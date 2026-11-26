# Chaos Troubleshooting Lab 6: LitmusChaos Custom Experiments + MariaDB / ProxySQL / ClickHouse / VictoriaMetrics

- [🇹🇷 Türkçe](#-türkçe)
- [🇬🇧 English](#-english)

---

## 🇹🇷 Türkçe

Bu lab, sıfırdan **LitmusChaos** (`litmus-core`) ile **özel (Custom) ChaosExperiment** yazmayı, **MariaDB**, **ProxySQL**, **ClickHouse** ve **VictoriaMetrics** servislerinin mimari rollerini, Kubernetes üzerindeki kurulumlarını ve gerçekçi kaos + troubleshooting senaryolarını uygulamalı ve açıklamalı olarak öğretir.

Lab izole bir **Minikube (`chaos-lab-6`)** profili üzerinde %100 lokal (`$0`) çalışır; ChaosCenter UI veya ağır MongoDB bağımlılıkları gerektirmez.

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
- **Ne işe yarar?** İşlemsel (**OLTP** — `INSERT/UPDATE/DELETE`, sipariş, ödeme, ACID transaction) veriler için MySQL tabanlı açık kaynaklı ilişkisel veritabanıdır.
- **Bu labda nasıl kuruldu?** [manifests/data-stack.yaml](./manifests/data-stack.yaml) içinde `mariadb:11.4` imajı ve `mariadb-init` `ConfigMap`'i (`/docker-entrypoint-initdb.d/01-init.sql`) ile `shop.orders` tablosu ve örnek veriler otomatik oluşturulur. `healthcheck.sh --connect --innodb_initialized` ile gerçek readiness kontrolü yapılır.

#### B) ProxySQL (Layer-7 SQL Proxy & Connection Multiplexer)
- **Ne işe yarar?** Uygulamalar ile MariaDB/MySQL düğümleri arasında duran akıllı L7 SQL proxy'sidir.
  - **Connection Pooling / Multiplexing:** 500 uygulama podu 500 ayrı DB bağlantısı açıp MariaDB'yi kilitlemek yerine ProxySQL'e bağlanır; ProxySQL arka tarafta çok daha az sayıda kalıcı havuz bağlantısı tutar.
  - **Read/Write Split & Hostgroup Routing:** `mysql_query_rules` ile `^SELECT.*` sorgularını Read replica hostgroup'una, yazma sorgularını Writer hostgroup'una yönlendirebilirsiniz.
  - **Health Monitoring:** `monitor_username` ile backend MariaDB node'larına düzenli ping atar, düşen node'u trafikten izole eder.
- **Portlar:**
  - `:6033` → Uygulamaların bağlandığı **SQL Frontend** portu.
  - `:6032` → Canlı kural ve istatistikleri sorguladığımız **Admin** portu (`admin:admin`).
- **Bu labda nasıl kuruldu?** `proxysql/proxysql:2.7.1` ve `proxysql-config` `ConfigMap` (`/etc/proxysql.cnf`) içinde `hostgroup=10` üzerinden `mariadb.chaos-shop.svc.cluster.local:3306` hedeflenmiştir.

#### C) ClickHouse (Kolon Tabanlı OLAP Analitik Veritabanı)
- **Ne işe yarar?** Milyarlarca satır log/event/metrik verisi üzerinde milisaniyeler içinde toplam (`COUNT`, `SUM`, `GROUP BY`) alan **kolon bazlı (columnar) OLAP** veritabanıdır. MariaDB gibi OLTP veritabanlarını ağır analitik sorgularla yormamak için event/telemetri verileri buraya yazılır (`MergeTree` motoru).
- **Portlar:** `:8123` (HTTP SQL API), `:9000` (Native TCP).
- **Mimari Desen — Graceful Degradation:** `orders-api` servisinde `/orders` isteği sipariş akışını ProxySQL/MariaDB ile kritik olarak doğrular, ardından ClickHouse'a analitik event gönderir. ClickHouse çökerse `/orders` **çökmemeli**, olayı `"degraded-skipped"` diyerek atlayıp kullanıcıya `200 OK` dönmeli, sadece `/analytics` endpoint'i `503 degraded` vermelidir! 3. kaos senaryosu tam olarak bunu test eder.

#### D) VictoriaMetrics (Yüksek Performanslı Prometheus Uyumlu TSDB)
- **Ne işe yarar?** Prometheus formatındaki metrikleri (`/metrics`) kazıyan (scrape eden), PromQL/MetricsQL ile sorgulanan, ancak Prometheus'a göre çok daha az RAM ve disk tüketen tek binary zaman serisi (TSDB) veritabanıdır.
- **Bu labda nasıl kuruldu?** [manifests/observability.yaml](./manifests/observability.yaml) içinde `vm-scrape-config` `ConfigMap`'i her 5 saniyede bir `orders-api:8080/metrics` endpoint'ini kazır. Port `8428` üzerinde `/vmui` arayüzünü sunar.

#### E) LitmusChaos (`litmus-core`) ve Custom Experiment Anatomisi
Full ChaosCenter UI (MongoDB dahil) ağır olduğu için bu labda **`litmuschaos/litmus-core`** Helm chart'ı kullanılır. Bu chart sadece iki çekirdek bileşeni kurar:
1. **`ChaosExperiment` (Şablon / Blueprint):** Hangi container imajının, hangi komutun ve hangi varsayılan env değişkenlerinin çalışacağını tanımlar. Custom test yazmak için Go derlemeniz gerekmez; `python:3.11-alpine` veya `bash` imajı koyup kendi test senaryonuzu yazabilirsiniz!
2. **`ChaosEngine` (Çalıştırıcı / Tetikleyici):** Hedef uygulamayı (`appinfo`), RBAC yetkisini (`chaosServiceAccount`), çalıştırılacak `ChaosExperiment` adını ve ek **Probe**'ları (`httpProbe`, `cmdProbe`) bağlar.
3. **`ChaosResult` (Rapor / Karar):** Deney bittiğinde `Verdict` (`Pass` veya `Fail`) ve `ProbeSuccessPercentage` değerini tutar. Custom Python script'lerimiz Kubernetes API üzerinden `ChaosResult` objesini de bizzat oluşturup günceller!

> **Not — ChaosCenter UI'da `probeRef` Hatası:** ChaosCenter grafik arayüzünde bazı sürümlerde Probe ekleyince `Probe in fault run-chaos is not attached to a proper reference, please add it to annotations as probeRef` uyarısı ve label seçememe/kaydedememe yaşanabilir. Deklaratif YAML içinde doğrudan `ChaosEngine.spec.experiments[].spec.probe` tanımı (`chaos/01-pod-delete.yaml` örneğindeki gibi) kullandığınızda ChaosOperator bu probe'u ek annotation gerektirmeden doğrudan çalıştırır.

---

### 3. Kurulum ve Keşif

```bash
cd troubleshoot/chaos-troubleshooting-6
chmod +x setup.sh cleanup.sh
./setup.sh
```

Kurulum tamamlandığında bileşenleri tek tek doğrulayın:

```bash
# Tüm podları gör
kubectl -n chaos-shop get pods,pdb

# 1. MariaDB ve ProxySQL üzerinden canlı bağlantı testi
kubectl -n chaos-shop exec -it deploy/mariadb -- \
  mariadb -h proxysql.chaos-shop.svc.cluster.local -P 6033 -u shop -pshop-pass -e "SELECT * FROM shop.orders;"

# 2. ProxySQL Admin arayüzünden connection pool ve hostgroup istatistiklerini oku
kubectl -n chaos-shop exec -it deploy/mariadb -- \
  mariadb -h proxysql.chaos-shop.svc.cluster.local -P 6032 -u admin -padmin \
  -e "SELECT hostgroup, srv_host, status, ConnUsed, ConnFree, Queries FROM stats_mysql_connection_pool;"

# 3. ClickHouse HTTP API testi
kubectl -n chaos-shop exec -it deploy/orders-api -- \
  python3 -c "import urllib.request; print(urllib.request.urlopen('http://clickhouse:8123/?query=SELECT%20count()%20FROM%20analytics.order_events').read().decode())"

# 4. orders-api ve VictoriaMetrics'i lokale port-forward et
kubectl -n chaos-shop port-forward svc/orders-api 8080:8080 >/tmp/orders-pf.log 2>&1 &
kubectl -n chaos-shop port-forward svc/victoriametrics 8428:8428 >/tmp/vm-pf.log 2>&1 &

curl -s http://localhost:8080/orders | python3 -m json.tool
curl -s http://localhost:8080/analytics | python3 -m json.tool
```

Tarayıcıdan **VictoriaMetrics VMUI** adresini açın: `http://localhost:8428/vmui`  
Örnek MetricsQL sorguları:
- `orders_requests_total`
- `clickhouse_degraded_total`
- `rate(orders_requests_total[1m])`

---

### 4. Kaos Deneyleri (Standart + Custom Experiments)

#### Deney 1: Standart `pod-delete` + Continuous `httpProbe` (`chaos/01-pod-delete.yaml`)
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

This hands-on lab teaches how to install and run **LitmusChaos (`litmus-core`)** with **custom `ChaosExperiment` CRDs** alongside a realistic data & observability stack (**MariaDB**, **ProxySQL**, **ClickHouse**, and **VictoriaMetrics**) in an isolated **Minikube (`chaos-lab-6`)** profile (`$0`).

---

### 1. Stack Overview

- **MariaDB (`11.4`):** Primary OLTP store initialized with `shop.orders` (`manifests/data-stack.yaml`).
- **ProxySQL (`2.7.1`):** Layer-7 SQL proxy & connection multiplexer listening on `:6033` (SQL) and `:6032` (Admin) routing hostgroup `10` to MariaDB.
- **ClickHouse (`24.8-alpine`):** Columnar OLAP engine (`analytics.order_events`) on `:8123` (HTTP) and `:9000` (Native), demonstrating **graceful degradation** when offline.
- **VictoriaMetrics (`v1.106.0`):** Fast, low-memory Prometheus-compatible TSDB scraping `orders-api:8080/metrics` every `5s` (`:8428/vmui`).
- **`orders-api` (`replicas: 2` + `PodDisruptionBudget`):** Python HTTP service exposing `/healthz`, `/orders` (ProxySQL critical check + ClickHouse best-effort event), `/analytics` (ClickHouse query), and `/metrics`.
- **LitmusChaos (`litmus-core`):** Lightweight operator + runner without heavy ChaosCenter MongoDB overhead:
  1. `chaos/01-pod-delete.yaml`: Standard `pod-delete` + declarative `Continuous` `httpProbe` (avoids the ChaosCenter UI `probeRef` annotation bug).
  2. `chaos/02-custom-proxysql-flood.yaml`: Custom Python `ChaosExperiment` stress-testing ProxySQL & `orders-api`, checking VictoriaMetrics, and writing a `ChaosResult`.
  3. `chaos/03-custom-clickhouse-outage.yaml`: Custom Python `ChaosExperiment` scaling `deploy/clickhouse` to `0`, verifying `/orders` remains `200 OK` while `/analytics` returns `503 degraded` and `clickhouse_degraded_total` increments in VictoriaMetrics, then restoring ClickHouse.

---

### 2. Quickstart & Verification

```bash
cd troubleshoot/chaos-troubleshooting-6
chmod +x setup.sh cleanup.sh
./setup.sh
```

Run port-forwards and test the stack:

```bash
kubectl -n chaos-shop port-forward svc/orders-api 8080:8080 >/tmp/orders-pf.log 2>&1 &
kubectl -n chaos-shop port-forward svc/victoriametrics 8428:8428 >/tmp/vm-pf.log 2>&1 &

curl -s http://localhost:8080/orders
curl -s http://localhost:8080/analytics
# Open http://localhost:8428/vmui in your browser
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
