"""SupplyShield DevSecOps & Software Supply Chain API (`src.main:app`).

Bu mikroservis, RKE2 üzerinde çalışan DevSecOps platformunun (Harbor + Trivy + Jenkins + ArgoCD)
canlı iş yükü katmanını oluşturur:
1. Liveness (`/healthz`) ve Readiness (`/readyz`) Ayrımı:
   - `/healthz`: Yalnızca Python/Uvicorn sürecinin hayatta olduğunu kontrol eder (ASLA DB'ye gitmez).
   - `/readyz`: Kritik bağımlılık olan PostgreSQL bağlantısını doğrular.
2. Arka Plan Sağlık Tarayıcısı (`BackgroundHealthProber` Thread):
   - Her 5 saniyede bir `postgres`, `redis` ve `harbor` bağımlılıklarını arka planda yoklar,
     `ss_dependency_up` ve `ss_dependency_latency_seconds` metriklerini bellekte günceller.
   - Böylece `/metrics` uç noktası çağrıldığında ağ I/O beklemez ve <2ms içinde yanıt döner!
3. Konteyner Artefakt Doğrulama Kayıtları (`/api/artifacts/verify` & `/api/artifacts`):
   - Jenkins CI/CD hattının 7. aşaması (Post-Deploy Smoke Test), Harbor Trivy taramasından geçen
     yeni konteyner imajını (`image_name`, `digest`, `trivy_status`) bu API üzerinden PostgreSQL'e
     kaydeder ve Redis önbelleğine yazar.
4. Yazılım Tedarik ve Lisans Siparişleri (`/api/orders`):
   - Kurumsal yazılım bileşeni/lisans siparişlerini PostgreSQL `supply_orders` tablosunda saklar.
"""
from contextlib import asynccontextmanager
from datetime import datetime, timezone
import json
import logging
import socket
import threading
import time
from typing import Any, Dict, List, Optional
from urllib.parse import urlparse
import uuid

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse, Response
import psycopg2
from psycopg2.extras import RealDictCursor
from prometheus_client import CONTENT_TYPE_LATEST, generate_latest
from pydantic import BaseModel, Field
import redis

from . import config
from .metrics import (
    ARTIFACTS_VERIFIED,
    DEP_LATENCY,
    DEP_UP,
    HTTP_DURATION,
    HTTP_REQUESTS,
    ORDERS_CREATED,
)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger("supplyshield.main")

# Bellek içi önbellek ve kilit (BackgroundHealthProber tarafından 5 sn'de bir güncellenir)
_STATUS_LOCK = threading.Lock()
_CACHED_DEP_STATUS: Dict[str, Dict[str, Any]] = {
    "postgres": {"status": "UNKNOWN", "latency_ms": 0.0, "detail": "Not probed yet"},
    "redis": {"status": "UNKNOWN", "latency_ms": 0.0, "detail": "Not probed yet"},
    "harbor": {"status": "UNKNOWN", "latency_ms": 0.0, "detail": "Not probed yet"},
}
_PROBER_STARTED = False
_SCHEMA_INITIALIZED = False

# DB erişilemediğinde birim testlerin ve dejenere modun çalışabilmesi için bellek içi yedek listeler
_FALLBACK_ARTIFACTS: List[Dict[str, Any]] = []
_FALLBACK_ORDERS: List[Dict[str, Any]] = []


# ==============================================================================
# PYDANTIC VERİ MODELLERİ (İSTEK ŞEMALARI)
# ==============================================================================
class ArtifactVerifyRequest(BaseModel):
    """`POST /api/artifacts/verify` isteği için konteyner imaj doğrulama şeması."""
    image_name: str = Field(
        default="harbor.MASTER_IP.nip.io/supplyshield/supplyshield-api:1.0.0",
        description="Harbor üzerindeki tam konteyner imaj adı ve etiketi",
    )
    digest: str = Field(
        default="sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
        description="OCI imaj SHA256 özeti (digest)",
    )
    trivy_status: str = Field(
        default="PASSED",
        description="Harbor Trivy tarama sonucu (PASSED | WARN | BLOCKED)",
    )
    critical_cves: int = Field(default=0, ge=0, description="Tespit edilen CRITICAL CVE sayısı")
    high_cves: int = Field(default=0, ge=0, description="Tespit edilen HIGH CVE sayısı")
    build_number: str = Field(default="1", description="Jenkins BUILD_NUMBER değeri")


