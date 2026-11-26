# Chaos Troubleshooting Lab 6: LitmusChaos Custom Experiments + MariaDB / ProxySQL / ClickHouse / VictoriaMetrics

- [🇹🇷 Türkçe](#-türkçe)
- [🇬🇧 English](#-english)

---

## 🇹🇷 Türkçe

Bu lab, sıfırdan **LitmusChaos ChaosCenter (Web UI + Cluster-Wide Infrastructure)** ve CLI ile **özel (Custom) ChaosExperiment** yazmayı, **MariaDB**, **ProxySQL**, **ClickHouse** ve **VictoriaMetrics** servislerinin mimari rollerini, neden tercih edildiklerini, Kubernetes üzerindeki kurulumlarını ve gerçekçi kaos + troubleshooting senaryolarını uygulamalı ve açıklamalı olarak öğretir.

Lab izole bir **Minikube (`chaos-lab-6`)** profili üzerinde %100 lokal (`$0`) çalışır; `setup.sh` hem **LitmusChaos Web Arayüzünü (`http://localhost:9091`)** hem de **cluster-wide Chaos Infrastructure (`chaos-lab-6-infra`)** ajanını otomatik kurup bağlar.

---

### 1. Mimari Genel Bakış

```text
                       +--------------------------+
                       |      orders-api (x2)     |
                       |  Python + PDB (minAvail) |
                       +-----+-------------+------+
                             |             |
              TCP :6033      |             | HTTP :8123
            (MySQL proto)    v             v (Insert / Query)
                    +--------+---+     +---+------------+
                    |  ProxySQL  |     |   ClickHouse   |
                    | :6033/:6032|     |   OLAP Engine  |
                    +-----+------+     +----------------+
                          |
                          v TCP :3306
                    +-----+------+
                    |  MariaDB   |     +-------------------------+
                    | OLTP InnoDB|     |    VictoriaMetrics      |
                    +------------+     | scrapes /metrics (:8428)|
                                       +-------------------------+
   LitmusChaos (litmus namespace)
     └─ chaos-operator ──> chaos-runner ──> Experiment Jobs (pod-delete + custom Python)
```

---

### 2. Bileşenler ve Neden Kullanılırlar? (Konu Anlatımı)

#### A) MariaDB (OLTP İlişkisel Veritabanı)
- **Neden tercih edilir & Rakipleriyle farkı nedir?**
  - **MariaDB vs MySQL:** MariaDB, Oracle'ın MySQL'i satın almasından sonra aynı kurucular tarafından açık kaynaklı (GPL) sürdürülen fork'tur. Üretimde en büyük farklarından biri **Thread Pool** desteğinin MariaDB'de ücretsiz ve dahili gelmesidir (MySQL tarafında gelişmiş thread pool yalnızca ücretli Enterprise Edition'dadır). Ayrıca Galera Cluster ile aktif-aktif multi-master replikasyon kutudan çıkma (built-in) gelir ve MariaDB query optimizer özellikle karmaşık join/subquery'lerde farklı optimizasyonlar sunar.
  - **MariaDB vs PostgreSQL:** PostgreSQL karmaşık analitik sorgular, JSONB indeksleme, coğrafi veri (PostGIS) ve zengin veri tiplerinde öndeyken; MariaDB yüksek eşzamanlılıklı basit/orta OLTP okuma-yazma (e-ticaret sepet, sipariş, stok düşümü) yüklerinde düşük bellek tüketimi, hafif replikasyon kurulumu ve InnoDB performansı nedeniyle tercih edilir.
- **Üretimdeki Kritik Darboğaz (`max_connections`):** MariaDB/MySQL mimarisinde varsayılan bağlantı modeli her istemci bağlantısı için bellek ve thread tüketir. Kubernetes üzerinde yatayda ölçeklenen 100 mikroservis podu aynı anda DB'ye direkt bağlanırsa `max_connections` sınırı hızla dolar ve `Too many connections` kesintisi yaşanır. **ProxySQL tam olarak bu sorunu çözmek için araya konur.**
- **Bu labda nasıl kuruldu?** [manifests/data-stack.yaml](./manifests/data-stack.yaml) içinde `mariadb:11.4` imajı ve `mariadb-init` `ConfigMap`'i (`/docker-entrypoint-initdb.d/01-init.sql`) ile `shop.orders` tablosu ve örnek veriler otomatik oluşturulur. `healthcheck.sh --connect --innodb_initialized` ile gerçek readiness kontrolü yapılır.

#### B) ProxySQL (Layer-7 SQL Proxy & Connection Multiplexer)
- **Neden tek başına Kubernetes `Service` veya HAProxy yetmez?** HAProxy veya K8s `Service` **L4 (TCP)** seviyesinde çalışır; gelen paketin içinde `SELECT` mi `INSERT` mi yazdığını bilmez, bağlantıları tek bir backend connection havuzunda birleştiremez. ProxySQL ise **L7 (MySQL/MariaDB protokolünü anlayan)** akıllı bir SQL proxy'sidir.
- **Neden tercih edilir & Ne kazandırır?**
  - **Connection Multiplexing (Çoklama):** Uygulama tarafında ProxySQL'e açılan 2.000 kısa ömürlü uygulama bağlantısını arka taraftaki MariaDB sunucularına örneğin sadece 50 kalıcı bağlantıya çoklar. Böylece MariaDB'nin connection açma/kapama (TLS + auth) CPU maliyeti sıfıra yakın düşer.
  - **Şeffaf Read/Write Split:** Uygulama kodunda "okuma için read-replica URL'ine, yazma için primary URL'ine bağlan" mantığı yazmaya gerek kalmaz. `mysql_query_rules` içinde regex ile (örneğin `^SELECT.*`) okumaları Reader hostgroup'una, geri kalanını Writer hostgroup'una otomatik yönlendirir.
  - **Query Cache, Firewall & Failover Buffering:** Tehlikeli veya `WHERE` şartı olmayan sorguları regex ile DB'ye ulaşmadan kesebilir, sık tekrarlanan sorguları bellekten dönebilir ve kısa failover anlarında sorguları birkaç saniye bekletip hata fırlatmadan yeni primary'e iletebilir.
  - **ProxySQL vs MariaDB MaxScale:** MaxScale güçlü bir alternatif olsa da BSL lisanslıdır (üretimde 3+ node için ticari lisans kısıtı doğar); ProxySQL tamamen açık kaynaklıdır (GPL) ve hem MySQL hem MariaDB kümelerinde endüstri standardıdır.
- **Portlar:** `:6033` (uygulama **SQL Frontend** portu), `:6032` (canlı kural/istatistik **Admin** portu, `admin:admin`).
- **Bu labda nasıl kuruldu?** `proxysql/proxysql:2.7.1` ve `proxysql-config` `ConfigMap` (`/etc/proxysql.cnf`) içinde `hostgroup=10` üzerinden `mariadb.chaos-shop.svc.cluster.local:3306` hedeflenmiştir.

#### C) ClickHouse (Kolon Tabanlı OLAP Analitik Veritabanı)
- **Satır Tabanlı (MariaDB/Postgres) ile Farkı Nedir?** MariaDB **satır tabanlıdır (row-oriented)**: bir siparişin tüm sütunlarını diskte yan yana tutar, bu yüzden "id=105 olan siparişi getir/güncelle" işleminde çok hızlıdır. ClickHouse ise **kolon tabanlıdır (column-oriented / OLAP)**: her sütunu ayrı dosyada ve yüksek sıkıştırmayla (LZ4/ZSTD) saklar. "Son 30 günde SKU bazlı toplam ciroyu hesapla" gibi sadece 2 kolonu okuyan milyarlarca satırlık `GROUP BY` / `SUM` sorgularında MariaDB'ye kıyasla **10x–100x daha hızlı** çalışır ve diski 5x–10x daha az kullanır.
- **Neden Elasticsearch / OpenSearch yerine tercih edilir?** Log, event, clickstream ve telemetri analitiğinde Elasticsearch JVM tabanlı olduğu için yüksek RAM tüketir ve büyük `GROUP BY` agregasyonlarında yavaşlar; C++ ile yazılan ClickHouse çok daha az RAM/CPU ile saniyede milyonlarca satır `INSERT` ve analitik sorgu işler.
- **Ne zaman KULLANILMAZ?** Sık tekil satır `UPDATE`/`DELETE` ve ACID transaction gereken sipariş/ödeme tabloları için kullanılmaz; o yük MariaDB'de kalır.
- **Mimari Desen — Graceful Degradation:** `orders-api` servisinde `/orders` isteği sipariş akışını ProxySQL/MariaDB ile kritik olarak doğrular, ardından ClickHouse'a analitik event gönderir. ClickHouse çökerse `/orders` **çökmemeli**, analitik yazımını `"degraded-skipped"` diyerek atlayıp kullanıcıya `200 OK` dönmeli, sadece `/analytics` endpoint'i `503 degraded` vermelidir.
- **Portlar:** `:8123` (HTTP SQL API), `:9000` (Native TCP).

#### D) VictoriaMetrics (Yüksek Performanslı Prometheus Uyumlu TSDB)
- **Neden Vanilla Prometheus yerine tercih edilir?** Standart Prometheus harikadır ancak özellikle Kubernetes üzerinde çok sayıda pod/label oluştuğunda (**high cardinality**) bellek tüketimi hızla GB'larca şişer (OOMKilled riski). Ayrıca Prometheus tek başına yerleşik küme/uzun süreli depolama sunmaz; bunun için yanına Thanos veya Cortex/Mimir gibi karmaşık bileşenler kurmak gerekir.
- **VictoriaMetrics'in Farkı Nedir?**
  - **2x–5x Daha Az RAM & Disk:** Aynı metrik hacmini yüksek sıkıştırmayla çok daha düşük kaynakta (bu labda 96Mi–256Mi limitlerle rahatça) işler.
  - **Tek Binary Sadelik + Uzun Süreli Saklama:** Thanos/Mimir karmaşıklığı olmadan günler/aylar boyu metrik tutabilir (`-retentionPeriod`).
  - **PromQL + MetricsQL Tam Uyumu:** Mevcut Prometheus `/metrics` endpoint'lerini ve Grafana dashboard'larını değiştirmeden doğrudan scrape eder; üstüne PromQL'in daha pratik genişletilmiş hali olan **MetricsQL** fonksiyonlarını sunar.
- **Bu labda nasıl kuruldu?** [manifests/observability.yaml](./manifests/observability.yaml) içinde `vm-scrape-config` `ConfigMap`'i her 5 saniyede bir `orders-api:8080/metrics` endpoint'ini kazır. Port `8428` üzerinde `/vmui` arayüzünü sunar.

#### E) LitmusChaos (`litmus-core`) ve Custom Experiment Anatomisi
- **Neden `kubectl delete pod` değil de LitmusChaos?** Manuel `kubectl delete pod` rastgele bir kesinti yaratır ama sistemin o esnada gerçekten sağlıklı kaldığını ölçmez ve tekrarlanabilir değildir. LitmusChaos kaos testini **GitOps uyumlu Kubernetes CRD'lerine** taşır: kaos öncesi/sırası/sonrasında otomatik **Probe** (`httpProbe`, `cmdProbe`, `promProbe`) koşturur ve CI/CD pipeline'larında kapı (gate) olarak kullanılabilecek `ChaosResult` (`Pass`/`Fail`) üretir.
- **LitmusChaos vs Chaos Mesh:** Her ikisi de güçlüdür; Chaos Mesh ağ/kernel (eBPF/tc) seviyesinde çok iyidir ancak yeni bir özel deney yazmak için çoğu zaman Go kodunu derlemek gerekir. LitmusChaos ise `ChaosExperiment` içine `python:3.11-alpine` veya `bash` gibi herhangi bir standart container imajı koyup saniyeler içinde kendi **Custom ChaosExperiment** şablonunuzu yazmanıza izin verir.
- **Bu labdaki çekirdek bileşenler (`litmus-core`):** Ağır ChaosCenter UI (MongoDB) yerine hafif operator + runner mimarisi kullanılır:
  1. **`ChaosExperiment` (Şablon / Blueprint):** Hangi container imajının, hangi komutun ve varsayılan env değişkenlerinin çalışacağını tanımlar.
  2. **`ChaosEngine` (Çalıştırıcı / Tetikleyici):** Hedef uygulamayı (`appinfo`), RBAC yetkisini (`chaosServiceAccount`), çalıştırılacak `ChaosExperiment` adını ve **Probe**'ları bağlar.
  3. **`ChaosResult` (Rapor / Karar):** Deney bittiğinde `Verdict` (`Pass` veya `Fail`) ve `ProbeSuccessPercentage` değerini tutar. Labdaki custom Python script'leri Kubernetes API üzerinden `ChaosResult` objesini de bizzat oluşturup günceller.

> **Not — ChaosCenter UI'da `probeRef` Hatası:** ChaosCenter grafik arayüzünde bazı sürümlerde Probe ekleyince `Probe in fault run-chaos is not attached to a proper reference, please add it to annotations as probeRef` uyarısı ve label seçememe/kaydedememe yaşanabilir. Deklaratif YAML içinde doğrudan `ChaosEngine.spec.experiments[].spec.probe` tanımı (`chaos/01-pod-delete.yaml` örneğindeki gibi) kullandığınızda ChaosOperator bu probe'u ek annotation gerektirmeden doğrudan çalıştırır.

#### F) Karşılaştırmalı Özet Tablosu

| Bileşen | Rolü | Başlıca Alternatifleri | Üretimde Neden Bu Tercih Edilir? |
| :--- | :--- | :--- | :--- |
| **MariaDB** | OLTP İlişkisel DB | MySQL, PostgreSQL | Açık kaynaklı dahili Thread Pool + Galera, yüksek eşzamanlılıklı standart OLTP'de düşük overhead |
| **ProxySQL** | L7 SQL Proxy & Pooler | MaxScale, HAProxy (L4) | Tam açık kaynak (GPL), SQL-farkında connection multiplexing ve şeffaf Read/Write split |
| **ClickHouse** | Kolon Tabanlı OLAP DB | Elasticsearch, BigQuery | C++ kolon motoru ile Elasticsearch'e göre çok düşük RAM'de 10x–100x hızlı analitik agregasyon |
| **VictoriaMetrics** | Prometheus Uyumlu TSDB | Prometheus + Thanos/Mimir | Tek binary sadelik, yüksek kardinalitede 2x–5x daha düşük RAM/disk, tam PromQL/MetricsQL uyumu |
| **LitmusChaos (`litmus-core`)** | K8s Chaos Engine | Chaos Mesh, Manuel script | CRD + otomatik steady-state Probe + herhangi bir container imajıyla kolay Custom Experiment |

---

### 3. Kurulum ve Keşif

```bash
cd troubleshoot/chaos-troubleshooting-6
chmod +x setup.sh cleanup.sh
./setup.sh
```

Kurulum tamamlandığında bileşenleri tek tek doğrulayın:

```bash
# Tüm podları gör (hem chaos-shop hem litmus)
kubectl -n chaos-shop get pods,pdb
kubectl -n litmus get pods

# 1. MariaDB ve ProxySQL (:6033 SQL) üzerinden canlı bağlantı testi (--skip-ssl gerekli)
kubectl -n chaos-shop exec -it deploy/mariadb -- \
  mariadb --skip-ssl -h proxysql.chaos-shop.svc.cluster.local -P 6033 -u shop -pshop-pass -e "SELECT * FROM shop.orders;"

# 2. ProxySQL Admin (:6032) arayüzünden connection pool ve hostgroup istatistiklerini oku (-u radmin)
kubectl -n chaos-shop exec -it deploy/mariadb -- \
  mariadb --skip-ssl -h proxysql.chaos-shop.svc.cluster.local -P 6032 -u radmin -pradmin \
  -e "SELECT hostgroup, srv_host, status, ConnUsed, ConnFree, Queries FROM stats_mysql_connection_pool;"

# 3. ClickHouse HTTP API testi
kubectl -n chaos-shop exec -it deploy/orders-api -- \
  python3 -c "import urllib.request; print(urllib.request.urlopen('http://clickhouse:8123/?query=SELECT%20count()%20FROM%20analytics.order_events').read().decode())"

# 4. LitmusChaos ChaosCenter Web UI, orders-api ve VictoriaMetrics'i lokale port-forward et
kubectl -n litmus port-forward svc/litmus-frontend-service 9091:9091 >/tmp/litmus-pf.log 2>&1 &
kubectl -n chaos-shop port-forward svc/orders-api 8080:8080 >/tmp/orders-pf.log 2>&1 &
kubectl -n chaos-shop port-forward svc/victoriametrics 8428:8428 >/tmp/vm-pf.log 2>&1 &

curl -s http://localhost:8080/orders | python3 -m json.tool
curl -s http://localhost:8080/analytics | python3 -m json.tool
```

- **LitmusChaos ChaosCenter UI:** `http://localhost:9091` (Kullanıcı: `admin`, Şifre: `Litmus@123`)
- **VictoriaMetrics VMUI:** `http://localhost:8428/vmui`  
  Örnek MetricsQL sorguları: `orders_requests_total`, `clickhouse_degraded_total`, `rate(orders_requests_total[1m])`

---

### 4. Kaos Deneyleri (Bölüm 1: Web UI + Bölüm 2: Custom Python Experiments)

#### Bölüm 1: ChaosCenter Web UI Üzerinden `pod-delete` + HTTP Probe (Hatasız Adım Sırası)

1. `http://localhost:9091` adresine **`admin` / `Litmus@123`** ile giriş yapın.
2. Sol menüden **Environments → `chaos-lab-6-env`** içine girin ve `chaos-lab-6-infra` altyapısının **Active** (yeşil) olduğunu doğrulayın.
3. **Önce Resilience Probe Oluşturun (`probeRef` hatasını önlemek için):**
   - Sol menü → **Resilience Probes** → **+ New Probe** → **HTTP Probe**
   - **Name:** `orders-health`
   - **Infrastructure:** `chaos-lab-6-infra`
   - **URL:** `http://orders-api.chaos-shop.svc.cluster.local:8080/healthz`
   - **Method:** `GET` | **Criteria:** `==` | **Response Code:** `200`
   - **Timeout:** `2s` | **Interval:** `2s` | **Retry:** `2` → **Create Probe**
4. **Deneyi Oluşturup Çalıştırın:**
   - Sol menü → **Chaos Experiments** → **+ New Experiment** → **Chaos Infrastructure:** `chaos-lab-6-infra` → **Blank Canvas**
   - **+ Add** → **Kubernetes** → **`pod-delete`** seçin.
   - **Target Application** sekmesi:
     - **App Kind:** `deployment`
     - **App Namespace:** `chaos-shop`
     - **App Label:** Listeden `app=orders-api` seçin (listede çıkmazsa kutuya `app=orders-api` yazıp `Enter`'a basın).
   - **Probes** sekmesi → `+ Add Probe` → az önce oluşturduğunuz **`orders-health`** probe'unu seçin, **Mode:** `Continuous` yapın.
   - **Apply Changes** → sağ üstten **Save** → **Run**!
   - Canlı takip: `kubectl -n chaos-shop get pods -w` ve ChaosCenter arayüzündeki **Resilience Score** ekranı.

#### Bölüm 2: CLI & Custom Python Experiments (ProxySQL Load & ClickHouse Outage)

ChaosCenter UI'daki standart fault'lara ek olarak, kendi veri yığınımıza özel yazdığımız 3 deklaratif deneyi CLI üzerinden çalıştırıp karşılaştırabilirsiniz:

##### Deney 1 (CLI Deklaratif Probe): Standart `pod-delete` (`chaos/01-pod-delete.yaml`)
`orders-api` podlarından birini öldürürken aynı anda her 2 saniyede bir `/healthz` endpoint'ine `httpProbe` gönderir. 2 replika + `PodDisruptionBudget (minAvailable: 1)` sayesinde kesinti yaşanmadan `Pass` vermelidir.

```bash
kubectl apply -f chaos/01-pod-delete.yaml
kubectl -n chaos-shop get pods,chaosengine,chaosresult -w
kubectl -n chaos-shop describe chaosresult orders-pod-delete-pod-delete
```

#### Deney 2: Custom `ChaosExperiment` — ProxySQL & API Concurrent Yük Testi (`chaos/02-custom-proxysql-flood.yaml`)
Kendi yazdığımız `custom-proxysql-chaos` `ChaosExperiment` kaynağı `python:3.11-alpine` imajıyla 16 eşzamanlı iş parçacığı açarak 160 isteği hem `orders-api/orders` hem de `proxysql:6033` üzerine gönderir, p95 gecikmeyi hesaplar, VictoriaMetrics'ten `orders_requests_total` değerini doğrular ve `ChaosResult` üretir.

```bash
kubectl apply -f chaos/02-custom-proxysql-flood.yaml
kubectl -n chaos-shop get jobs,pods -w
# Job podu oluştuktan sonra logları ve sonucu inceleyin:
kubectl -n chaos-shop logs -l job-name --tail=50
kubectl -n chaos-shop get chaosresult -o wide
```

#### Deney 3: Custom `ChaosExperiment` — ClickHouse Kesintisi ve Graceful Degradation (`chaos/03-custom-clickhouse-outage.yaml`)
Kendi yazdığımız `custom-clickhouse-outage` deneyi Kubernetes API'yi kullanarak `deploy/clickhouse` replikasını 15 saniyeliğine `0`'a indirir ve otomatik olarak şunları doğrular:
1. `/orders` HTTP `200 OK` vermeye devam etmeli (`"analytics_event": "degraded-skipped"`).
2. `/analytics` HTTP `503` (`"status": "degraded"`) dönmeli.
3. VictoriaMetrics içinde `clickhouse_degraded_total` artmalı.
4. `finally` bloğunda ClickHouse tekrar `1` replikaya çıkarılmalı ve iyileşme doğrulanmalı.

```bash
kubectl apply -f chaos/03-custom-clickhouse-outage.yaml
kubectl -n chaos-shop logs -l name=custom-clickhouse-outage -f
kubectl -n chaos-shop get chaosresult clickhouse-outage-chaos-custom-clickhouse-outage -o yaml
```

---

### 5. Uygulamalı Troubleshooting Alıştırmaları (Drills)

1. **Drill 1 — MariaDB Durursa ProxySQL Ne Yapar?**
   - `kubectl -n chaos-shop scale deploy/mariadb --replicas=0` çalıştırın.
   - `stats_mysql_connection_pool` tablosundan ProxySQL'in backend durumunu (`SHUNNED` / `OFFLINE_HARD`) gözlemleyin.
   - `curl -i http://localhost:8080/orders` ve VictoriaMetrics `orders_errors_total` metriğini inceleyin, ardından MariaDB'yi `1` replikaya geri alın.

2. **Drill 2 — Kendi Custom `ChaosExperiment`'ini Yaz**
   - `chaos/02-custom-proxysql-flood.yaml` dosyasını kopyalayın.
   - `CONCURRENCY` değerini `40`, başarı eşiğini `%99` ve VictoriaMetrics p95 kontrolünü sıkılaştırarak `chaosresult` çıktısının `Fail` durumuna nasıl düştüğünü test edin.

3. **Drill 3 — RBAC Yetki Hatasını Ayıklama**
   - `chaos/rbac.yaml` içinden `deployments/scale` yetkisini geçici olarak kaldırıp `03-custom-clickhouse-outage.yaml` çalıştırın; `chaos-runner` ve experiment pod loglarından `403 Forbidden` kök nedenini tespit edip geri düzeltin.

---

### 6. Temizlik

```bash
./cleanup.sh
# Minikube profilini tamamen silmek için:
./cleanup.sh --delete-minikube
```

---

## 🇬🇧 English

This hands-on lab teaches how to install and run **LitmusChaos ChaosCenter (Web UI + Cluster-Wide Infrastructure)** and **custom `ChaosExperiment` CRDs** alongside a realistic data & observability stack (**MariaDB**, **ProxySQL**, **ClickHouse**, and **VictoriaMetrics**) in an isolated **Minikube (`chaos-lab-6`)** profile (`$0`).

---

### 1. Stack Overview & Why Each Component Is Chosen

- **MariaDB (`11.4`):** Primary OLTP store initialized with `shop.orders` (`manifests/data-stack.yaml`). Chosen over MySQL Community for its built-in GPL Thread Pool and Galera support, and over PostgreSQL for lightweight high-concurrency simple/medium OLTP workloads.
- **ProxySQL (`2.7.1`):** Layer-7 SQL proxy & connection multiplexer listening on `:6033` (SQL) and `:6032` (Admin) routing hostgroup `10` to MariaDB. Prevents `max_connections` exhaustion caused by K8s pod scaling (which L4 HAProxy/K8s Services cannot solve) and provides transparent Read/Write splitting (`mysql_query_rules`) under full GPL open-source licensing (vs BSL MaxScale).
- **ClickHouse (`24.8-alpine`):** Columnar OLAP engine (`analytics.order_events`) on `:8123` (HTTP) and `:9000` (Native). Delivers 10x–100x faster analytical aggregations (`GROUP BY`/`SUM`) with much lower RAM/disk footprint than JVM-based Elasticsearch, while isolating heavy analytics from MariaDB OLTP and demonstrating **graceful degradation** when offline.
- **VictoriaMetrics (`v1.106.0`):** Prometheus-compatible TSDB scraping `orders-api:8080/metrics` every `5s` (`:8428/vmui`). Chosen over vanilla Prometheus + Thanos/Mimir for 2x–5x lower RAM/disk usage under high cardinality, single-binary simplicity, built-in long-term retention, and MetricsQL/PromQL compatibility.
- **`orders-api` (`replicas: 2` + `PodDisruptionBudget`):** Python HTTP service exposing `/healthz`, `/orders` (ProxySQL critical check + ClickHouse best-effort event), `/analytics` (ClickHouse query), and `/metrics`.
- **LitmusChaos (`litmus` ChaosCenter + `chaos-lab-6-infra`):** CRD-driven GitOps chaos platform + Web UI (`setup.sh` auto-connects cluster-wide Chaos Infrastructure via `litmusctl`) supporting continuous steady-state probes and custom `ChaosExperiment` blueprints in Python/Bash without compiling Go:
  1. **Web UI Walkthrough:** Create an `orders-health` HTTP Probe under **Resilience Probes** first (prevents the UI `probeRef` error), then run `pod-delete` targeting `deployment` / `chaos-shop` / `app=orders-api`.
  2. `chaos/01-pod-delete.yaml`: Declarative CLI `pod-delete` + `Continuous` `httpProbe`.
  3. `chaos/02-custom-proxysql-flood.yaml`: Custom Python `ChaosExperiment` stress-testing ProxySQL & `orders-api`, checking VictoriaMetrics, and writing a `ChaosResult`.
  4. `chaos/03-custom-clickhouse-outage.yaml`: Custom Python `ChaosExperiment` scaling `deploy/clickhouse` to `0`, verifying `/orders` remains `200 OK` while `/analytics` returns `503 degraded` and `clickhouse_degraded_total` increments in VictoriaMetrics, then restoring ClickHouse.

---

### 2. Quickstart & Verification

```bash
cd troubleshoot/chaos-troubleshooting-6
chmod +x setup.sh cleanup.sh
./setup.sh
```

Run port-forwards and verify the stack:

```bash
# 1. MariaDB via ProxySQL (:6033) and ProxySQL Admin (:6032)
kubectl -n chaos-shop exec -it deploy/mariadb -- \
  mariadb --skip-ssl -h proxysql.chaos-shop.svc.cluster.local -P 6033 -u shop -pshop-pass -e "SELECT * FROM shop.orders;"
kubectl -n chaos-shop exec -it deploy/mariadb -- \
  mariadb --skip-ssl -h proxysql.chaos-shop.svc.cluster.local -P 6032 -u radmin -pradmin \
  -e "SELECT hostgroup, srv_host, status, ConnUsed, ConnFree, Queries FROM stats_mysql_connection_pool;"

# 2. Port-forward ChaosCenter UI, orders-api, and VictoriaMetrics
kubectl -n litmus port-forward svc/litmus-frontend-service 9091:9091 >/tmp/litmus-pf.log 2>&1 &
kubectl -n chaos-shop port-forward svc/orders-api 8080:8080 >/tmp/orders-pf.log 2>&1 &
kubectl -n chaos-shop port-forward svc/victoriametrics 8428:8428 >/tmp/vm-pf.log 2>&1 &

curl -s http://localhost:8080/orders
curl -s http://localhost:8080/analytics
# ChaosCenter UI: http://localhost:9091 (admin / Litmus@123)
# VictoriaMetrics VMUI: http://localhost:8428/vmui
```

Run the three LitmusChaos experiments:

```bash
kubectl apply -f chaos/01-pod-delete.yaml
kubectl apply -f chaos/02-custom-proxysql-flood.yaml
kubectl apply -f chaos/03-custom-clickhouse-outage.yaml
kubectl -n chaos-shop get chaosengine,chaosresult -o wide
```

---

### 3. Cleanup

```bash
./cleanup.sh --delete-minikube
```
