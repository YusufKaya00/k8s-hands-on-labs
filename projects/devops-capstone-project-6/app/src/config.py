"""Konfigürasyon: 12-Factor App prensibi gereği TÜM ayarlar ortam değişkenlerinden okunur.

Neden prod DevSecOps ortamında böyle?
Aynı imaj (`harbor.MASTER_IP.nip.io/supplyshield/supplyshield-api`) Jenkins tarafından
bir kez derlenir, Trivy ile taranır ve hiç değiştirilmeden dev/stage/prod ortamlarına
taşınır; ortam farkları yalnızca Helm `values.yaml` -> Kubernetes `env` üzerinden verilir.
"""
import os


def _env(name: str, default: str) -> str:
    return os.getenv(name, default)


SERVICE_NAME = _env("SERVICE_NAME", "SupplyShield DevSecOps API")
APP_VERSION = _env("APP_VERSION", "1.0.0")
PORT = int(_env("PORT", "8000"))

# Harbor Özel Konteyner Kayıt Defteri (Private OCI Registry) bilgileri
IMAGE_REGISTRY = _env("IMAGE_REGISTRY", "harbor.MASTER_IP.nip.io")
HARBOR_URL = _env("HARBOR_URL", "http://harbor-core.harbor.svc.cluster.local")

# PostgreSQL (Sistem Kayıt Defteri - System of Record: `data` namespace)
POSTGRES_HOST = _env("POSTGRES_HOST", "postgres-postgresql.data.svc.cluster.local")
POSTGRES_PORT = int(_env("POSTGRES_PORT", "5432"))
POSTGRES_DB = _env("POSTGRES_DB", "supplyshield")
POSTGRES_USER = _env("POSTGRES_USER", "supplyshield")
POSTGRES_PASSWORD = _env("POSTGRES_PASSWORD", "AdminPassword2026!")

# Redis (Önbellek Katmanı - Cache-Aside: `data` namespace)
REDIS_HOST = _env("REDIS_HOST", "redis-master.data.svc.cluster.local")
REDIS_PORT = int(_env("REDIS_PORT", "6379"))
REDIS_PASSWORD = _env("REDIS_PASSWORD", "AdminPassword2026!")
REDIS_CACHE_TTL = int(_env("REDIS_CACHE_TTL", "300"))

# Arka plan sağlık kontrolü ve zaman aşımı ayarları (<2ms `/metrics` yanıtı için)
DEP_TIMEOUT_SECONDS = float(_env("DEP_TIMEOUT_SECONDS", "2.0"))
HEALTH_PROBE_INTERVAL = float(_env("HEALTH_PROBE_INTERVAL", "5.0"))