class SupplyOrderRequest(BaseModel):
    """`POST /api/orders` isteği için yazılım tedarik / lisans siparişi şeması."""
    customer_id: str = Field(default="secops-team-01", description="Siparişi veren birim/müşteri")
    package_name: str = Field(default="supplyshield-enterprise-scanner", description="Yazılım paketi veya lisans adı")
    quantity: int = Field(default=1, ge=1, description="Lisans / düğüm adedi")
    amount: float = Field(default=249.90, gt=0, description="Toplam tutar (USD)")


# ==============================================================================
# VERİTABANI VE ÖNBELLEK YARDIMCI FONKSİYONLARI
# ==============================================================================
def _get_pg_conn():
    """Kısa zaman aşımlı PostgreSQL bağlantısı açar."""
    timeout_int = max(1, int(config.DEP_TIMEOUT_SECONDS))
    return psycopg2.connect(
        host=config.POSTGRES_HOST,
        port=config.POSTGRES_PORT,
        dbname=config.POSTGRES_DB,
        user=config.POSTGRES_USER,
        password=config.POSTGRES_PASSWORD,
        connect_timeout=timeout_int,
    )


def _get_redis_client() -> redis.Redis:
    """Kısa zaman aşımlı Redis istemcisi döndürür."""
    return redis.Redis(
        host=config.REDIS_HOST,
        port=config.REDIS_PORT,
        password=config.REDIS_PASSWORD or None,
        socket_connect_timeout=config.DEP_TIMEOUT_SECONDS,
        socket_timeout=config.DEP_TIMEOUT_SECONDS,
        decode_responses=True,
    )


