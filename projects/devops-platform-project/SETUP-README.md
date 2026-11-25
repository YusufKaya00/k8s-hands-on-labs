# DevOps Platform Mastery — Adım Adım Kurulum & `# TODO` Bilet Rehberi (`SETUP-README.md`)

> **[← Proje Özeti ve Konu Anlatımı (README.md)](./README.md)**

Bu dosya, [projects/devops-platform-project](./README.md) projesini sıfırdan Azure AKS üzerinde kurup özellikle **LitmusChaos ChaosCenter Web UI** üzerinden canlı kaos testlerini çalıştırman için hazırlanmış 8 fazlı uygulama rehberidir.

---

### Faz 1 — Altyapı Provisioning (`Terraform`)
- [ ] **Bilet 1.1:** [terraform/main.tf](./terraform/main.tf) içinde benzersiz `acr_name` belirle.
- [ ] **Bilet 1.2–1.4:** `azurerm_container_registry`, `azurerm_kubernetes_cluster` (`Standard_B4ms`, Calico NetworkPolicy) ve `AcrPull` rol atamasını gözden geçirip uygula:
  ```bash
  cd projects/devops-platform-project/terraform
  terraform init
  terraform apply -auto-approve
  ```

---

### Faz 2 — DevSecOps CI Pipeline (`GitHub Actions`)
- [ ] **Bilet 2.1:** [ci/platform-ci.yml](./ci/platform-ci.yml) içindeki `ACR_LOGIN_SERVER` değerini kendi ACR adresinle güncelle ve `.github/workflows/platform-ci.yml` olarak kopyala.
- [ ] **Bilet 2.2:** GitHub repo ayarlarından `ACR_USERNAME` ve `ACR_PASSWORD` (Service Principal `AcrPush`) secret'larını ekle.
- [ ] **Bilet 2.3:** Workflow'u çalıştır (`pytest` → Semgrep SAST → Trivy FS/Config → Build → Trivy Image → ACR Push) ve [k8s/app-stack.yaml](./k8s/app-stack.yaml) içindeki `orders-api` imajını kendi ACR imajınla güncelle.

---

### Faz 3 — Observability (`Ders 01`: Prometheus + Grafana + Loki)
- [ ] **Bilet 3.1:** Ansible ile observability yığınını kur (`tags: [always]` sayesinde `az aks get-credentials` ve `helm repo update` otomatik çalışır; Loki ise Grafana 13 healthcheck uyumu için `--set loki.image.tag=2.9.10` ile kurulur):
  ```bash
  cd ../ansible
  ansible-playbook -i inventory.ini playbook.yml --tags observability
  ```
- [ ] **Bilet 3.2:** Grafana şifresini doğrula ve arayüze bağlan (**Kullanıcı:** `admin`, **Şifre:** `admin`):
  ```bash
  kubectl -n monitoring get secret monitoring-grafana -o jsonpath='{.data.admin-password}' | base64 -d; echo ""
  kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80
  # Tarayıcı: http://localhost:3000
  ```
- [ ] **Bilet 3.3:** Grafana içinde **Connections → Data sources → Add data source → Loki** seç:
  - **URL:** `http://loki.monitoring.svc.cluster.local:3100`
  - **Save & test** tıkla, ardından sol menüden **Explore** → **`loki-1`** seçip **Code** modunda logları sorgula:
    ```logql
    {namespace="monitoring"}
    {namespace="shop-prod"}
    ```
  > **Not:** İlk açılışta `loki-0` henüz ayağa kalkarken `loki-promtail` loglarında `connection refused` görünmesi normaldir; `loki-0` `1/1 Running` olduktan sonra log akışı otomatik başlar.

---

### Faz 4 — Backup & DR (`Ders 02`: MinIO S3 + Velero)
- [ ] **Bilet 4.1:** MinIO S3 hedefini kur (`bitnamilegacy/minio` + `5Gi` PVC):
  ```bash
  ansible-playbook -i inventory.ini playbook.yml --tags backup
  ```
- [ ] **Bilet 4.2:** MinIO Console'u aç (**Kullanıcı:** `minioadmin`, **Şifre:** `minioadmin`):
  ```bash
  kubectl -n velero port-forward svc/minio 9001:9001
  # Tarayıcı: http://localhost:9001
  ```
  - `MINIO_DEFAULT_BUCKETS=velero-backups` ayarı sayesinde `velero-backups` kovası otomatik oluşturulur (ilk Velero yedeği alınana kadar içinin boş görünmesi normaldir).

---

