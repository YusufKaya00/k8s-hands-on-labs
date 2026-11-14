[🇹🇷 Türkçe](#-türkçe) | [🇬🇧 English](#-english)

---

# 🇹🇷 Türkçe

# NovaMesh v12.0 (Lab 29) — Gerçekçi Production Kubernetes Ağ Arıza Giderme Labı

**NovaMesh**, Azure Kubernetes Service (AKS + Calico CNI + NGINX Ingress Controller) üzerinde çalışan 3 katmanlı dağıtık bir mikroservis platformudur:

- **`novamesh-edge`**: Dış dünyaya açılan `edge-proxy-lb` (Azure L4 LoadBalancer) ve 5 adet L7 NGINX Ingress kuralı (`novamesh-ingress`, `novamesh-catalog-ingress`, `novamesh-partner-ingress`, `novamesh-portal-ingress`, `novamesh-report-ingress`).
- **`novamesh-api`**: `gateway-api`, `catalog-api`, `pricing-engine`, `risk-evaluator`, `receipt-service` ve `report-bridge` (cross-namespace servis köprüsü).
- **`novamesh-data`**: `token-vault` ve `report-service`.

> [!IMPORTANT]
> Bu labdaki **tüm Pod'lar `1/1 Running` durumundadır**. Klasik `kubectl get pods` çıktısı tamamen sağlıklı görünecektir. Sorunları tıpkı gerçek bir SRE/Platform Mühendisi gibi **canlı HTTP semptomlarını gözlemleyerek, katmanlar arası izolasyon testleri yaparak ve karşılaştırmalı mantık yürüterek** tespit etmeniz gerekir.

---

## 1. Kurulum ve Ortam Hazırlığı

```bash
chmod +x setup.sh check.sh cleanup.sh
./setup.sh
```

> [!NOTE]
> Eğer önceki labdan kalan bir AKS kümeniz (`denmarkeast` bölgesinde 6 vCPU kota sınırı) halen açıksa önce onun `./cleanup.sh` scriptini çalıştırın. Mevcut AKS kümeniz zaten açıksa `./setup.sh --skip-terraform` kullanabilirsiniz.

Test komutlarında kullanacağınız ortam değişkenlerini yükleyin:

```bash
export INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
export LB_IP=$(kubectl get svc -n novamesh-edge edge-proxy-lb -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
export HOST="novamesh.${INGRESS_IP}.nip.io"
export PORTAL_HOST="portal.${INGRESS_IP}.nip.io"
```

Önce temel hattın çalıştığını doğrulayın (`200 OK` dönmelidir):

```bash
curl -i --max-time 4 "http://${HOST}/api/v1/health"
```

---

## 2. 5 Kapılı Ağ Eleme Metodolojisi (5-Gate Isolation)

Gerçek dünyada ağ paketinin geçtiği her kapı farklı bir HTTP sinyali bırakır:

| Kapı | Katman | Tipik Canlı Semptomlar | İlk İzolasyon Sorusu |
| :--- | :--- | :--- | :--- |
| **1** | **Azure L4 LoadBalancer** | Bağlantı reddi veya timeout (`HTTP 000`) | Dış LB IP yerine küme içinden doğrudan Pod/Service IP'sine erişince yanıt geliyor mu? |
| **2** | **NGINX Ingress (L7)** | `403`, `308`, yanlış yönlendirilmiş `404` veya `503` | Küme içinden doğrudan hedef Service'e `curl` atınca çalışıyor ama Ingress üzerinden bozuluyor mu? |
| **3** | **Service & Endpoints** | Immediate `502` veya `Connection refused` | Service arkasında gerçekten trafik alabilen bir Endpoint IP'si var mı? |
| **4** | **CoreDNS & ExternalName** | `502` + `Name does not resolve` / DNS hatası | Pod içinden servis adını `nslookup` ile çözebiliyor musunuz, yoksa doğrudan Pod/Service IP'sine ulaşıp isme ulaşamıyor musunuz? |
| **5** | **Calico NetworkPolicy** | `504 Gateway Timeout` (veya DNS paket düşmesi) | Aynı isteği politikadan muaf başka bir namespace/pod içinden veya politikadaki etiket/CIDR kurallarını pod kimliğiyle karşılaştırdığınızda ne değişiyor? |

---

## 3. Saha Mühendisi Araç Kutusu (Toolbox)

Aşağıdaki genel şablonları tüm biletlerde izolasyon testi için kullanabilirsiniz:

- **Dışarıdan ham HTTP başlıklarını ve süreyi görme:**
  `curl -i --max-time 5 "http://<HOST_OR_IP>/<PATH>"`
- **Küme içindeki bir Pod'un gözünden servis testi (Ingress/LB'yi baypas etme):**
  `kubectl exec -n <NAMESPACE> <POD> -- python3 -c "import urllib.request; print(urllib.request.urlopen('<URL>', timeout=3).read().decode())"`
