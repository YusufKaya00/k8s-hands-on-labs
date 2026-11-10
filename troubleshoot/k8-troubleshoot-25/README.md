# 🌐 K8s Troubleshoot Lab 25: NetPulse v8.0 — Zero-Trust Network, DNS, Service & Ingress Deep-Dive

### 📋 Lab Özeti (Incident Briefing)

| Alan | Detay |
| :--- | :--- |
| **Platform** | **NetPulse v8.0** — Zero-Trust Cloud-Native Telemetry & Payment Mesh |
| **Odak Noktası** | **Kubernetes Networking (%75 Ağ & Güvenlik: Ingress, NetworkPolicy, DNS, Service/Endpoints, Headless DNS, Loopback Bind) + (%25 Core Workloads: StatefulSet, DaemonSet, RBAC, Job/HPA/PDB)** |
| **Etkilenen Alanlar** | `netpulse-data`, `netpulse-core`, `netpulse-edge` (3 Namespace, 16 Görev) |
| **Kontrol Aracı** | `./check.sh` — İstediğiniz her an çalıştırabileceğiniz, 16 adımı tek tek test eden interaktif doğrulama scripti (Helm hook engeli **yoktur**!) |
| **Çözüm Anahtarı** | [`SOLUTION.md`](./SOLUTION.md) — Tüm 16 hatanın detaylı kök neden analizi, teşhis komutları ve tam çözümleri |

---

### 🧠 Lab Öncesi Aklında Kalması Gereken 7 Altın Kubernetes Ağ Kuralı

Bu labı çözerken aşağıdaki **7 temel ağ kuralını** bizzat deneyimleyerek kalıcı olarak pekiştireceksin:

1. **Ingress `ADDRESS` Neden Boş Kalır?**
   - `Ingress` tek başına bir yönlendirici değil, bir kural kağıdıdır. Kümedeki `ingress-nginx-controller` podu yalnızca `spec.ingressClassName: nginx` olan Ingress objelerini sahiplenir. Eğer `ingressClassName` yanlışsa (`istio-external` vb.), Controller o Ingress'i görmezden gelir ve **`ADDRESS` sütunu boş kalır**.
2. **Ingress Hata Kodlarının Anlamı (`404` vs `502` vs `504`):**
   - **`404 Not Found`:** İstek NGINX Ingress Controller'a ulaştı ama Ingress içindeki `host` veya `path` (`/v2/internal` vs `/`) istekle eşleşmedi.
   - **`502 Bad Gateway`:** Ingress veya Reverse Proxy arka uçtaki servise gitmek istedi ama ya Service'in `Endpoints` listesi boş (`<none>`) ya da pod `Connection refused` döndü (yanlış port veya `127.0.0.1` loopback bind).
   - **`504 Gateway Time-out`:** Paket yolda bir **NetworkPolicy** (güvenlik duvarı) tarafından sessizce düşürüldü (`DROP`).
3. **`127.0.0.1` (Loopback) vs `0.0.0.0` Bind Tuzağı:**
   - Bir uygulama pod içinde `127.0.0.1:9000` adresini dinlerse, sadece o podun kendi içinden (`localhost`) erişilebilir. Kubelet (Readiness/Liveness probe) ve diğer podlar **Pod IP'si** üzerinden geldiği için `Connection refused` alır! Container uygulamaları her zaman **`0.0.0.0`** dinlemelidir.
4. **Service -> Endpoints -> Pod Bağlantısı:**
   - Bir `Service` objesinin trafiği podlara iletebilmesi için:
     1. `Service.spec.selector` etiketleri ile Pod etiketleri **birebir** eşleşmelidir (eşleşmezse `kubectl get endpoints` çıktısı `<none>` olur).
     2. `Service.spec.ports[].targetPort` değeri, Podun `containerPort` numarası veya `name` (`http-api`) alanıyla eşleşmelidir.
5. **Headless Service (`clusterIP: None`) ve StatefulSet Pod DNS Kaydı:**
   - Bir `StatefulSet` poduna (`ledger-db-0`) doğrudan DNS adıyla (`ledger-db-0.ledger-headless.netpulse-data.svc.cluster.local`) erişebilmek için `StatefulSet.spec.serviceName` alanı ile Headless `Service.metadata.name` alanı (`ledger-headless`) **birebir aynı** olmalıdır. Farklıysa CoreDNS kayıt oluşturmaz (`NXDOMAIN`).