### Faz 5 — Service Mesh & Uygulama (`Ders 05`: Istio + `shop-prod` + Multi-Team RBAC)
> **Sıra Notu:** Vault dinamik kimlik tanımlarında `postgres.shop-prod.svc.cluster.local` ve `orders-sa` kullanıldığı için uygulamayı (`app`) ve Istio'yu Vault konfigürasyonundan önce ayağa kaldırıyoruz.

- [ ] **Bilet 5.1:** Istio Control Plane + `shop-prod` uygulama yığınını (`postgres`, `orders-api-v1`, `orders-api-v2`, `orders-pdb`, `client`) ve mesh kurallarını uygula:
  ```bash
  ansible-playbook -i inventory.ini playbook.yml --tags istio,app
  kubectl apply -f ../k8s/istio-mesh.yaml
  ```
- [ ] **Bilet 5.2:** `shop-prod` pod'larının `2/2 Ready` (`app + istio-proxy`) olduğunu gör; Canary (%80/`v1`, %20/`v2`), `x-user: beta` header ve L7 `GET`/`POST` testlerini çalıştır:
  ```bash
  kubectl -n shop-prod get pods
  # Canary 10 istek (~%80 v1, ~%20 v2-canary):
  for i in $(seq 1 10); do
    kubectl -n shop-prod exec deploy/client -c client -- curl -s http://orders-api:8080/orders; echo ""
  done
  # Beta header (%100 v2-canary):
  kubectl -n shop-prod exec deploy/client -c client -- curl -s -H "x-user: beta" http://orders-api:8080/orders; echo ""
  # L7 AuthZ (GET -> 200 OK, POST -> 403 RBAC: access denied):
  kubectl -n shop-prod exec deploy/client -c client -- curl -i -s -X POST http://orders-api:8080/orders
  ```

---

### Faz 6 — Secrets Management (`Ders 03`: HashiCorp Vault)
- [ ] **Bilet 6.1:** Vault'u kur:
  ```bash
  ansible-playbook -i inventory.ini playbook.yml --tags vault
  ```
- [ ] **Bilet 6.2:** `vault-0` üzerinde `vault operator init` + `vault operator unseal` yap, `postgres.shop-prod.svc.cluster.local:5432` üzerinde **Dynamic PostgreSQL Credentials** ve `orders-sa` için **Kubernetes Auth** tanımla.

---

### Faz 7 — DevSecOps & Runtime Security (`Ders 04`: Kyverno + Trivy Operator + Falco)
- [ ] **Bilet 7.1:** Güvenlik yığınını kur ve [k8s/security-policies.yaml](./k8s/security-policies.yaml) (Kyverno v1.20+ CEL `NamespacedValidatingPolicy` + Multi-Team `dev-readonly-sa` RBAC) kurallarını uygula:
  ```bash
  ansible-playbook -i inventory.ini playbook.yml --tags security
  kubectl apply -f ../k8s/security-policies.yaml
  ```
- [ ] **Bilet 7.2:** Politikaları, zafiyet raporlarını ve Multi-Team RBAC yetkilerini doğrula:
  ```bash
  kubectl -n shop-prod get nvpol
  kubectl -n shop-prod get vulnerabilityreports,configauditreports
  kubectl -n falco logs ds/falco --tail=20

  # Multi-Team Least-Privilege RBAC:
  kubectl auth can-i list pods -n shop-prod --as=system:serviceaccount:shop-prod:dev-readonly-sa     # yes
  kubectl auth can-i get secrets -n shop-prod --as=system:serviceaccount:shop-prod:dev-readonly-sa   # no
  ```

---

### Faz 8 — Chaos Engineering (`LitmusChaos 3.x` — ChaosCenter Web UI Rehberi)

> **2-Node AKS Notu:** Litmus MongoDB varsayılan olarak `podAntiAffinity` ile 3 replica kurmaya çalışır ve 2 node'lu AKS'de `chaos-mongodb-2` `Pending` kalabilir; `standalone` modda ise `wait-for-mongodb` init container'ının beklediği `chaos-mongodb-0.chaos-mongodb-headless` DNS adı oluşmaz (`Init:0/1`). Bu yüzden `playbook.yml` içinde **`mongodb.architecture=replicaset` + `mongodb.replicaCount=1` + `mongodb.arbiter.enabled=false`** kullanılır. Eğer yeniden kurman gerekirse eski PVC `Terminating` kalırsa `kubectl -n litmus patch pvc chaos-mongodb -p '{"metadata":{"finalizers":null}}'` ile kilidi açabilirsin.