- **Geçici ağ/DNS test podu açma:**
  `kubectl run netdebug --rm -it --restart=Never --image=busybox:1.36 -n <NAMESPACE> -- sh`
- **Service -> Endpoint eşleşmesini görme:**
  `kubectl get endpoints <SERVICE> -n <NAMESPACE>`
- **Pod IP'leri ve etiketlerini inceleme:**
  `kubectl get pods -n <NAMESPACE> --show-labels -o wide`
- **Ingress veya NetworkPolicy kurallarını inceleme:**
  `kubectl describe ingress <NAME> -n novamesh-edge` / `kubectl get netpol -n <NAMESPACE> -o yaml`

---

## 4. Production Destek Biletleri (10 Adet)

### Bilet 1 — Dış Edge LoadBalancer Yanıt Vermiyor
- **Canlı Test:**
  ```bash
  curl -i --max-time 4 "http://${LB_IP}:8080/edge/ping"
  ```
- **Gözlenen Semptom:** İstek dış LoadBalancer IP üzerinden `000` / zaman aşımı veya bağlantı hatası veriyor.
- **Nasıl Yaklaşmalısın?**
  1. `novamesh-edge` altındaki `edge-proxy` podunun sağlıklı çalıştığını ve küme içinden kendi portunda gerçekten yanıt verip vermediğini test ederek uygulamanın masum olduğunu kanıtlayın.
  2. Uygulama içten yanıt veriyorsa sorun Azure LoadBalancer ile Pod arasındaki L4 port yönlendirme zincirindedir (`port` -> `targetPort` -> `containerPort` üçlüsünü karşılaştırın).
- **Beklenen Kanıt:** `HTTP 200 OK` ve `{"proxy": "edge-proxy", "status": "online", ...}`.

---

### Bilet 2 — `/v2/catalog/items` Endpoint'i `404` Dönüyor
- **Canlı Test:**
  ```bash
  curl -i --max-time 4 "http://${HOST}/v2/catalog/items"
  ```
- **Gözlenen Semptom:** Yanıt gövdesinde JSON olarak `404` ve `received_path` alanını göreceksiniz.
- **Nasıl Yaklaşmalısın?**
  1. Dönen JSON içindeki `received_path` değerine dikkatlice bakın: Ingress, isteği backend servise hangi URI ile teslim etmiş?
  2. Ardından küme içinden `catalog-api` servisine doğrudan `/items` ve `/v2/catalog/items` yollarıyla istek atarak mikroservisin aslında hangi path'i dinlediğini doğrulayın.
  3. Prefix'in backend'e iletilmeden önce L7 katmanında nasıl soyulması gerektiğini `novamesh-catalog-ingress` üzerinde analiz edin.
- **Beklenen Kanıt:** `HTTP 200 OK` ve `catalog-api` ürün listesi JSON çıktısı.

---

### Bilet 3 — İş Ortağı Senkronizasyonu Tüm İstemcilere `403 Forbidden` Veriyor
- **Canlı Test:**
  ```bash
  curl -i --max-time 4 "http://${HOST}/partner/sync"
  ```
- **Gözlenen Semptom:** İstek backend loglarına bile düşmeden NGINX tarafından `403 Forbidden` ile kesiliyor.
- **Nasıl Yaklaşmalısın?**
  1. Küme içinden `gateway-api` servisinin `/partner/sync` endpoint'ini doğrudan çağırarak servisin kendisinin `403` üretmediğini (`200 OK` verdiğini) doğrulayın.
  2. Sorun Ingress katmanında kaynak IP bazlı L7 erişim kısıtlamasından kaynaklanıyorsa ilgili Ingress tanımındaki annotasyonları inceleyin.
- **Beklenen Kanıt:** `HTTP 200 OK` ve `partner-sync` JSON yanıtı.

