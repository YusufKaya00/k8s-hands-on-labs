"""SupplyShield API Birim Testleri (`tests/test_main.py`).

Neden bu testler kritik?
Jenkins CI/CD hattının 2. Aşamasında (Stage 2 — Unit Tests & SAST Security Scan),
Kaniko ile Docker imajı derlenmeden ÖNCE `pytest` tarafından çalıştırılır.
Eğer `/healthz`, `/` veya `/metrics` uç noktalarından herhangi biri beklenen
şemayı veya Prometheus metriklerini (`ss_*`) döndürmezse pipeline anında durur
ve bozuk kodun Harbor kayıt defterine yüklenmesi engellenir (Shift-Left Testing).
"""
from fastapi.testclient import TestClient

from src.main import app

client = TestClient(app)


def test_healthz_liveness_probe() -> None:
    """`/healthz` uç noktası dış veritabanlarına ihtiyaç duymadan 200 OK ve `status=alive` dönmelidir."""
    response = client.get("/healthz")
    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "alive"
    assert body["service"] == "SupplyShield DevSecOps API"
    assert "pod" in body


def test_root_platform_summary() -> None:
    """`GET /` uç noktası servis adını, versiyonu, Harbor imaj kayıt defterini ve bağımlılık özetini dönmelidir."""
    response = client.get("/")
    assert response.status_code == 200
    body = response.json()
    assert body["service"] == "SupplyShield DevSecOps API"
    assert "version" in body
    assert "harbor." in body["image_registry"]
    assert "dependencies" in body
    for dep in ("postgres", "redis", "harbor"):
        assert dep in body["dependencies"]


def test_prometheus_metrics_endpoint() -> None:
    """`GET /metrics` uç noktası tüm zorunlu `ss_*` Prometheus metrik ailelerini içermelidir."""
    # Önce bir HTTP isteği atarak middleware metriklerinin kaydedilmesini sağla
    client.get("/healthz")
    response = client.get("/metrics")
    assert response.status_code == 200
    text = response.text
    assert "ss_http_requests_total" in text
    assert "ss_http_request_duration_seconds" in text
    assert "ss_dependency_up" in text
    assert "ss_artifacts_verified_total" in text
    assert "ss_orders_created_total" in text


def test_artifact_verify_and_orders_endpoints() -> None:
    """`POST /api/artifacts/verify` ve `POST /api/orders` uç noktaları DB yokken bile
    graceful fallback ile 201 Created dönmeli ve metrikleri artırmalıdır."""
    verify_res = client.post(
        "/api/artifacts/verify",
        json={
            "image_name": "harbor.MASTER_IP.nip.io/supplyshield/supplyshield-api:42",
            "digest": "sha256:1234567890abcdef",
            "trivy_status": "PASSED",
            "critical_cves": 0,
            "high_cves": 0,
            "build_number": "42",
        },
    )
    assert verify_res.status_code == 201
    assert verify_res.json()["status"] == "verified"

    list_art_res = client.get("/api/artifacts")
    assert list_art_res.status_code == 200
    assert list_art_res.json()["count"] >= 1

    order_res = client.post(
        "/api/orders",
        json={
            "customer_id": "unit-test-team",
            "package_name": "trivy-enterprise-feed",
            "quantity": 2,
            "amount": 199.50,
        },
    )
    assert order_res.status_code == 201
    assert "order" in order_res.json()