#### Bilet 8.1 — ChaosCenter Web UI'ya Giriş
- [ ] Litmus pod'larının (`auth-server`, `frontend`, `server`, `chaos-mongodb-0`) hepsinin `1/1 Running` olduğunu doğrula ve arayüze bağlan (**Kullanıcı:** `admin`, **Şifre:** `litmus`):
  ```bash
  kubectl -n litmus get pods
  kubectl -n litmus port-forward svc/chaos-litmus-frontend-service 9091:9091
  # (9091 başka terminalde doluysa: kubectl -n litmus port-forward svc/chaos-litmus-frontend-service 9092:9091)
  # Tarayıcı: http://localhost:9091  (ilk girişte yeni şifre belirlemeni ister)
  ```

#### Bilet 8.2 — Chaos Infrastructure Bağlama (Tek Seferlik)
LitmusChaos 3.x Web UI'dan deney başlatabilmek için önce cluster'a bir **Chaos Infrastructure** ajanı bağlamalısın:

1. **Terminal 1'de port-forward açık kalsın:**
   ```bash
   kubectl -n litmus port-forward svc/chaos-litmus-frontend-service 9091:9091
   ```
2. **(`litmusctl` yoksa) CLI aracını yükle:**
   ```bash
   curl -sL https://litmusctl-production-bucket.s3.amazonaws.com/litmusctl-linux-amd64-1.28.0.tar.gz | tar -xz
   sudo mv litmusctl /usr/local/bin/ && litmusctl version
   ```
3. **`litmusctl` hesabını tanımla *(zorunlu — `~/.litmusconfig` dosyasını oluşturur)*:**
   ```bash
   litmusctl config set-account \
     --endpoint http://localhost:9091 \
     --username admin \
     --password <CHAOSCENTER_SIFREN>
   ```
4. **ChaosCenter Web UI'da Environment oluştur *(henüz yoksa)*:**
   - Sol menüden **Environments** → **+ New Environment** → **Name:** `aks-prod`, **Type:** `Production` → **Confirm**.
5. **Cluster'ı Chaos Infrastructure olarak bağla:**
   ```bash
   litmusctl connect chaos-infra \
     --name="aks-platform-infra" \
     --installation-mode="cluster" \
     --namespace="litmus" \
     --ns-exists=true \
     --service-account="litmus" \
     --sa-exists=false \
     --platform-name="Others"
   ```
   - Açılan interaktif listeden projeni ve `aks-prod` environment'ını seç, onay için `Y` yaz.
   > **Neden `Namespace: litmus` + `Cluster-wide`?** Deney runner pod'ları `shop-prod` içine düşerse `shop-prod`'daki Kyverno `require-run-as-nonroot` politikası veya Istio sidecar enjeksiyonu tarafından engellenir/geciktirilir. `litmus` namespace'inde `Cluster-wide` yetkiyle kurulduğunda `shop-prod` iş yüklerine temiz şekilde kaos enjekte edebilir. Ayrıca `chaos-litmus-server` üzerinde `CHAOS_CENTER_UI_ENDPOINT=http://chaos-litmus-frontend-service.litmus.svc.cluster.local:9091` tanımlı olduğu için `subscriber` pod'u cluster içinden doğrudan ChaosCenter'a bağlanır.
6. **Bağlantıyı doğrula:**
   - `kubectl -n litmus get pods` çıktısında `subscriber`, `chaos-operator`, `workflow-controller`, `event-tracker`, `chaos-exporter` pod'larının `Running` olduğunu ve ChaosCenter Web UI → **Environments → aks-prod** ekranında `aks-platform-infra` durumunun yeşil **`CONNECTED`** döndüğünü gör.
   > **Kapasite Notu (2-Node `Standard_B2ms`):** Azure CNI node başına en fazla 30 pod sınırına (`maxPods=30`) yaklaşırsan (`Too many pods` / `Insufficient cpu`), 3. node ekleyerek hemen yer açabilirsin:
   > `az aks nodepool scale -g rg-devops-platform-project --cluster-name aks-platform-mastery -n systempool --node-count 3`

---

#### Bilet 8.3 — UI Deney 1: `pod-delete` (Dayanıklılık & Zero-Downtime Testi)
1. Sol menüden **Chaos Experiments** → **+ New Experiment** → **Start from Blank Canvas**:
   - **Experiment Name:** `orders-pod-delete`
   - **Select Chaos Infrastructure:** `aks-platform-infra`
   - **ChaosHub:** `Litmus ChaosHub`