---

### Bilet 4 — Yeni Portal URL'si Beklenmedik Şekilde Yönlendirme (`308`) Yapıyor
- **Canlı Test:**
  ```bash
  curl -i --max-time 4 "http://${PORTAL_HOST}/portal/status"
  ```
- **Gözlenen Semptom:** `curl -L` kullanmadan baktığınızda sunucu `200` yerine `308 Permanent Redirect` ve `Location: https://...` başlığı dönüyor.
- **Nasıl Yaklaşmalısın?**
  1. Ham HTTP başlıklarındaki `Location` hedefini okuyun: Trafik neden TLS/HTTPS'e zorlanıyor?
  2. `novamesh-ingress` ile `novamesh-portal-ingress` kurallarını ve annotasyonlarını yan yana karşılaştırın (TLS sertifikası olmayan HTTP lab ortamında hangi L7 kuralı buna yol açar?).
- **Beklenen Kanıt:** `HTTP 200 OK` (yönlendirme olmadan doğrudan yanıt).

---

### Bilet 5 — Fiyatlandırma Servisi (`/api/v1/quote`) Zaman Aşımına Uğruyor (`504`)
- **Canlı Test:**
  ```bash
  curl -i --max-time 5 "http://${HOST}/api/v1/quote"
  ```
- **Gözlenen Semptom:** `gateway-api` -> `pricing-engine` çağrısı asılı kalıp `504 Gateway Timeout` dönüyor.
- **Nasıl Yaklaşmalısın?**
  1. Önce `pricing-engine` Pod ve Endpoint'lerinin sağlıklı olduğunu doğrulayın (`catalog-api` gibi başka bir `novamesh-api` podu aynı servise erişebiliyor mu, yoksa o da mı takılıyor?).
  2. Bağlantı `Connection refused` yerine **sessizce zaman aşımına** uğruyorsa güvenlik duvarı/NetworkPolicy paket düşürüyor demektir.
  3. İstemci (`gateway-api`) üzerindeki gerçek Pod etiketleri ile hedefteki koruma politikasının kabul ettiği etiketleri birebir karşılaştırın. *(Güvenlik politikasını silmeden düzeltin!)*
- **Beklenen Kanıt:** `HTTP 200 OK` ve `pricing-engine` fiyat yanıtı (`pricing-netpol` aktif kalmalı).

---

### Bilet 6 — Risk Değerlendirme Servisi (`/api/v1/risk`) `502` Hatası Veriyor
- **Canlı Test:**
  ```bash
  curl -i --max-time 6 "http://${HOST}/api/v1/risk"
  ```
- **Gözlenen Semptom:** `gateway-api` -> `risk-evaluator` çağrısı hızla `502` + DNS/upstream hata mesajı ile dönüyor.
- **Nasıl Yaklaşmalısın?**
  1. `risk-evaluator` podunun içine girip hem hedef `report-service.novamesh-data.svc.cluster.local` FQDN'ini `nslookup` ile çözmeyi deneyin, hem de doğrudan hedef Pod IP'sine (`-o wide`) bağlanmayı test edin.
  2. Hedefe TCP olarak izin varken neden isim çözümlemesi başarısız oluyor? Pod üzerinde tanımlı Egress NetworkPolicy kurallarının hangi kritik küme servisini unuttuğunu düşünün. *(Politikayı silmeden düzeltin!)*
- **Beklenen Kanıt:** `HTTP 200 OK` ve `risk-evaluator` çıktısı (`risk-netpol` aktif kalmalı).

---

### Bilet 7 — Makbuz Servisi (`/api/v1/receipt`) `502 Unreachable` Dönüyor
- **Canlı Test:**
  ```bash
  curl -i --max-time 4 "http://${HOST}/api/v1/receipt"
  ```
- **Gözlenen Semptom:** Zaman aşımı beklemeden anında `502` / `upstream unreachable` hatası alınıyor.
- **Nasıl Yaklaşmalısın?**
  1. Pod `1/1 Running` olmasına rağmen anında bağlantı reddi/ulaşılamama varsa önce `receipt-service` Service'inin arkasında aktif bir Endpoint listesi olup olmadığına bakın.
  2. Endpoint boşsa Service'in aradığı etiket kümesi ile Pod'un gerçek etiket kümesini satır satır kıyaslayın.