6. **Farklı Namespace'ler Arası (Cross-Namespace) DNS Kuralı:**
   - Aynı namespace içindeki podlar birbirine kısa servis adıyla (`http://payment-engine:8080`) ulaşabilir. Ancak `netpulse-edge` içindeki bir pod, `netpulse-core` içindeki bir servise kısa adla **ulaşamaz**; tam **FQDN** (`http://payment-engine.netpulse-core.svc.cluster.local:8080`) kullanmak zorundadır.
7. **NetworkPolicy `Egress` ve CoreDNS (`Port 53`) Tuzağı:**
   - Bir namespace'te `policyTypes: ["Egress"]` içeren bir `NetworkPolicy` tanımladığınız an, izin verilmeyen **tüm çıkışlar kapanır**. Eğer `kube-system` namespace'ine **`UDP 53` ve `TCP 53`** (CoreDNS) çıkış izni vermezseniz, pod hiçbir domain adını IP'ye çeviremez (`Temporary failure in name resolution`)!

---

### 🏗️ Hedeflenen Mimari ve Ağ Akışı (Target Architecture)

```mermaid
flowchart TD
    Client(["🌐 İstemci (curl)<br/>http://netpulse.<IP>.nip.io/api/v1/status"]) -->|"1. HTTP :80"| IngCtrl["🚪 NGINX Ingress Controller<br/>(ns: ingress-nginx)"]
    
    subgraph EdgeNS ["🌐 Namespace: netpulse-edge (label: netpulse.io/tier=edge)"]
        IngObj["Ingress: netpulse-ingress<br/>(ingressClassName: nginx, path: /)"]
        EdgeNP["🛡️ NetworkPolicy: edge-netpol<br/>(Ingress from ns: ingress-nginx :8080)"]
        EdgeSvc["Service: edge-router (:8080)"]
        EdgePod["Deployment: edge-router<br/>(NGINX Reverse Proxy :8080)"]
        
        IngCtrl -->|"2. edge-netpol kontrolü"| EdgeSvc
        EdgeSvc --> EdgePod
    end

    subgraph CoreNS ["⚙️ Namespace: netpulse-core (label: netpulse.io/tier=core)"]
        CoreNP["🛡️ NetworkPolicy: core-netpol<br/>Ingress: tier=edge (:8080)<br/>Egress: DNS(:53) + tier=data(:6379, :9000)"]
        CoreSvc["Service: payment-engine (:8080 -> targetPort: http-api)"]
        CorePod["Deployment: payment-engine (2 Replicas)<br/>init-1: init-verify-endpoints (RBAC)<br/>init-2: init-wait-ledger (DNS + TCP)<br/>main: Python API (:8080 /healthz & /api/v1/status)"]
        SeedJob["Job: ledger-seed"]
        Cron["CronJob: reconcile-cron"]
        ArchivePVC[("PVC: audit-archive-pvc")]
        HPA["HPA: payment-engine-hpa"]
        PDB["PDB: payment-engine-pdb"]

        EdgePod -->|"3. Cross-NS FQDN HTTP :8080<br/>payment-engine.netpulse-core.svc.cluster.local"| CoreSvc
        CoreSvc -->|"Selector: component=core-engine"| CorePod
        CorePod --> ArchivePVC
        Cron --> ArchivePVC
    end

    subgraph DataNS ["🔐 Namespace: netpulse-data (label: netpulse.io/tier=data)"]
        DataNP["🛡️ NetworkPolicy: data-zero-trust<br/>Ingress from tier=core (:6379, :9000)"]
        HeadlessSvc["Headless Service: ledger-headless<br/>(clusterIP: None, :6379)"]
        LedgerSTS["StatefulSet: ledger-db (ledger-db-0)<br/>(serviceName: ledger-headless, SC: managed-csi)"]
        SignerSvc["Service: token-signer (:9000)"]
        SignerPod["Deployment: token-signer<br/>(Bind: 0.0.0.0:9000)"]
        AgentDS["DaemonSet: net-agent"]

        HeadlessSvc --> LedgerSTS
        SignerSvc --> SignerPod
    end

    CorePod -->|"4. UDP/TCP :53"| CoreDNS(["🧭 CoreDNS (ns: kube-system)"])
    CorePod -->|"5. StatefulSet DNS TCP :6379"| HeadlessSvc
    CorePod -->|"6. HTTP :9000 (/v1/sign)"| SignerSvc
    SeedJob -->|"TCP :6379"| HeadlessSvc
```

