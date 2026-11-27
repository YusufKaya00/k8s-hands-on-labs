# Chaos Troubleshooting Lab 7: Known / Unknown Chaos Matrix (LitmusChaos UI + Prometheus + Grafana)

- [🇹🇷 Türkçe](#-türkçe)
- [🇬🇧 English](#-english)

---

## 🇹🇷 Türkçe

Bu lab, Gremlin'in **"Chaos Engineering: the history, principles, and practice"** rehberindeki bilimsel kaosu gerçek Kubernetes ortamına taşır. Sadece "pod silmek" yerine her deneyi **Known / Unknown Matrisi** ve **Dağıtık Sistemlerin 8 Yanılgısı** çerçevesinde kurar, **ChaosCenter Web UI** üzerinden tek tıkla çalıştırır ve sonucunu canlı **Prometheus + Grafana** panellerinden okursun.

---

### 1. Teori: Known / Unknown Matrisi ve Ne Öğreniyoruz?

| Kadran | Tanım (Türkçe) | Örnek Soru ("What could go wrong?") | Bu Labdaki Deney |
| :--- | :--- | :--- | :--- |
| **1. Known-Knowns** | Bildiğimiz ve davranışından emin olduğumuz durumlar | "2 replikalı `inventory-replica` podlarından 1'i ölürse sistem kesintisiz devam eder mi?" | `q1-known-known-replica-kill` |
| **2. Known-Unknowns** | Olacağını bildiğimiz ama **eşiğini/etkisini bilmediğimiz** durumlar | "Ağ gecikmesi (`latency`) kaç ms'ye çıkınca `1.5s` timeout patlar ve Retry Fırtınası başlar?" | `q2-known-unknown-latency-timeout` |
| **3. Unknown-Knowns** | Mimari olarak bildiğimiz ama pratik yük etkisini henüz ölçmediğimiz riskler | "2 replikanın **ikisi birden** düşerse `inventory-primary` tüm trafiği sırtlayabilir mi?" | `q3-unknown-known-double-replica-kill` |
| **4. Unknown-Unknowns** | Hesaba katmadığımız büyük kesintiler — önce koruma/fallback mühendisliği gerekir | "Hem `replica` hem `primary` DB aynı anda tamamen giderse Circuit Breaker + Redis fallback devreye girer mi?" | `q4-unknown-unknown-total-db-blackout` |

**Dağıtık Sistemlerin 8 Yanılgısından Hangilerini Test Ediyoruz?**
- *"Ağ güvenilirdir"* ve *"Gecikme sıfırdır (Latency is zero)"* → Q2 deneyinde gecikme arttıkça uygulamanın agresif retry atıp nasıl kendi kendini boğduğunu (**Retry Storm**) ve timeout sınırını görürsün.
- *"Topoloji değişmez"* → Q1, Q3 ve Q4 deneylerinde podlar ve endpoint'ler kaybolduğunda Kubernetes Service + failover + Circuit Breaker davranışını izlersin.

---

### 2. Ortam Mimarisi: Neyi, Neden Kurduk?

```text
  [ loadgen (~5 RPS sürekli trafik) ]
                   │
                   ▼
        +---------------------+
        |  checkout-api (x3)  | ──(timeout=1.5s, 1 retry)──> +-----------------------+
        |  + Circuit Breaker  |                              | inventory-replica (x2)|
        |  + PDB (minAvail:2) |                              | (/stock, /admin/delay)|
        +-----+---------+-----+                              +-----------------------+
              │         │
  (Failover)  │         └─(CB Open -> Fallback)─> [ cache-redis (:6379) ]
              ▼
   +----------------------+       (5s scrape)       +-------------+     +---------+
   | inventory-primary(x1)| <────────────────────── | Prometheus  | ──> | Grafana |
   +----------------------+   kubernetes_sd_configs |   (:9090)   |     | (:3000) |
                                                    +-------------+     +---------+
```

1. **StreamCart Mikroservis Yığını (`shop-chaos` namespace, [manifests/app-stack.yaml](./manifests/app-stack.yaml)):**
   - **`checkout-api` (`replicas: 3`, PDB `minAvailable: 2`):** İstekleri önce `inventory-replica`'ya atar (`1.5s` timeout + 1 retry). Başarısız olursa `inventory-primary`'ye failover yapar. Arka arkaya 4 tam hata görürse **Circuit Breaker** açar (`10s` cooldown) ve trafiği **`cache-redis`** üzerinden `200 OK` (`degraded-cache`) olarak döndürür.
   - **`inventory-replica` (`replicas: 2`) ve `inventory-primary` (`replicas: 1`):** Her iki katman da `prometheus.io/scrape: "true"` annotation'ı ile kendi QPS ve yapay gecikme metriklerini yayınlar.
   - **`loadgen`:** Saniyede ~5 istek üretir ki deney başlatmadığın anda bile Grafana panellerinde canlı baseline (yeşil çizgi) görebilesin.

2. **Observability Yığını (`monitoring` namespace, [manifests/observability.yaml](./manifests/observability.yaml)):**
   - **Prometheus (`prom/prometheus:v2.54.1`):** `kubernetes_sd_configs (role: pod)` ile `shop-chaos` içindeki podları otomatik keşfeder ve her 5 saniyede bir `/metrics` kazır. *(Bu sayede pod ölünce veya yeni pod gelince hedef listesi kendiliğinden güncellenir.)*
   - **Grafana (`grafana/grafana:11.2.2`):** Kurulum sırasında Prometheus veri kaynağı (`uid: Prometheus`) ve **6 panelli "Known-Unknown Chaos Matrix — StreamCart Live SRE Impact" Dashboard'u** otomatik yüklenir; manuel JSON import etmen gerekmez.

3. **LitmusChaos ChaosCenter Web UI (`litmus` namespace):**
   - Önceki tecrübelerden bildiğimiz 3 sorun bu kurulumda otomatik düzeltilmiştir:
     1. MongoDB 1 replika + `persistence: false` ile tek node Minikube'de hafif çalışır.
     2. Helm release adı `litmus` olduğu için oluşan `subscriber-config` `SERVER_ADDR` (`chaos-litmus-server-service`) DNS hatasını `setup.sh` otomatik `litmus-server-service`'e patch eder.
     3. [chaos/ui-workflows/](./chaos/ui-workflows/) altındaki 4 Workflow'da `podGC` **kapalıdır**, böylece deney bitince ChaosCenter **Logs** sekmesinde Python çıktılarını ve metrik özetini kayıpsız okuyabilirsin.

---

### 3. Kurulum ve Arayüzleri Açma

```bash
cd troubleshoot/chaos-troubleshooting-7
chmod +x setup.sh cleanup.sh
./setup.sh
```

Kurulum tamamlandıktan sonra 3 arayüzü lokale port-forward et:

```bash
kubectl -n litmus port-forward svc/litmus-frontend-service 9091:9091 >/tmp/litmus-pf.log 2>&1 &
kubectl -n monitoring port-forward svc/grafana 3000:3000 >/tmp/grafana-pf.log 2>&1 &
kubectl -n monitoring port-forward svc/prometheus 9090:9090 >/tmp/prom-pf.log 2>&1 &
```

- **LitmusChaos ChaosCenter:** `http://localhost:9091` → Giriş: **`admin` / `Litmus@123`** *(Giriş yaparken eski oturum kalmışsa Gizli Sekme kullan veya Site Verisini Temizle.)*
- **Grafana Dashboard:** `http://localhost:3000` → Giriş: **`admin` / `admin`** *(Ana sayfada **Known-Unknown Chaos Matrix** dashboard'u direkt açılır, sağ üstten `Last 15 minutes` ve `5s` refresh açık gelir.)*
- **Prometheus UI:** `http://localhost:9090` → **Status → Targets** altından `shop-chaos-pods` hedeflerini görebilirsin.

> **Kaos Öncesi Baseline Kontrolü (Grafana'da ne görmelisin?):**
> - Panel 1 (`Checkout Success vs Error RPS`): Sadece yeşil **`ok` ~5 req/s** çizgisi (`error=0`, `degraded=0`).
> - Panel 2 (`p95 Latency`): **`< 0.05s` (50ms altı)**.
> - Panel 3 (`Healthy Inventory`): **`healthy_replicas = 2`**, **`healthy_primary = 1`**.
> - Panel 4, 5, 6: `primary_qps`, `failover_rps`, `db_retries_per_sec` ve `circuit_breaker_open` hepsi **`0`**.

---

### 4. ChaosCenter Web UI'dan 4 Kadran Deneyi (Adım Adım + Ne Görmelisin?)

Sol menüden **Chaos Experiments** sekmesine git. 4 deneyin tamamı `chaos-lab-7-infra` üzerinde hazır kayıtlıdır; sırayla **Run** butonuna bas ve yan sekmede **Grafana**'yı canlı izle!

---

#### Deney 1 (Known-Knowns): `q1-known-known-replica-kill`
- **Ne Yapar?** Native Litmus `pod-delete` fault'unu kullanarak `inventory-replica` podlarından birini öldürür; aynı anda **Continuous `httpProbe`** her 2 saniyede bir `checkout-api/healthz`'i doğrular.
- **Neden Yapıyoruz?** Bildiğimiz yüksek erişilebilirlik (2 replika) tasarımının gerçekten sıfır kesintiyle çalışıp çalışmadığını kanıtlamak ve ekibe kas hafızası kazandırmak için.
- **Litmus UI'da Ne Görmelisin?**
  - Workflow grafiği: `install-chaos-faults` → `pod-delete-replica` → `cleanup-chaos-resources` (hepsi yeşil).
  - Native `ChaosEngine` + `weight: 10` kullandığı için **Resilience Score: `100%`** görünür.
- **Grafana'da Ne Görmelisin?**
  - **Panel 3 (`Healthy Inventory`):** `healthy_replicas` kısa süreliğine `2 → 1 → 2` iner çıkar.
  - **Panel 1 (`Checkout RPS`):** Yeşil `ok` çizgisinde **sıfır kesinti** (`error = 0` kalır) — çünkü K8s Service trafiği diğer sağlam replikaya yönlendirir.

---

#### Deney 2 (Known-Unknowns): `q2-known-unknown-latency-timeout`
- **Hipotez:** *"Gecikme (`delay`) yaşayacağımızı biliyoruz ama kaç ms'de sistem kırılır bilmiyoruz."*
- **Ne Yapar?** `inventory-replica` podlarına önce **20 sn `800ms`**, ardından **20 sn `2500ms`** yapay gecikme verir, sonunda otomatik `0ms`'ye geri döndürür (`Rollback Plan`).
- **Neden Yapıyoruz?** `checkout-api` içinde DB timeout `1.5s` (1500ms) ayarlıdır. Gecikme 1500ms'yi geçtiğinde uygulamanın nasıl agresif retry + failover ürettiğini ölçmek için.
- **Litmus UI (`Logs` sekmesi) & Grafana'da Ne Görmelisin?**
  - **Faz 1 (`800ms`, ilk 20 sn):**
    - **Panel 2 (`p95 Latency`):** `~0.8s–1.0s` bandına çıkar.
    - **Panel 1:** Hâlâ **%100 `ok`** (`800ms < 1500ms` timeout).
  - **Faz 2 (`2500ms`, sonraki 20 sn):**
    - Timeout (`1.5s`) aşıldığı için her istek önce **1 kez retry** atar (toplam ~3s bekler!).
    - **Panel 5 (`DB Retry Storm`):** Birden keskin şekilde yükselir (**Retry Storm**).
    - **Panel 4 (`Primary Failover`):** Replikalar timeout yediği için trafik `inventory-primary`'ye sıçrar (`primary_qps` ve `failover_rps` yükselir).
    - **Panel 2 (`p95 Latency`):** `> 2.5s` tepe yapar.
  - **Deney Sonu (`0ms` Rollback):** Tüm paneller tekrar normal baseline'a (`<50ms`, `0 retry`) döner.

---

#### Deney 3 (Unknown-Knowns): `q3-unknown-known-double-replica-kill`
- **Hipotez:** *"`inventory-replica` çökerse `primary` devreye girer biliyoruz; ama **2 replika birden aynı anda** giderse `primary` tüm okuma yükünü ne kadar süre ve hangi gecikmeyle taşır?"*
- **Ne Yapar?** `deploy/inventory-replica` sayısını 25 saniyeliğine `2 → 0`'a çeker, ardından `2`'ye geri getirir.
- **Neden Yapıyoruz?** Replikasyon/yedeklilik varken "zaten primary var" rahatlığının gerçekte primary üzerinde yarattığı QPS patlamasını görmek için.
- **Litmus UI (`Logs` sekmesi) & Grafana'da Ne Görmelisin?**
  - **Panel 3 (`Healthy Inventory`):** `healthy_replicas = 0` olurken `healthy_primary = 1` kalır.
  - **Panel 4 (`Primary QPS & Failover`):** Daha önce **`0`** olan `primary_qps`, bir anda tüm `loadgen` yükünü (`~5 QPS`) sırtlar!
  - **Panel 5 (`DB Retry Storm`):** Failover öncesi her istek replica'ya bir retry attığı için retry oranı da beraberinde artar (bu da bize replica yokken bile timeout+retry yüzünden gereksiz gecikme ödediğimizi gösterir!).

---

#### Deney 4 (Unknown-Unknowns): `q4-unknown-unknown-total-db-blackout`
- **Hipotez:** *"Hem `inventory-replica` hem `inventory-primary` aynı anda tamamen ulaşılamaz olursa (bölge/cluster veritabanı kesintisi) sistem tamamen çöker mi yoksa zarifçe düşer mi (`Graceful Degradation`)?"*
- **Ne Yapar?** Hem `inventory-replica` (`0`) hem `inventory-primary` (`0`) Deployment'larını 20 saniyeliğine kapatır; `checkout-api` içindeki **Circuit Breaker**'ın devreye girmesini ve **Redis Cache Fallback** dönüşünü doğrular, ardından ikisini de geri açıp sistemin kendiliğinden toparlanmasını (`auto-recovery`) test eder.
- **Neden Yapıyoruz?** Gremlin rehberindeki *Unknown-Unknowns* ilkesini uygulamak için: bütün DB katmanı yokken bile kullanıcıya `500` patlatmak yerine Redis önbellekten kontrollü hizmet verip DB gelince restart atmadan düzeldiğimizi kanıtlamak.
- **Litmus UI (`Logs` sekmesi) & Grafana'da Ne Görmelisin?**
  - İlk 4 ardışık hatada **Panel 1** kısa bir `error` sıçraması yapar.
  - 4. hatadan hemen sonra **Panel 6 (`Circuit Breaker`)** **`0 → 1`** olur (`circuit_breaker_open = 1`) ve **`redis_fallback_rps` ~5 RPS** yükselmeye başlar!
  - Aynı anda **Panel 1**'de `error` sıfırlanıp **`degraded` (sarı/turuncu) ~5 RPS** başlar — yani kullanıcı HTTP `200` (`degraded-cache`) almaya devam eder!
  - **Panel 2 (`p95 Latency`):** Circuit Breaker DB'yi beklemeyi bıraktığı için p95 latency tekrar **`< 50ms`'ye düşer** (fail-fast!).
  - Deney DB'leri geri açtıktan ~10 sn sonra Circuit Breaker kapanır (`1 → 0`), **`degraded` sıfırlanır ve `ok` tekrar ~5 RPS'ye oturur**.

---

### 5. Temizlik

```bash
./cleanup.sh
# Minikube profilini tamamen silmek için:
./cleanup.sh --delete-minikube
```

---

## 🇬🇧 English

This lab implements the **Gremlin Chaos Engineering Known / Unknown Matrix** and the **8 Fallacies of Distributed Systems** using **LitmusChaos ChaosCenter Web UI**, **Prometheus** (`kubernetes_sd_configs`), and an auto-provisioned 6-panel **Grafana** dashboard on an isolated **Minikube (`chaos-lab-7`, `$0`)** cluster.

### 1. The 4 Quadrant Experiments (`chaos/ui-workflows/`)

All 4 workflows are pre-registered by `setup.sh` inside **ChaosCenter UI → Chaos Experiments** with `podGC` disabled so step **Logs** always stay readable:

1. **`q1-known-known-replica-kill` (Known-Knowns):** Native Litmus `pod-delete` on `inventory-replica` with Continuous `httpProbe` (`weight: 10`, **100% Resilience Score**). Grafana proves `checkout-api` maintains 100% `ok` RPS when 1 of 2 DB replicas dies.
2. **`q2-known-unknown-latency-timeout` (Known-Unknowns):** Injects `800ms` delay (safe, below `1.5s` timeout), then ramps to `2500ms` (triggers **DB Retry Storm** + **Primary Failover** in Grafana Panels 2, 4, 5), then resets to `0ms`.
3. **`q3-unknown-known-double-replica-kill` (Unknown-Knowns):** Scales `inventory-replica` `2 -> 0` for 25s, measuring how `inventory-primary` absorbs all read QPS and failover latency overhead on Grafana Panel 4.
4. **`q4-unknown-unknown-total-db-blackout` (Unknown-Unknowns):** Scales BOTH `inventory-replica` and `inventory-primary` to `0`, triggering `checkout-api`'s **Circuit Breaker** (`circuit_breaker_open = 1`) and **Redis fallback** (`degraded` HTTP `200`, fast `<50ms` latency), then restores both DBs and verifies automatic half-open -> closed recovery.

### 2. Quickstart

```bash
cd troubleshoot/chaos-troubleshooting-7
chmod +x setup.sh cleanup.sh
./setup.sh

# Port-forward the 3 UIs:
kubectl -n litmus port-forward svc/litmus-frontend-service 9091:9091 >/tmp/litmus-pf.log 2>&1 &
kubectl -n monitoring port-forward svc/grafana 3000:3000 >/tmp/grafana-pf.log 2>&1 &
kubectl -n monitoring port-forward svc/prometheus 9090:9090 >/tmp/prom-pf.log 2>&1 &
```

- **ChaosCenter UI:** `http://localhost:9091` (`admin` / `Litmus@123`)
- **Grafana Dashboard:** `http://localhost:3000` (`admin` / `admin`) — home dashboard opens **Known-Unknown Chaos Matrix — StreamCart Live SRE Impact** directly.
- **Prometheus UI:** `http://localhost:9090`

### 3. Cleanup

```bash
./cleanup.sh --delete-minikube
```
