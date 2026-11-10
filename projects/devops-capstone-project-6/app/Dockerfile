# ==============================================================================
# SUPPLYSHIELD — GÜVENLİK SIKILAŞTIRILMIŞ (HARDENED) DOCKERFILE
# ==============================================================================
# Neden prod DevSecOps ortamında böyle tasarlanır?
# 1. Küçük Saldırı Yüzeyi (Minimal Attack Surface): `python:3.11-slim` taban imajı
#    kullanılarak gereksiz derleyiciler (gcc, make) ve kabuk araçları dışarıda
#    bırakılır; böylece Trivy taramasında ortaya çıkacak OS kaynaklı CVE sayısı
#    minimuma indirilir.
# 2. İşletim Sistemi Güvenlik Yamaları (`apt-get upgrade -y`): Taban imaj yayınlandıktan
#    sonra çıkan Debian güvenlik yamaları build anında uygulanır ve apt önbelleği
#    temizlenir (Harbor Trivy tarama kapısından sıfır CRITICAL zafiyetle geçmek için).
# 3. Katman Önbellekleme (Layer Caching): `requirements.txt` uygulama kodundan
#    (`src/`) ÖNCE kopyalanır; kod değiştiğinde Kaniko paketleri yeniden indirmez.
# 4. Yetkisiz (Non-Root) Kullanıcı (`UID 10001`): Konteyner asla `root` (UID 0)
#    olarak çalışmaz. Olası bir konteyner kaçış (Container Escape) zafiyetinde
#    saldırgan worker düğümünde (`vm-worker-app`) root yetkisi elde edemez.
# ==============================================================================

FROM python:3.11-slim

# PYTHONDONTWRITEBYTECODE=1 -> .pyc dosyaları diske yazılmaz (temiz dosya sistemi)
# PYTHONUNBUFFERED=1        -> stdout/stderr logları tamponlanmadan anında `kubectl logs`'a düşer
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    APP_HOME=/app

WORKDIR ${APP_HOME}

# İşletim sistemi güvenlik yamalarını uygula ve apt önbelleğini temizle (Trivy HIGH/CRITICAL CVE önlemi)
RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Kurumsal DevSecOps standardı gereği UID 10001 olan yetkisiz (non-root) kullanıcı oluştur
RUN groupadd --gid 10001 appuser && \
    useradd --uid 10001 --gid 10001 --shell /sbin/nologin --create-home appuser

# Önce bağımlılıkları kopyala ve kur (Kaniko katman önbelleklemesi)
COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

# Uygulama kaynak kodunu (`src/`) ve birim testlerini (`tests/`) kopyala, sahipliğini `appuser:appuser` yap
COPY --chown=appuser:appuser src/ ./src/
COPY --chown=appuser:appuser tests/ ./tests/

# Root yetkilerini bırak: UID 10001 ile çalış
USER 10001

EXPOSE 8000

# Uvicorn ASGI sunucusunu başlat
CMD ["uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8000"]