---

### 🚀 Kurulum ve Güncelleme Komutları

#### 1. Ortamı Kurmak İçin:
```bash
chmod +x setup.sh cleanup.sh check.sh
./setup.sh
```

#### 2. Durumu ve İlerlemeni Kontrol Etmek İçin (`check.sh`):
Herhangi bir anda kaç hatayı çözdüğünü ve sıradaki hatanın ne olduğunu görmek için:
```bash
./check.sh
```

#### 3. `helm/netpulse/values.yaml` Dosyasını Güncelledikten Sonra Uygulamak İçin:
> Bu labda `helm upgrade` komutunu engelleyen hiçbir hook yoktur! Doğrudan çalıştırabilirsin:
```bash
INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

helm upgrade --install netpulse ./helm/netpulse \
  --namespace netpulse-core \
  --set global.ingressHost="netpulse.${INGRESS_IP}.nip.io"
```

---

### 🛠️ Adım Adım Sorun Giderme Rehberi (Namespace Bazlı 16 Görev)

Sorunları rastgele aramak yerine `./check.sh` çıktısındaki sırayla, **aşağıdan yukarıya (`netpulse-data` -> `netpulse-core` -> `netpulse-edge`)** doğru çöz:

---

#### 📦 BÖLÜM 1: Veri Katmanı (`namespace: netpulse-data`)

Önce `netpulse-data` içindeki tüm kaynakları listele (`Not: Bu namespace'te Job yoktur, StatefulSet, Deployment, DaemonSet, Service, PVC ve NetworkPolicy vardır`):
```bash
kubectl get sts,deploy,ds,pods,svc,pvc,netpol -n netpulse-data
```

* **Görev 1 — `ledger-db-0` Podu Neden `Pending` Durumunda?**
  - **Teşhis Komutu:**
    ```bash
    kubectl describe pvc ledger-storage-ledger-db-0 -n netpulse-data
    kubectl get sc
    ```
  - **Nereye Bakmalı?** `values.yaml` -> `ledgerDb.storageClassName`.
  - **Önemli Not:** `StatefulSet.volumeClaimTemplates` ve `PVC` alanları *immutable* (değiştirilemez) olduğu için `values.yaml`'ı düzelttikten sonra eski StatefulSet ve PVC'yi silip `helm upgrade` çalıştır:
    ```bash
    kubectl delete sts ledger-db -n netpulse-data
    kubectl delete pvc ledger-storage-ledger-db-0 -n netpulse-data
    ```

* **Görev 2 — `ledger-db-0` Podunun Headless DNS Kaydı Neden Oluşmuyor?**
  - **Teşhis Komutu:**
    ```bash
    kubectl get svc -n netpulse-data
    kubectl get sts ledger-db -n netpulse-data -o jsonpath='{.spec.serviceName}{"\n"}'
    ```
  - **Nereye Bakmalı?** Headless Service'in adı `ledger-headless` iken `StatefulSet`'in `spec.serviceName` alanı ne olarak ayarlanmış? (`values.yaml` -> `ledgerDb.serviceName`). *Not: Değiştirdikten sonra `kubectl delete sts ledger-db -n netpulse-data` yapıp upgrade çalıştırmayı unutma.*

* **Görev 3 — `token-signer` Podu `Running` Olduğu Halde Neden `0/1 Ready` Kalıyor?**
  - **Teşhis Komutu:**
    ```bash
    kubectl logs -n netpulse-data -l app=token-signer
    kubectl describe pod -n netpulse-data -l app=token-signer
    ```
  - **Nereye Bakmalı?** Loglardaki uyarıyı oku! Uygulama hangi IP adresini (`127.0.0.1` vs `0.0.0.0`) dinliyor? (`values.yaml` -> `tokenSigner.bindAddress`).

* **Görev 4 — `data-zero-trust` NetworkPolicy Neden `netpulse-core` Trafiğini Engelliyor?**
  - **Teşhis Komutu:**
    ```bash
    kubectl describe netpol data-zero-trust -n netpulse-data
    kubectl get ns --show-labels
    ```
  - **Nereye Bakmalı?** `data-zero-trust` hangi `netpulse.io/tier` etiketine sahip namespace'e izin veriyor? Ayrıca `token-signer` servisi `9000` portunda çalışırken NetworkPolicy hangi porta izin vermiş? (`values.yaml` -> `dataNetworkPolicy`).