def ensure_db_schema() -> bool:
    """PostgreSQL üzerinde `verified_artifacts` ve `supply_orders` tablolarını idempotent oluşturur."""
    global _SCHEMA_INITIALIZED
    if _SCHEMA_INITIALIZED:
        return True
    try:
        conn = _get_pg_conn()
        with conn:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    CREATE TABLE IF NOT EXISTS verified_artifacts (
                        id SERIAL PRIMARY KEY,
                        artifact_id VARCHAR(64) UNIQUE NOT NULL,
                        image_name TEXT NOT NULL,
                        digest TEXT NOT NULL,
                        trivy_status VARCHAR(32) NOT NULL,
                        critical_cves INT NOT NULL DEFAULT 0,
                        high_cves INT NOT NULL DEFAULT 0,
                        build_number VARCHAR(32) NOT NULL DEFAULT '1',
                        verified_by_pod VARCHAR(128) NOT NULL,
                        verified_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
                    );
                    """
                )
                cur.execute(
                    """
                    CREATE TABLE IF NOT EXISTS supply_orders (
                        id SERIAL PRIMARY KEY,
                        order_id VARCHAR(64) UNIQUE NOT NULL,
                        customer_id VARCHAR(128) NOT NULL,
                        package_name VARCHAR(256) NOT NULL,
                        quantity INT NOT NULL,
                        amount NUMERIC(12, 2) NOT NULL,
                        pod_name VARCHAR(128) NOT NULL,
                        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
                    );
                    """
                )
        conn.close()
        _SCHEMA_INITIALIZED = True
        return True
    except Exception as exc:
        logger.debug("PostgreSQL şema hazırlığı henüz tamamlanamadı: %s", exc)
        return False


# ==============================================================================
# ARKA PLAN SAĞLIK KONTROL İŞ PARÇACIĞI (BACKGROUND HEALTH PROBER)
# ==============================================================================
def _probe_postgres() -> None:
    start = time.perf_counter()
    try:
        conn = _get_pg_conn()
        with conn.cursor() as cur:
            cur.execute("SELECT 1;")
            cur.fetchone()
        conn.close()
        ensure_db_schema()
        elapsed = time.perf_counter() - start
        DEP_UP.labels(dependency="postgres").set(1)
        DEP_LATENCY.labels(dependency="postgres").observe(elapsed)
        with _STATUS_LOCK:
            _CACHED_DEP_STATUS["postgres"] = {
                "status": "UP",
                "latency_ms": round(elapsed * 1000, 2),
                "host": f"{config.POSTGRES_HOST}:{config.POSTGRES_PORT}",
            }
    except Exception as exc:
        elapsed = time.perf_counter() - start
        DEP_UP.labels(dependency="postgres").set(0)
        DEP_LATENCY.labels(dependency="postgres").observe(elapsed)
        with _STATUS_LOCK:
            _CACHED_DEP_STATUS["postgres"] = {
                "status": "DOWN",
                "latency_ms": round(elapsed * 1000, 2),
                "error": str(exc)[:120],
            }


def _probe_redis() -> None:
    start = time.perf_counter()
    try:
        client = _get_redis_client()
        client.ping()
        elapsed = time.perf_counter() - start
        DEP_UP.labels(dependency="redis").set(1)
        DEP_LATENCY.labels(dependency="redis").observe(elapsed)
        with _STATUS_LOCK:
            _CACHED_DEP_STATUS["redis"] = {
                "status": "UP",
                "latency_ms": round(elapsed * 1000, 2),
                "host": f"{config.REDIS_HOST}:{config.REDIS_PORT}",
            }
    except Exception as exc:
        elapsed = time.perf_counter() - start
        DEP_UP.labels(dependency="redis").set(0)
        DEP_LATENCY.labels(dependency="redis").observe(elapsed)
        with _STATUS_LOCK:
            _CACHED_DEP_STATUS["redis"] = {
                "status": "DOWN",
                "latency_ms": round(elapsed * 1000, 2),
                "error": str(exc)[:120],
            }


def _probe_harbor() -> None:
    start = time.perf_counter()
    try:
        parsed = urlparse(config.HARBOR_URL)
        host = parsed.hostname or config.IMAGE_REGISTRY.split("/")[0]
        port = parsed.port or (443 if parsed.scheme == "https" else 80)
        with socket.create_connection((host, port), timeout=config.DEP_TIMEOUT_SECONDS):
            pass
        elapsed = time.perf_counter() - start
        DEP_UP.labels(dependency="harbor").set(1)
        DEP_LATENCY.labels(dependency="harbor").observe(elapsed)
        with _STATUS_LOCK:
            _CACHED_DEP_STATUS["harbor"] = {
                "status": "UP",
                "latency_ms": round(elapsed * 1000, 2),
                "registry": config.IMAGE_REGISTRY,
            }
    except Exception as exc:
        elapsed = time.perf_counter() - start
        DEP_UP.labels(dependency="harbor").set(0)
        DEP_LATENCY.labels(dependency="harbor").observe(elapsed)
        with _STATUS_LOCK:
            _CACHED_DEP_STATUS["harbor"] = {
                "status": "DOWN",
                "latency_ms": round(elapsed * 1000, 2),
                "registry": config.IMAGE_REGISTRY,
                "error": str(exc)[:120],
            }


def probe_all_dependencies_once() -> None:
    """Tüm bağımlılıkları tek sefer yoklar ve Prometheus Gauge/Histogram metriklerini günceller."""
    _probe_postgres()
    _probe_redis()
    _probe_harbor()


def _health_probe_loop() -> None:
    """Her `HEALTH_PROBE_INTERVAL` (5 sn) aralıkla bağımlılıkları arka planda yoklayan daemon döngüsü."""
    while True:
        try:
            probe_all_dependencies_once()
        except Exception as exc:
            logger.warning("Health prober döngüsünde beklenmeyen hata: %s", exc)
        time.sleep(config.HEALTH_PROBE_INTERVAL)


def start_health_prober() -> None:
    """Arka plan sağlık kontrol thread'ini (daemon) yalnızca bir kez başlatır."""
    global _PROBER_STARTED
    if _PROBER_STARTED:
        return
    _PROBER_STARTED = True
    thread = threading.Thread(
        target=_health_probe_loop,
        name="ss-background-health-prober",
        daemon=True,
    )
    thread.start()