- **Beklenen Kanıt:** `HTTP 200 OK` ve `receipt-service` JSON yanıtı.

---

### Bilet 8 — Cross-Namespace Token Servisi (`/api/v1/token`) Zaman Aşımına Uğruyor (`504`)
- **Canlı Test:**
  ```bash
  curl -i --max-time 5 "http://${HOST}/api/v1/token"
  ```
- **Gözlenen Semptom:** `novamesh-api` altındaki `gateway-api`, `novamesh-data` altındaki `token-vault` servisine giderken `504 Timeout` yiyor.
- **Nasıl Yaklaşmalısın?**
  1. `gateway-api` Pod'unun gerçek IP adresini (`-o wide`) ve `novamesh-data` altındaki `token-vault` servisini koruyan NetworkPolicy kuralını yan yana koyun.
  2. `gateway-api` IP adresi politika içindeki hangi CIDR veya istisna (`except`) kuralına takılıyor olabilir? *(Güvenlik politikasını silmeden düzeltin!)*
- **Beklenen Kanıt:** `HTTP 200 OK` ve `token-vault` yanıtı (`token-vault-netpol` aktif kalmalı).

---

### Bilet 9 — Köprü Üzerinden Raporlama (`/api/v1/bridge`) İsim Çözemiyor (`502`)
- **Canlı Test:**
  ```bash
  curl -i --max-time 4 "http://${HOST}/api/v1/bridge"
  ```
- **Gözlenen Semptom:** `gateway-api` aynı namespace içindeki `report-bridge` servisini aradığında `Name does not resolve` benzeri bir `502` hatası alıyor.
- **Nasıl Yaklaşmalısın?**
  1. `novamesh-api` namespace'indeki `report-bridge` Service tanımının türünü (`type`) ve hedefini inceleyin.
  2. `gateway-api` içine girip `nslookup report-bridge` çalıştırın. CoreDNS'in döndüğü `CNAME` kaydı başka bir namespace'deki gerçek servise tam olarak işaret edebiliyor mu?
- **Beklenen Kanıt:** `HTTP 200 OK` ve `report-service` JSON çıktısı.

---

### Bilet 10 — Doğrudan Raporlama Ingress Yolu (`/reports/daily`) `503` Veriyor
- **Canlı Test:**
  ```bash
  curl -i --max-time 4 "http://${HOST}/reports/daily"
  ```
- **Gözlenen Semptom:** Bilet 9'un aksine bu kez trafik doğrudan Ingress üzerinden `report-service` servisine gitmek istiyor ama NGINX `503 Service Temporarily Unavailable` veriyor.
- **Nasıl Yaklaşmalısın?**
  1. `novamesh-data` içindeki `report-service` servisinin dışarıya açtığı **Service Port** ile Pod'un dinlediği **targetPort** değerlerini inceleyin.
  2. Ardından `novamesh-report-ingress` tanımının backend olarak hangi port numarasına bağlanmaya çalıştığını karşılaştırın. Ingress hangi porta bağlanır?
- **Beklenen Kanıt:** `HTTP 200 OK` ve `report-service` JSON çıktısı.

---

## 5. Tam Doğrulama ve Temizlik

Tüm 10 bileti çözdüğünüzde otomatik canlı testi çalıştırın:

```bash
./check.sh
```

Tüm Azure kaynaklarını silmek için:

```bash
./cleanup.sh
```

---

# 🇬🇧 English

# NovaMesh v12.0 (Lab 29) — Real-World Production Kubernetes Networking Lab

**NovaMesh** is a 3-tier microservices architecture running on Azure Kubernetes Service (AKS + Calico CNI + NGINX Ingress Controller):

- **`novamesh-edge`**: Public Azure L4 LoadBalancer (`edge-proxy-lb`) and 5 L7 NGINX Ingress routes (`novamesh-ingress`, `novamesh-catalog-ingress`, `novamesh-partner-ingress`, `novamesh-portal-ingress`, `novamesh-report-ingress`).
- **`novamesh-api`**: `gateway-api`, `catalog-api`, `pricing-engine`, `risk-evaluator`, `receipt-service`, and `report-bridge` (cross-namespace service bridge).
- **`novamesh-data`**: `token-vault` and `report-service`.