* **Görev 5 — `net-agent` DaemonSet Neden `0` Pod Oluşturuyor ve Başlayınca Çöküyor?**
  - **Teşhis Komutu:**
    ```bash
    kubectl describe ds net-agent -n netpulse-data
    kubectl get nodes --show-labels
    ```
  - **Nereye Bakmalı?** `values.yaml` -> `netAgent.nodeSelector` (boş bırakmak için `nodeSelector: {}` yapabilirsin) ve `mountRunEmptyDir` ayarı.

---

#### ⚙️ BÖLÜM 2: Çekirdek Katman (`namespace: netpulse-core`)

Önce `netpulse-core` içindeki kaynakları listele:
```bash
kubectl get deploy,pods,svc,endpoints,job,cronjob,hpa,pdb,netpol -n netpulse-core
```

* **Görev 6 — `payment-engine` Podu Neden `Init:0/2` (`init-verify-endpoints`) Aşamasında Kalıyor?**
  - **Teşhis Komutu:**
    ```bash
    kubectl logs -n netpulse-core -l app=payment-engine -c init-verify-endpoints
    kubectl get role core-endpoint-reader -n netpulse-core -o yaml
    ```
  - **Nereye Bakmalı?** Init container K8s API üzerinden hem `services` hem de `endpoints` yetkisi kontrol ediyor. `values.yaml` -> `rbac.allowedResources` listesinde hangisi eksik?

* **Görev 7 — `payment-engine` Podu `Init:1/2` (`init-wait-ledger`) Aşamasında Neden DNS Çözemiyor?**
  - **Teşhis Komutu:**
    ```bash
    kubectl logs -n netpulse-core -l app=payment-engine -c init-wait-ledger
    kubectl describe netpol core-netpol -n netpulse-core
    ```
  - **Nereye Bakmalı?** `core-netpol` üzerinde `Egress` politikası aktif! Ama CoreDNS (`kube-system` port `53/UDP` ve `53/TCP`) izni açık mı? (`values.yaml` -> `coreNetworkPolicy.allowDnsEgress`).

* **Görev 8 — DNS Çözüldükten Sonra `init-wait-ledger` Neden `token-signer:9000` Bağlantısında Takılıyor?**
  - **Teşhis Komutu:**
    ```bash
    kubectl describe netpol core-netpol -n netpulse-core
    ```
  - **Nereye Bakmalı?** `core-netpol` Egress kurallarında `netpulse-data` yönüne `6379` yanı sıra hangi porta izin verilmiş? `token-signer` gerçekte hangi portta çalışıyor? (`values.yaml` -> `coreNetworkPolicy.allowedDataSignerPort`).

* **Görev 9 — `payment-engine` Ana Konteyneri Başladıktan Sonra Neden Sürekli Restart Oluyor?**
  - **Teşhis Komutu:**
    ```bash
    kubectl describe pod -n netpulse-core -l app=payment-engine
    ```
  - **Nereye Bakmalı?** `Events` kısmındaki `Liveness probe failed` mesajına bak! Uygulama `8080` portunda çalışırken `livenessProbe` hangi portu kontrol ediyor? (`values.yaml` -> `paymentEngine.livenessProbe.port`).

* **Görev 10 — `payment-engine` Podları `1/1 Running` Olduğu Halde `Service` Arkasında Neden `Endpoints` Yok (`<none>`)?**
  - **Teşhis Komutu:**
    ```bash
    kubectl get endpoints payment-engine -n netpulse-core
    kubectl describe svc payment-engine -n netpulse-core
    kubectl get pods -n netpulse-core --show-labels
    ```
  - **Nereye Bakmalı?**
    1. Podların `component` etiketi (`core-engine`) ile Service'in `Selector` (`legacy-engine`) etiketi uyuşuyor mu? (`paymentEngine.serviceSelectorComponent`)
    2. Podun containerPort adı (`http-api`) ile Service'in `TargetPort` (`http-legacy`) adı uyuşuyor mu? (`paymentEngine.serviceTargetPort`)