@asynccontextmanager
async def lifespan(_app: FastAPI):
    """Uygulama başlarken arka plan sağlık tarayıcısını devreye alır."""
    start_health_prober()
    yield


app = FastAPI(
    title="SupplyShield DevSecOps & Software Supply Chain API",
    description="Proje 6: Harbor + Trivy + Jenkins + Kaniko + ArgoCD + RKE2 Güvenli Yazılım Tedarik Zinciri API",
    version=config.APP_VERSION,
    lifespan=lifespan,
)


@app.middleware("http")
async def prometheus_http_middleware(request: Request, call_next):
    """Her HTTP isteğinin süresini (`ss_http_request_duration_seconds`) ve durum kodunu
    (`ss_http_requests_total`) otomatik olarak kaydeder."""
    start_ts = time.perf_counter()
    endpoint = request.url.path
    method = request.method
    status_code = 500
    try:
        response = await call_next(request)
        status_code = response.status_code
        return response
    finally:
        duration = time.perf_counter() - start_ts
        HTTP_DURATION.labels(endpoint=endpoint).observe(duration)
        HTTP_REQUESTS.labels(method=method, endpoint=endpoint, status=str(status_code)).inc()


# ==============================================================================
# 1. PLATFORM ÖZETİ (`GET /`), LIVENESS (`/healthz`), READINESS (`/readyz`), METRICS (`/metrics`)
# ==============================================================================
@app.get("/")
def root_summary() -> JSONResponse:
    """Platform özetini, imaj kayıt defterini (`harbor.MASTER_IP.nip.io`) ve bağımlılık durumlarını döndürür."""
    start_health_prober()
    with _STATUS_LOCK:
        deps_copy = dict(_CACHED_DEP_STATUS)
    return JSONResponse(
        status_code=200,
        content={
            "service": config.SERVICE_NAME,
            "version": config.APP_VERSION,
            "image_registry": config.IMAGE_REGISTRY,
            "pod": socket.gethostname(),
            "timestamp_utc": datetime.now(timezone.utc).isoformat(),
            "dependencies": deps_copy,
        },
    )


@app.get("/healthz")
def healthz() -> JSONResponse:
    """Kubernetes Liveness Probe: Yalnızca Python/Uvicorn sürecinin hayatta olduğunu doğrular.
    Dış bağımlılıkları KONTROL ETMEZ; böylece veritabanı bakımında pod restart fırtınası yaşanmaz."""
    return JSONResponse(
        status_code=200,
        content={
            "status": "alive",
            "service": config.SERVICE_NAME,
            "pod": socket.gethostname(),
        },
    )


@app.get("/readyz")
def readyz() -> JSONResponse:
    """Kubernetes Readiness Probe: Kritik bağımlılık olan PostgreSQL bağlantısını doğrular."""
    try:
        conn = _get_pg_conn()
        with conn.cursor() as cur:
            cur.execute("SELECT 1;")
            cur.fetchone()
        conn.close()
        return JSONResponse(
            status_code=200,
            content={
                "status": "ready",
                "postgres": "UP",
                "pod": socket.gethostname(),
            },
        )
    except Exception as exc:
        return JSONResponse(
            status_code=503,
            content={
                "status": "not_ready",
                "postgres": "DOWN",
                "error": str(exc)[:120],
                "pod": socket.gethostname(),
            },
        )