> [!IMPORTANT]
> **Every Pod starts in `1/1 Running` state.** `kubectl get pods` will show zero crashes or restarts. You must diagnose faults like an SRE: observe live HTTP symptoms, run layer-by-layer isolation probes, and reason from evidence.

---

## 1. Setup & Environment Variables

```bash
chmod +x setup.sh check.sh cleanup.sh
./setup.sh
```

> [!NOTE]
> If an earlier AKS cluster is still active in `denmarkeast` (Azure for Students 6 vCPU limit), run its `./cleanup.sh` first. If this AKS cluster is already provisioned, pass `./setup.sh --skip-terraform`.

Export the live endpoints:

```bash
export INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
export LB_IP=$(kubectl get svc -n novamesh-edge edge-proxy-lb -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
export HOST="novamesh.${INGRESS_IP}.nip.io"
export PORTAL_HOST="portal.${INGRESS_IP}.nip.io"
```

Verify the healthy baseline route first (`200 OK`):

```bash
curl -i --max-time 4 "http://${HOST}/api/v1/health"
```

---

## 2. The 5-Gate Elimination Methodology

| Gate | Layer | Typical Live Symptom | Isolation Question |
| :--- | :--- | :--- | :--- |
| **1** | **Azure L4 LoadBalancer** | Timeout / Refused (`HTTP 000`) | Does hitting the Pod/ClusterIP internally succeed while the external LB IP fails? |
| **2** | **NGINX Ingress (L7)** | `403`, `308`, unexpected `404` JSON, or `503` | Does calling the target Service directly inside the cluster succeed while Ingress alters/blocks it? |
| **3** | **Service & Endpoints** | Immediate `502` / unreachable | Does the target Service actually have active Endpoint IPs behind it? |
| **4** | **CoreDNS & ExternalName** | `502` + DNS lookup failure | Does `nslookup` fail from inside the caller Pod while direct Pod IP reachability works? |
| **5** | **Calico NetworkPolicy** | `504 Gateway Timeout` (dropped packets) | Does the caller Pod's labels or IP CIDR violate an Ingress or Egress rule (or miss CoreDNS `:53`)? |

---

## 3. Field Engineer Toolbox

- **Inspect raw HTTP status & headers externally:**
  `curl -i --max-time 5 "http://<HOST_OR_IP>/<PATH>"`
- **Bypass Ingress/LB by calling a Service from inside a Pod:**
  `kubectl exec -n <NAMESPACE> <POD> -- python3 -c "import urllib.request; print(urllib.request.urlopen('<URL>', timeout=3).read().decode())"`
- **Ephemeral DNS/network probe Pod:**
  `kubectl run netdebug --rm -it --restart=Never --image=busybox:1.36 -n <NAMESPACE> -- sh`
- **Inspect Service Endpoints & Pod Labels/IPs:**
  `kubectl get endpoints <SERVICE> -n <NAMESPACE>` / `kubectl get pods -n <NAMESPACE> --show-labels -o wide`
- **Inspect Ingress or NetworkPolicy definitions:**
  `kubectl describe ingress <NAME> -n novamesh-edge` / `kubectl get netpol -n <NAMESPACE> -o yaml`

---

## 4. Production Support Tickets (10 Scenarios)

### Ticket 1 — External Edge LoadBalancer Unreachable
- **Live Test:** `curl -i --max-time 4 "http://${LB_IP}:8080/edge/ping"`
- **Symptom:** External LB times out or drops connections (`HTTP 000`).
- **How to Approach:** Verify `edge-proxy` responds directly inside the cluster on its container port; once confirmed healthy internally, trace the port forwarding chain (`port` -> `targetPort` -> `containerPort`) on `edge-proxy-lb`.
- **Proof:** `HTTP 200 OK` with `"status": "online"`.

### Ticket 2 — `/v2/catalog/items` Returns `404` JSON
- **Live Test:** `curl -i --max-time 4 "http://${HOST}/v2/catalog/items"`
- **Symptom:** `404` JSON containing `received_path`.
- **How to Approach:** Compare the `received_path` reported by `catalog-api` against what `catalog-api` expects internally (`/items` vs `/v2/catalog/items`). Determine how `novamesh-catalog-ingress` must rewrite the path before forwarding.
- **Proof:** `HTTP 200 OK` with `"service": "catalog-api"`.