* **Görev 11 — `ledger-seed` Job'ı Neden `Error` Veriyor ve `HPA` / `PDB` Neden Hatalı?**
  - **Teşhis Komutu:**
    ```bash
    kubectl logs -n netpulse-core -l app=ledger-seed
    kubectl get hpa,pdb -n netpulse-core
    ```
  - **Nereye Bakmalı?**
    - `batch.seedJob.targetRedisPort` (`6380` yerine `6379` olmalı; düzelttikten sonra `kubectl delete job ledger-seed -n netpulse-core` yapıp upgrade çalıştır).
    - `scaling.hpa.targetDeploymentName` (`payment-engine` olmalı) ve `scaling.pdb.minAvailable` (`1` olmalı).

---

#### 🚪 BÖLÜM 3: Edge Gateway & Ingress Katmanı (`namespace: netpulse-edge`)

Önce `netpulse-edge` içindeki kaynakları listele:
```bash
kubectl get deploy,pods,svc,endpoints,ingress,netpol -n netpulse-edge
```

* **Görev 12 — `edge-router` Podu Neden `CrashLoopBackOff` Durumunda?**
  - **Teşhis Komutu:**
    ```bash
    kubectl logs -n netpulse-edge -l app=edge-router
    kubectl get cm edge-router-conf -n netpulse-edge -o yaml
    ```
  - **Nereye Bakmalı?** NGINX logunda `host not found in upstream "payment-engine"` hatasını göreceksin! `netpulse-edge` içindeki bir pod, `netpulse-core` içindeki `payment-engine` servisine kısa adla gidebilir mi? Tam FQDN (`http://payment-engine.netpulse-core.svc.cluster.local:8080`) yazıp `helm upgrade` sonrası podu yeniden başlat (`kubectl rollout restart deploy edge-router -n netpulse-edge`).

* **Görev 13 — `edge-router` Çalıştıktan Sonra `payment-engine`'e Giden İstekler Neden `core-netpol` Tarafından Bloklanıyor?**
  - **Teşhis Komutu:**
    ```bash
    kubectl describe netpol core-netpol -n netpulse-core
    kubectl get ns netpulse-edge --show-labels
    ```
  - **Nereye Bakmalı?** `core-netpol` Ingress kuralı `netpulse.io/tier: api-gateway` bekliyor, oysa `netpulse-edge` namespace'inin gerçek etiketi nedir? (`values.yaml` -> `coreNetworkPolicy.allowedIngressTier`).

* **Görev 14 — NGINX Ingress Controller'dan `edge-router` Poduna Gelen İstekler Neden `edge-netpol` Tarafından Bloklanıyor?**
  - **Teşhis Komutu:**
    ```bash
    kubectl describe netpol edge-netpol -n netpulse-edge
    kubectl get ns ingress-nginx --show-labels
    ```
  - **Nereye Bakmalı?** `edge-netpol` hangi namespace isminden (`kubernetes.io/metadata.name`) gelen trafiğe izin veriyor? NGINX Ingress Controller hangi namespace'te çalışıyor? (`values.yaml` -> `edgeNetworkPolicy.allowedIngressControllerNamespace`).

* **Görev 15 — `kubectl get ingress -n netpulse-edge` Çıktısında `ADDRESS` Neden Boş?**
  - **Teşhis Komutu:**
    ```bash
    kubectl get ingress -n netpulse-edge
    kubectl get ingressclass
    ```
  - **Nereye Bakmalı?** Kümedeki aktif IngressClass adı `nginx` iken `values.yaml` -> `ingress.className` içinde ne yazıyor?

* **Görev 16 — `ADDRESS` Dolduktan Sonra `curl http://netpulse.<IP>.nip.io/api/v1/status` Neden `404 Not Found` Dönüyor?**
  - **Teşhis Komutu:**
    ```bash
    kubectl describe ingress netpulse-ingress -n netpulse-edge
    ```
  - **Nereye Bakmalı?** Ingress kuralındaki `Path` alanı `/v2/internal` olarak bırakılmış! Tüm `/api/...` isteklerini karşılaması için `values.yaml` -> `ingress.path` değerini `/` yap!

---

### ✅ Final Kontrolü (`./check.sh`)

Tüm değişiklikleri uyguladıktan sonra:
```bash
./check.sh
```
Çıktıda **`16/16 Başarılı`** ve aşağıdaki JSON yanıtını görüyorsan labı başarıyla tamamladın demektir:
```json
{
  "platform": "NetPulse v8.0",
  "status": "operational",
  "ledger_db": "v8.0-ready",
  "token_signer": "ed25519-verified",
  "pod": "payment-engine-..."
}
```