2. Canvas üzerinde **+** simgesine tıkla → arama kutusuna **`pod-delete`** yaz ve seç:
   - **Target Application:**
     - **Namespace:** `shop-prod`
     - **Kind:** `deployment`
     - **Label:** `app=orders-api,version=v1`
   - **Tune Fault (Parametreler):**
     - `TOTAL_CHAOS_DURATION`: `30`
     - `CHAOS_INTERVAL`: `10`
     - `FORCE`: `false`
     - `PODS_AFFECTED_PERC`: `50`
   - **Probes (Opsiyonel K8s Probe):**
     > **Önemli (Istio Notu):** `litmus` namespace'indeki unmeshed bir runner pod'u `shop-prod` içine doğrudan `HTTP Probe` atmaya çalışırsa `shop-prod`'daki `STRICT` mTLS + `AuthorizationPolicy` nedeniyle `403`/bağlantı hatası alır. UI içinde HTTP Probe yerine **`K8s Probe`** (`Group/Version: v1`, `Resource: pods`, `Namespace: shop-prod`, `Label Selector: app=orders-api,version=v1`, `Operation: present`) kullan; gerçek HTTP kesintisizlik kontrolünü ise mesh içindeki `deploy/client` üzerinden yap!
3. Sağ üstten **Save** → **Run** tıkla.
4. **Canlı Doğrulama (Deney koşarken ayrı terminalde çalıştır):**
   ```bash
   # Terminal 1 — Pod'ların silinip yeniden oluşmasını izle:
   kubectl -n shop-prod get pods -l app=orders-api -w

   # Terminal 2 — Kaos boyunca HTTP 200 OK kesintisiz akıyor mu? (orders-pdb + Istio + 2 replica sayesinde %100 200!):
   while true; do
     kubectl -n shop-prod exec deploy/client -c client -- \
       curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" http://orders-api:8080/orders
     sleep 1
   done
   ```
5. ChaosCenter UI'da deney grafiğinin yeşil **`Completed`** ve **Resilience Score: `%100`** olduğunu doğrula. *(Alternatif olarak aynı deneyi CLI'dan yapmak için [k8s/litmus-chaos.yaml](./k8s/litmus-chaos.yaml) manifesti de hazırdır.)*

---

#### Bilet 8.4 — UI Deney 2: `pod-network-latency` (Istio Canary vs Ağ Gecikmesi)
1. **Chaos Experiments** → **+ New Experiment** → `orders-v1-latency` (`aks-platform-infra`) oluştur.
2. **`pod-network-latency`** deneyini ekle:
   - **Namespace:** `shop-prod` · **Kind:** `deployment` · **Label:** `app=orders-api,version=v1`
   - **Tune Fault:** `NETWORK_LATENCY`: `2000` (2 saniye), `TOTAL_CHAOS_DURATION`: `30`, `PODS_AFFECTED_PERC`: `100`
3. **Save** → **Run** tıkla ve deney sürerken `v1` ile `v2-canary` yanıt sürelerini karşılaştır:
   ```bash
   # Normal trafik (v1 yavaşlamış ~2s, v2 hızlı):
   for i in $(seq 1 6); do
     kubectl -n shop-prod exec deploy/client -c client -- \
       curl -s -w " -> %{time_total}s\n" http://orders-api:8080/orders
   done

   # Beta kullanıcısı header'ı ile (%100 v2-canary, 0 gecikme!):
   kubectl -n shop-prod exec deploy/client -c client -- \
     curl -s -H "x-user: beta" -w " -> %{time_total}s\n" http://orders-api:8080/orders
   ```

---

#### Bilet 8.5 — UI Deney 3: `pod-cpu-hog` (Grafana Canlı CPU Tüketimi Gözlemi)
1. **Chaos Experiments** → **+ New Experiment** → `orders-cpu-stress` oluştur.
2. **`pod-cpu-hog`** deneyini ekle:
   - **Namespace:** `shop-prod` · **Kind:** `deployment` · **Label:** `app=orders-api,version=v1`
   - **Tune Fault:** `CPU_CORES`: `1`, `TOTAL_CHAOS_DURATION`: `30`
3. **Save** → **Run** tıkla; deney çalışırken Grafana (`http://localhost:3000` → **Dashboards → Kubernetes / Compute Resources / Pod** → Namespace: `shop-prod`) ve terminalden CPU sıçramasını izle:
   ```bash
   kubectl -n shop-prod top pods
   ```

---

### 🧹 Temizlik (Maliyet Kontrolü)
```bash
cd projects/devops-platform-project/terraform
terraform destroy -auto-approve
```
