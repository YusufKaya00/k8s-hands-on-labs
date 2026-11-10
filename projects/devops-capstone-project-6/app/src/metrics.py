"""SupplyShield Prometheus metrik tanımları (`ss_` öneki ile tek merkezden yönetilir).

Neden tek dosyada?
Grafana panelleri ve Prometheus alarm kuralları bu metrik isimlerine (`ss_*`) bağlıdır.
Başlangıçta tüm etiket kombinasyonları sıfırlanır (`0`), böylece ilk istek gelmeden önce
bile Prometheus serileri mevcut olur ve `absent()` kaynaklı sahte alarmlar önlenir.
"""
from prometheus_client import Counter, Gauge, Histogram

DEPENDENCIES = ("postgres", "redis", "harbor")

HTTP_REQUESTS = Counter(
    "ss_http_requests_total",
    "SupplyShield HTTP istek sayısı",
    ["method", "endpoint", "status"],
)

HTTP_DURATION = Histogram(
    "ss_http_request_duration_seconds",
    "SupplyShield HTTP istek yanıt süresi (saniye)",
    ["endpoint"],
    buckets=(0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0),
)

DEP_UP = Gauge(
    "ss_dependency_up",
    "Alt yapı bağımlılığı erişilebilir mi? (1=UP, 0=DOWN)",
    ["dependency"],
)

DEP_LATENCY = Histogram(
    "ss_dependency_latency_seconds",
    "Arka plan sağlık kontrolü (health prober) bağımlılık gecikmesi (saniye)",
    ["dependency"],
    buckets=(0.002, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.0),
)

ARTIFACTS_VERIFIED = Counter(
    "ss_artifacts_verified_total",
    "Harbor + Trivy doğrulamasından geçen konteyner artefakt sayısı",
    ["trivy_status"],
)

ORDERS_CREATED = Counter(
    "ss_orders_created_total",
    "Oluşturulan yazılım tedarik / lisans siparişi sayısı",
    ["status"],
)

# Başlangıç etiketlerini ilklendir (Dashboard ve alarmlarda seri kaybını önler)
for _dep in DEPENDENCIES:
    DEP_UP.labels(dependency=_dep).set(0)

for _trivy_st in ("PASSED", "WARN", "BLOCKED"):
    ARTIFACTS_VERIFIED.labels(trivy_status=_trivy_st)

for _ord_st in ("created", "degraded", "failed"):
    ORDERS_CREATED.labels(status=_ord_st)