### Ticket 3 — Partner Sync Fails with `403 Forbidden`
- **Live Test:** `curl -i --max-time 4 "http://${HOST}/partner/sync"`
- **Symptom:** NGINX rejects all requests with `403`.
- **How to Approach:** Test `/partner/sync` directly against `gateway-api` inside the cluster to confirm the app returns `200`, then inspect L7 access-control annotations on `novamesh-partner-ingress`.
- **Proof:** `HTTP 200 OK` with `"route": "partner-sync"`.

### Ticket 4 — Portal Status Returns `308 Permanent Redirect`
- **Live Test:** `curl -i --max-time 4 "http://${PORTAL_HOST}/portal/status"`
- **Symptom:** Plain HTTP returns `308` pointing to `https://...`.
- **How to Approach:** Read the `Location` response header and compare `novamesh-portal-ingress` annotations against `novamesh-ingress` to find why HTTP is forced to HTTPS in a cluster without TLS.
- **Proof:** `HTTP 200 OK` directly without redirects.

### Ticket 5 — Pricing Quote Times Out (`504`)
- **Live Test:** `curl -i --max-time 5 "http://${HOST}/api/v1/quote"`
- **Symptom:** `gateway-api` -> `pricing-engine` hangs until `504`.
- **How to Approach:** Silent timeouts usually indicate packet drops by a NetworkPolicy. Compare the actual labels on the `gateway-api` Pod against the Ingress selector inside `pricing-netpol`. *(Keep the policy active.)*
- **Proof:** `HTTP 200 OK` from `pricing-engine` with `pricing-netpol` still enforced.

### Ticket 6 — Risk Evaluator Fails (`502`)
- **Live Test:** `curl -i --max-time 6 "http://${HOST}/api/v1/risk"`
- **Symptom:** `502` referencing DNS lookup / upstream failure.
- **How to Approach:** Exec into `risk-evaluator` and test `nslookup report-service.novamesh-data.svc.cluster.local` vs connecting directly to the target IP. Check what cluster dependency `risk-netpol` omits from its Egress rules. *(Keep the policy active.)*
- **Proof:** `HTTP 200 OK` from `risk-evaluator` with `risk-netpol` still enforced.

### Ticket 7 — Receipt Service Returns Immediate `502`
- **Live Test:** `curl -i --max-time 4 "http://${HOST}/api/v1/receipt"`
- **Symptom:** Fails immediately with `upstream unreachable`.
- **How to Approach:** Check `receipt-service` Endpoints first. If empty despite a `1/1 Running` Pod, compare the Service's selector labels with the Pod's labels.
- **Proof:** `HTTP 200 OK` from `receipt-service`.

### Ticket 8 — Cross-Namespace Token Service Times Out (`504`)
- **Live Test:** `curl -i --max-time 5 "http://${HOST}/api/v1/token"`
- **Symptom:** Calls from `novamesh-api` to `token-vault` in `novamesh-data` hang with `504`.
- **How to Approach:** Inspect `gateway-api` Pod's actual IP (`-o wide`) and compare it against the CIDR/exclusion rules inside `token-vault-netpol`. *(Keep the policy active.)*
- **Proof:** `HTTP 200 OK` from `token-vault` with `token-vault-netpol` still enforced.

### Ticket 9 — Bridge Route Fails Name Resolution (`502`)
- **Live Test:** `curl -i --max-time 4 "http://${HOST}/api/v1/bridge"`
- **Symptom:** `gateway-api` cannot resolve `report-bridge`.
- **How to Approach:** Inspect `report-bridge` Service type (`ExternalName`) and run `nslookup report-bridge` inside `gateway-api` to see why cross-namespace resolution fails.
- **Proof:** `HTTP 200 OK` returning daily report JSON.

### Ticket 10 — Direct Report Ingress Route Returns `503`
- **Live Test:** `curl -i --max-time 4 "http://${HOST}/reports/daily"`
- **Symptom:** NGINX returns `503 Service Temporarily Unavailable`.
- **How to Approach:** Inspect `report-service` ports (`port` vs `targetPort`) and compare them with the backend service port referenced by `novamesh-report-ingress`.
- **Proof:** `HTTP 200 OK` returning daily report JSON.

---

## 5. Final Verification & Cleanup

Run the automated live audit suite once all 10 tickets are fixed:

```bash
./check.sh
```

Destroy all Azure resources when done:

```bash
./cleanup.sh
```