@app.get("/metrics")
def metrics() -> Response:
    """Prometheus ServiceMonitor uç noktası.
    Arka plan thread'i metrikleri bellekte hazır tuttuğu için <2ms içinde yanıt verir."""
    start_health_prober()
    return Response(content=generate_latest(), media_type=CONTENT_TYPE_LATEST)


# ==============================================================================
# 2. KONTEYNER ARTEFAKT DOĞRULAMA UÇ NOKTALARI (`/api/artifacts/verify` & `/api/artifacts`)
# ==============================================================================
@app.post("/api/artifacts/verify")
def verify_artifact(payload: Optional[ArtifactVerifyRequest] = None) -> JSONResponse:
    """Harbor + Trivy taramasından geçen bir konteyner imajının doğrulama kaydını
    PostgreSQL'e yazar ve Redis üzerinde önbelleğe alır."""
    req = payload or ArtifactVerifyRequest()
    normalized_status = req.trivy_status.upper()
    if normalized_status not in ("PASSED", "WARN", "BLOCKED"):
        normalized_status = "PASSED"

    artifact_id = f"ART-{uuid.uuid4().hex[:10].upper()}"
    verified_at = datetime.now(timezone.utc).isoformat()
    record: Dict[str, Any] = {
        "artifact_id": artifact_id,
        "image_name": req.image_name,
        "digest": req.digest,
        "trivy_status": normalized_status,
        "critical_cves": req.critical_cves,
        "high_cves": req.high_cves,
        "build_number": req.build_number,
        "verified_by_pod": socket.gethostname(),
        "verified_at": verified_at,
    }

    pg_stored = False
    redis_cached = False

    try:
        ensure_db_schema()
        conn = _get_pg_conn()
        with conn:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    INSERT INTO verified_artifacts (
                        artifact_id, image_name, digest, trivy_status,
                        critical_cves, high_cves, build_number, verified_by_pod
                    ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s);
                    """,
                    (
                        artifact_id,
                        req.image_name,
                        req.digest,
                        normalized_status,
                        req.critical_cves,
                        req.high_cves,
                        req.build_number,
                        record["verified_by_pod"],
                    ),
                )
        conn.close()
        pg_stored = True
    except Exception as exc:
        logger.warning("PostgreSQL artefakt yazımı başarısız, bellek içi yedeğe kaydediliyor: %s", exc)
        _FALLBACK_ARTIFACTS.insert(0, record)

    try:
        r_client = _get_redis_client()
        r_client.setex(
            f"supplyshield:artifact:{artifact_id}",
            config.REDIS_CACHE_TTL,
            json.dumps(record),
        )
        r_client.lpush("supplyshield:artifacts:recent", json.dumps(record))
        r_client.ltrim("supplyshield:artifacts:recent", 0, 49)
        redis_cached = True
    except Exception as exc:
        logger.debug("Redis artefakt önbellekleme atlandı: %s", exc)

    ARTIFACTS_VERIFIED.labels(trivy_status=normalized_status).inc()

    return JSONResponse(
        status_code=201,
        content={
            "status": "verified",
            "artifact": record,
            "storage": {
                "postgres": "STORED" if pg_stored else "FALLBACK_MEMORY",
                "redis": "CACHED" if redis_cached else "SKIPPED",
            },
        },
    )


@app.get("/api/artifacts")
def list_artifacts() -> JSONResponse:
    """Doğrulanmış konteyner imaj artefaktlarını önce Redis önbelleğinden, yoksa PostgreSQL'den listeler."""
    # 1. Önce Redis önbelleğini dene (Cache-Aside)
    try:
        r_client = _get_redis_client()
        cached_items = r_client.lrange("supplyshield:artifacts:recent", 0, 49)
        if cached_items:
            parsed = [json.loads(item) for item in cached_items]
            return JSONResponse(
                status_code=200,
                content={
                    "source": "redis_cache",
                    "count": len(parsed),
                    "artifacts": parsed,
                },
            )
    except Exception as exc:
        logger.debug("Redis okuma atlandı, PostgreSQL'e düşülüyor: %s", exc)

    # 2. PostgreSQL'den oku
    try:
        ensure_db_schema()
        conn = _get_pg_conn()
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                """
                SELECT artifact_id, image_name, digest, trivy_status,
                       critical_cves, high_cves, build_number, verified_by_pod,
                       verified_at::text AS verified_at
                FROM verified_artifacts
                ORDER BY id DESC
                LIMIT 50;
                """
            )
            rows = [dict(r) for r in cur.fetchall()]
        conn.close()
        return JSONResponse(
            status_code=200,
            content={
                "source": "postgresql",
                "count": len(rows),
                "artifacts": rows,
            },
        )
    except Exception as exc:
        logger.debug("PostgreSQL okuma başarısız, bellek içi yedek dönülüyor: %s", exc)
        return JSONResponse(
            status_code=200,
            content={
                "source": "fallback_memory",
                "count": len(_FALLBACK_ARTIFACTS),
                "artifacts": _FALLBACK_ARTIFACTS[:50],
            },
        )


