# VortexGrid v1.0 (Lab 43) — Multi-Layer Cascading Incident Triage

- [🇹🇷 Türkçe](#-türkçe)
- [🇬🇧 English](#-english)

---

## 🇹🇷 Türkçe

### Senaryo Özeti

**VortexGrid v1.0**, üç namespace (`vortex-app`, `vortex-data`, `vortex-ops`) üzerine yayılmış bir finans/veri işleme platformudur. Trafik doğrudan `ingress-nginx` üzerinden `vortex-app` servislerine ulaşır (`Ingress -> Service -> Pod`).

Bu labdaki olaylar **5 bağımsız çok katmanlı zincir (toplam 10 kök neden)** şeklinde kurgulanmıştır: çoğu bileşende ilk engeli çözdüğünüzde arkasındaki ikinci gizli katman ortaya çıkar.

### Başlatma

```bash
cd troubleshoot/k8-troubleshoot-43
chmod +x setup.sh check.sh cleanup.sh broken-manifests/setup-broken.sh
./setup.sh
```

Mevcut bir küme üzerinde Terraform çalıştırmadan başlatmak için:

```bash
./setup.sh --skip-terraform
```

### Bildirilen Arıza Belirtileri (Triage Tickets)

1. **Zincir 1 — `GET /api/v1/quote` (`gateway-api` → `pricing-svc`):**
   - Müşteri istekleri dışarıdan `502 Bad Gateway` dönüyor.
   - `pricing-svc` ve `gateway-api` pod durumları ile arka uç iletişimini uçtan uca doğrulayın.
2. **Zincir 2 — `GET /ledger/health` (`ledger-api` → `ledger-db`):**
   - `vortex-data` altındaki `ledger-db` StatefulSet replikaları ayağa kalkmıyor ve `ledger-api` veritabanı düğümüne bağlanamıyor.
3. **Zincir 3 — `batch-reconciler` (`vortex-ops`):**
   - Dakikada bir çalışması gereken uzlaştırma `CronJob`'ı `ConfigMap/reconcile-status` durumunu `reconciled` değerine güncelleyemiyor.
4. **Zincir 4 — `GET /stream/status` (`stream-worker`):**
   - 3 replikalı `stream-worker` deployment'ında eksik podlar zamanlanamıyor ve `/stream/status` endpoint'i sağlıklı yanıt vermiyor.
5. **Zincir 5 — `metrics-collector` (`vortex-ops` → `vortex-app`):**
   - `metrics-collector` podu `vortex-ops` içinde sağlıklı çalışmıyor ve `gateway-api` metriklerini kazıyamıyor.

### Doğrulama ve Sıfırlama

```bash
# Kör mod durum kontrolü (root-cause spoiler içermez)
./check.sh

# Takıldığınız noktada yönlendirici ipuçları için
./check.sh --hints

# Labı başlangıçtaki arızalı haline sıfırlamak için
./broken-manifests/setup-broken.sh

# Tüm kaynakları temizlemek için
./cleanup.sh
```

> Tam kök neden analizi ve çözümler için [SOLUTION.md](./SOLUTION.md) dosyasına bakın.

---

## 🇬🇧 English

### Scenario Overview

**VortexGrid v1.0** runs across three namespaces (`vortex-app`, `vortex-data`, `vortex-ops`) using direct `Ingress -> Service -> Pod` routing via `ingress-nginx`.

The environment contains **5 cascading multi-layer incident chains (10 root causes total)**: resolving the surface issue in a chain uncovers a second underlying defect.

### Setup

```bash
cd troubleshoot/k8-troubleshoot-43
chmod +x setup.sh check.sh cleanup.sh broken-manifests/setup-broken.sh
./setup.sh
# Or on an existing cluster:
./setup.sh --skip-terraform
```

### Incident Symptoms

1. **Chain 1 (`GET /api/v1/quote`):** External requests fail with `502`. Verify end-to-end routing from Ingress through `gateway-api` to `pricing-svc`.
2. **Chain 2 (`GET /ledger/health`):** `StatefulSet/ledger-db` in `vortex-data` fails to start all pods cleanly, and `ledger-api` reports the ledger unreachable.
3. **Chain 3 (`batch-reconciler` in `vortex-ops`):** The scheduled CronJob does not update `ConfigMap/reconcile-status` to `reconciled`.
4. **Chain 4 (`GET /stream/status`):** Not all 3 `stream-worker` replicas schedule, and `/stream/status` fails health checks.
5. **Chain 5 (`metrics-collector` in `vortex-ops`):** `metrics-collector` fails to schedule/become Ready and cannot scrape `gateway-api` metrics in `vortex-app`.

### Verification & Reset

```bash
./check.sh          # Blind-mode verification (zero spoilers)
./check.sh --hints  # Directional clues
./broken-manifests/setup-broken.sh
./cleanup.sh
```

> Full root-cause analysis and fixes are documented in [SOLUTION.md](./SOLUTION.md).
