# DevOps Platform Mastery — Adım Adım Kurulum & `# TODO` Bilet Rehberi (`SETUP-README.md`)

> **[← Proje Özeti ve Konu Anlatımı (README.md)](./README.md)**

Bu dosya, [projects/devops-platform-project](./README.md) projesini sıfırdan Azure AKS üzerinde kurup test etmen için 8 fazlı adım adım uygulama rehberidir.

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
- [ ] **Bilet 3.1:** Ansible ile observability yığınını kur:
  ```bash
  cd ../ansible
  ansible-playbook -i inventory.ini playbook.yml --tags observability
  ```
- [ ] **Bilet 3.2:** Grafana'ya bağlanıp (`admin` / `admin`) Prometheus metriklerini ve Loki loglarını doğrula:
  ```bash
  kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80
  # http://localhost:3000
  ```

---

### Faz 4 — Backup & DR (`Ders 02`: MinIO S3 + Velero)
- [ ] **Bilet 4.1:** MinIO S3 hedefini kur:
  ```bash
  ansible-playbook -i inventory.ini playbook.yml --tags backup
  ```
- [ ] **Bilet 4.2:** MinIO Console'u (`kubectl -n velero port-forward svc/minio-console 9001:9001`) açıp `velero-backups` bucket'ını gör ve `shop-prod` için Velero yedek/geri yükleme tatbikatı yap.

---

### Faz 5 — Secrets Management (`Ders 03`: HashiCorp Vault)
- [ ] **Bilet 5.1:** Vault'u kur:
  ```bash
  ansible-playbook -i inventory.ini playbook.yml --tags vault
  ```
- [ ] **Bilet 5.2:** `vault-0` üzerinde `vault operator init` + `unseal` yap, `shop-prod/postgres` için **Dynamic PostgreSQL Credentials** ve `orders-sa` için **Kubernetes Auth** tanımla.

---

### Faz 6 — DevSecOps & Runtime Security (`Ders 04`: Kyverno + Trivy Operator + Falco)
- [ ] **Bilet 6.1:** Güvenlik yığınını kur ve politikaları uygula:
  ```bash
  ansible-playbook -i inventory.ini playbook.yml --tags security
  kubectl apply -f ../k8s/security-policies.yaml
  ```
- [ ] **Bilet 6.2:** Doğrula:
  ```bash
  kubectl -n shop-prod get nvpol
  kubectl -n shop-prod get vulnerabilityreports,configauditreports
  kubectl -n falco logs ds/falco --tail=20
  ```

---

### Faz 7 — Service Mesh & Day-2 Ops (`Ders 05`: Istio + RBAC)
- [ ] **Bilet 7.1:** Istio + uygulamayı kur ve mesh kurallarını uygula:
  ```bash
  ansible-playbook -i inventory.ini playbook.yml --tags istio,app
  kubectl apply -f ../k8s/istio-mesh.yaml
  ```
- [ ] **Bilet 7.2:** `shop-prod` pod'larının `2/2 Ready` (`istio-proxy`) olduğunu gör; Canary (%80/`v1`, %20/`v2`), `x-user: beta` header ve L7 `GET`/`POST` testlerini çalıştır:
  ```bash
  kubectl -n shop-prod get pods
  # Canary 10 istek:
  for i in $(seq 1 10); do
    kubectl -n shop-prod exec deploy/client -c client -- curl -s http://orders-api:8080/orders; echo ""
  done
  # Beta header (%100 v2):
  kubectl -n shop-prod exec deploy/client -c client -- curl -s -H "x-user: beta" http://orders-api:8080/orders; echo ""
  # L7 AuthZ (POST -> 403 RBAC: access denied):
  kubectl -n shop-prod exec deploy/client -c client -- curl -i -s -X POST http://orders-api:8080/orders
  ```
- [ ] **Bilet 7.3:** Multi-Team RBAC'ı test et:
  ```bash
  kubectl auth can-i list pods -n shop-prod --as=system:serviceaccount:shop-prod:dev-readonly-sa     # yes
  kubectl auth can-i get secrets -n shop-prod --as=system:serviceaccount:shop-prod:dev-readonly-sa   # no
  ```

---

### Faz 8 — Chaos Engineering (`LitmusChaos`)
- [ ] **Bilet 8.1:** LitmusChaos kur:
  ```bash
  ansible-playbook -i inventory.ini playbook.yml --tags litmus
  kubectl -n litmus get pods,svc
  ```
- [ ] **Bilet 8.2:** `pod-delete` deney şablonunu ve [k8s/litmus-chaos.yaml](./k8s/litmus-chaos.yaml) manifestini uygula:
  ```bash
  kubectl apply -f https://hub.litmuschaos.io/api/chaos/master?file=charts/generic/pod-delete/experiment.yaml -n shop-prod
  kubectl apply -f ../k8s/litmus-chaos.yaml
  kubectl -n shop-prod get chaosengine,chaosresult -w
  ```
- [ ] **Bilet 8.3:** Kaos sırasında `orders-api` pod'larının silinip yeniden ayağa kalktığını, `orders-pdb` + Istio ile trafiğin kesintisiz kaldığını ve `ChaosResult` çıktısının **`Verdict: Pass`** olduğunu doğrula!

---

### 🧹 Temizlik (Maliyet Kontrolü)
```bash
cd projects/devops-platform-project/terraform
terraform destroy -auto-approve
```