# ==============================================================================
# 3. YAZILIM TEDARİK / LİSANS SİPARİŞ UÇ NOKTALARI (`POST /api/orders` & `GET /api/orders`)
# ==============================================================================
@app.post("/api/orders")
def create_order(payload: Optional[SupplyOrderRequest] = None) -> JSONResponse:
    """Yeni bir yazılım tedarik/lisans siparişi oluşturur ve PostgreSQL'e kaydeder."""
    req = payload or SupplyOrderRequest()
    order_id = f"ORD-{uuid.uuid4().hex[:10].upper()}"
    created_at = datetime.now(timezone.utc).isoformat()
    order_doc: Dict[str, Any] = {
        "order_id": order_id,
        "customer_id": req.customer_id,
        "package_name": req.package_name,
        "quantity": req.quantity,
        "amount": float(req.amount),
        "pod_name": socket.gethostname(),
        "created_at": created_at,
    }

    try:
        ensure_db_schema()
        conn = _get_pg_conn()
        with conn:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    INSERT INTO supply_orders (
                        order_id, customer_id, package_name, quantity, amount, pod_name
                    ) VALUES (%s, %s, %s, %s, %s, %s);
                    """,
                    (
                        order_id,
                        req.customer_id,
                        req.package_name,
                        req.quantity,
                        req.amount,
                        order_doc["pod_name"],
                    ),
                )
        conn.close()
        ORDERS_CREATED.labels(status="created").inc()
        return JSONResponse(
            status_code=201,
            content={"status": "created", "storage": "postgresql", "order": order_doc},
        )
    except Exception as exc:
        logger.warning("PostgreSQL sipariş yazımı başarısız, bellek içi yedeğe yazılıyor: %s", exc)
        _FALLBACK_ORDERS.insert(0, order_doc)
        ORDERS_CREATED.labels(status="degraded").inc()
        return JSONResponse(
            status_code=201,
            content={"status": "degraded", "storage": "fallback_memory", "order": order_doc},
        )


@app.get("/api/orders")
def list_orders() -> JSONResponse:
    """PostgreSQL'deki yazılım tedarik siparişlerini listeler."""
    try:
        ensure_db_schema()
        conn = _get_pg_conn()
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                """
                SELECT order_id, customer_id, package_name, quantity,
                       amount::float AS amount, pod_name, created_at::text AS created_at
                FROM supply_orders
                ORDER BY id DESC
                LIMIT 50;
                """
            )
            rows = [dict(r) for r in cur.fetchall()]
        conn.close()
        return JSONResponse(
            status_code=200,
            content={"source": "postgresql", "count": len(rows), "orders": rows},
        )
    except Exception as exc:
        logger.debug("PostgreSQL sipariş listeleme başarısız, bellek içi yedek dönülüyor: %s", exc)
        return JSONResponse(
            status_code=200,
            content={
                "source": "fallback_memory",
                "count": len(_FALLBACK_ORDERS),
                "orders": _FALLBACK_ORDERS[:50],
            },
        )
