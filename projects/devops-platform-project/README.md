# DevOps Platform Mastery Project — Full-Stack AKS Platform (Lessons 01–05 + LitmusChaos)

> **[🇹🇷 Türkçe](#-türkçe-bölüm) | [🇬🇧 English](#-english-section)**  
> **Mimari:** Terraform (AKS + ACR) · Ansible (Tek Playbook, Tag Bazlı Kurulum) · GitHub Actions DevSecOps CI · Prometheus/Grafana/Loki · MinIO/Velero DR · HashiCorp Vault · Kyverno/Trivy Operator/Falco · Istio Service Mesh (mTLS + Canary + L7 AuthZ) · **LitmusChaos**

---

<a id="-türkçe-bölüm"></a>
## 🇹🇷 Türkçe Bölüm

### 🎯 Proje Amacı
`lessons/01`–`lessons/05` modüllerinde tek tek öğrendiğin tüm üretim araçlarını **tek bir gerçek Azure AKS platformunda**, gereksiz dosya parçalamadan, **# TODO biletleri** üzerinden kendi ellerinle kurup **LitmusChaos** ile dayanıklılık testinden geçirmek.

### 🧠 Konu Anlatımı: Hangi Araç Neden Burada? (Büyük Resim)

Bir üretim Kubernetes platformu sadece `kubectl apply` değildir; kodun yazılmasından canlıdaki felaket/kaos anına kadar **8 farklı katman** birlikte çalışır:

| Katman | Araç | Nedir & Hangi Sorunu Çözer? |
|---|---|---|
| **Day-1 Altyapı** | **Terraform** | Azure RG, AKS cluster, ACR ve `AcrPull` IAM yetkilerini kod olarak (IaC) tekrarlanabilir şekilde kurar. |
| **Platform Kurulumu** | **Ansible** | Cluster ayağa kalktıktan sonra tüm Helm chart'larını (`--tags` ile modüler) tek komutla ve standart ayarlarla yükler. |
| **Shift-Left CI Güvenliği** | **Semgrep + Trivy (GitHub Actions)** | Kod daha cluster'a ulaşmadan SAST (kod açığı), SCA (paket açığı), Secret sızıntısı, Dockerfile ve Container Image taraması yapar; `CRITICAL` açık varsa build'i durdurur. |
| **Gözlemlenebilirlik (`Ders 01`)** | **Prometheus + Grafana + Loki** | **Prometheus** sayısal metrikleri (CPU, RAM, HTTP 5xx), **Loki** pod loglarını toplar; **Grafana** ikisini tek ekranda gösterir. |
| **Backup & DR (`Ders 02`)** | **MinIO (S3) + Velero** | `HA != Backup`. Yanlışlıkla tablo/namespace silindiğinde cluster dışındaki S3 (MinIO) kovasından `RPO = 0` hedefiyle geri dönüş sağlar. |
| **Secrets (`Ders 03`)** | **HashiCorp Vault** | Standart K8s `Secret` sadece base64'tür. Vault şifreleri şifreli tutar, pod'lara **süreli dinamik DB kullanıcısı** verir ve **Vault Agent sidecar** ile otomatik yeniler. |
| **Cluster & Runtime Güvenliği (`Ders 04`)** | **Kyverno + Trivy Operator + Falco** | **Kyverno** `:latest`/root pod'ları daha oluşmadan kapıda reddeder; **Trivy Operator** çalışan pod'ları sürekli tarar; **Falco (eBPF)** çalışan pod içinde şüpheli komut (`cat /etc/shadow`, shell) olursa anında alarm basar. |
| **Service Mesh & Day-2 Ops (`Ders 05`)** | **Istio + RBAC + PDB** | **Istio**, pod'lar arası trafiği otomatik **mTLS** ile şifreler, kod değiştirmeden **%80/%20 Canary** yapar ve L7 katmanında (`GET` izinli / `POST` 403) yetkilendirir. **RBAC** takımlara en az yetki verir; **PDB** bakım/kaos anında en az 1 pod'u ayakta tutar. |
| **Chaos Engineering** | **LitmusChaos** | *"Gerçekten dayanıklı mıyız?"* sorusunu kanıtlar. Bilinçli olarak pod silip/ağ gecikmesi verip sistemin kesintisiz kalıp kalmadığını test eder. |

#### 🔥 LitmusChaos Nasıl Çalışır? (3 Temel Obje)
1. **`ChaosExperiment`:** Litmus Hub'dan çekilen hazır deney tarifi (ör. `pod-delete`, `pod-network-latency`).
2. **`ChaosEngine`:** Deneyi belirli bir hedefe (`shop-prod` / `app=orders-api,version=v1`) ve sürelere (`TOTAL_CHAOS_DURATION: 30`) bağlayıp çalıştıran motor.
3. **`ChaosResult`:** Deney bitince **`Verdict: Pass`** veya **`Fail`** sonucunu yazan rapor objesi. (Ek olarak **ChaosCenter** Web UI üzerinden görsel olarak da yönetilebilir.)

### 📁 Sadeleştirilmiş Proje Yapısı
```text
projects/devops-platform-project/
├── terraform/main.tf             # Tek dosya: RG + AKS + ACR + AcrPull
├── ansible/
│   ├── inventory.ini
│   └── playbook.yml              # Tek playbook (--tags observability|backup|vault|security|istio|litmus|app)
├── app/                          # orders-api (Python + pytest + non-root Dockerfile)
├── ci/platform-ci.yml            # GitHub Actions DevSecOps CI (pytest + Semgrep + Trivy + ACR Push)
└── k8s/
    ├── app-stack.yaml            # shop-prod (istio-injection=enabled), PostgreSQL, orders-api v1/v2, PDB, client
    ├── istio-mesh.yaml           # Canary 80/20 + beta header + STRICT mTLS + L7 AuthorizationPolicy
    ├── security-policies.yaml    # Kyverno v1.20+ CEL ValidatingPolicy + Multi-Team RBAC
    └── litmus-chaos.yaml         # LitmusChaos ChaosEngine (pod-delete) + RBAC
```

---

### 📋 Faz & `# TODO` Bilet Listesi

#### Faz 1 — Altyapı Provisioning (`Terraform`)
- [ ] **Bilet 1.1:** [terraform/main.tf](./terraform/main.tf) içinde benzersiz `acr_name` belirle.
- [ ] **Bilet 1.2–1.4:** `azurerm_container_registry`, `azurerm_kubernetes_cluster` (`Standard_B4ms`, Calico NetworkPolicy) ve `AcrPull` rol atamasını gözden geçirip uygula:
  ```bash
  cd terraform && terraform init && terraform apply -auto-approve
  ```

#### Faz 2 — DevSecOps CI Pipeline (`GitHub Actions`)
- [ ] **Bilet 2.1–2.3:** [ci/platform-ci.yml](./ci/platform-ci.yml) içindeki `ACR_LOGIN_SERVER` değerini güncelle, `.github/workflows/` altına kopyala, `ACR_USERNAME` / `ACR_PASSWORD` secret'larını ekleyip `orders-api` imajını SAST (Semgrep) + Trivy taramasından geçirerek ACR'ye pushla.

#### Faz 3 — Observability (`Ders 01`: Prometheus + Grafana + Loki)
- [ ] **Bilet 3.1:** Ansible ile observability katmanını kur:
  ```bash
  cd ansible && ansible-playbook -i inventory.ini playbook.yml --tags observability
  ```
- [ ] **Bilet 3.2:** Grafana (`port-forward svc/monitoring-grafana 3000:80`) üzerinden Prometheus metriklerini ve Loki loglarını doğrula.

#### Faz 4 — Backup & DR (`Ders 02`: MinIO S3 + Velero)
- [ ] **Bilet 4.1:** MinIO S3 hedefini kur (`--tags backup`), Velero'yu `minio.velero.svc.cluster.local:9000` ve `velero-backups` bucket'ına bağla, `shop-prod` PostgreSQL yedeği al ve restore tatbikatı yap.

#### Faz 5 — Secrets Management (`Ders 03`: HashiCorp Vault)
- [ ] **Bilet 5.1:** Vault'u kur (`--tags vault`), `vault operator init` + `unseal` yap, `shop-prod/postgres` için **Dynamic PostgreSQL Credentials** ve `orders-sa` için **Kubernetes Auth** tanımla.

#### Faz 6 — DevSecOps & Runtime Security (`Ders 04`: Kyverno + Trivy Operator + Falco)
- [ ] **Bilet 6.1:** Güvenlik yığınını kur (`--tags security`), ardından [k8s/security-policies.yaml](./k8s/security-policies.yaml) uygula.
- [ ] **Bilet 6.2:** `shop-prod` içine `:latest` veya `root` pod göndermeyi deneyip Kyverno'nun reddettiğini gör; `kubectl -n shop-prod get vulnerabilityreports` ve `kubectl -n falco logs ds/falco` çıktılarını doğrula.

#### Faz 7 — Service Mesh & Day-2 Ops (`Ders 05`: Istio + RBAC)
- [ ] **Bilet 7.1–7.3:** Istio ve uygulamayı kur (`--tags istio,app`), ardından [k8s/istio-mesh.yaml](./k8s/istio-mesh.yaml) uygula:
  - `shop-prod` pod'larının `2/2 Ready` (`istio-proxy`) olduğunu doğrula.
  - `client` pod'undan `orders-api`'ye 10 istek atıp `%80 v1 / %20 v2` dağılımını ve `-H "x-user: beta"` ile `%100 v2` yönlendirmesini gör.
  - `GET` → `200 OK`, `POST` → `403 RBAC: access denied` olduğunu doğrula.
  - `kubectl auth can-i list pods / get secrets -n shop-prod --as=system:serviceaccount:mesh-demo:dev-readonly-sa` (ve `shop-prod:dev-readonly-sa`) ile en az yetki RBAC'ı test et.

#### Faz 8 — Chaos Engineering (`LitmusChaos`)
- [ ] **Bilet 8.1:** LitmusChaos kurulumunu çalıştır (`--tags litmus`) ve ChaosCenter arayüzüne eriş (`kubectl -n litmus get svc`).
- [ ] **Bilet 8.2:** `pod-delete` deney şablonunu ve [k8s/litmus-chaos.yaml](./k8s/litmus-chaos.yaml) manifestini uygula:
  ```bash
  kubectl apply -f https://hub.litmuschaos.io/api/chaos/master?file=charts/generic/pod-delete/experiment.yaml -n shop-prod
  kubectl apply -f k8s/litmus-chaos.yaml
  kubectl -n shop-prod get chaosengine,chaosresult -w
  ```
- [ ] **Bilet 8.3:** Kaos devam ederken `orders-api` pod'larının silinip yeniden ayağa kalktığını, `PodDisruptionBudget` (`orders-pdb`) + Istio sayesinde servisin kesintisiz `200 OK` döndüğünü ve `ChaosResult` çıktısının `Verdict: Pass` olduğunu doğrula!

---

<a id="-english-section"></a>
## 🇬🇧 English Section

### 🎯 Project Goal
A consolidated, TODO-driven AKS Platform Mastery capstone uniting **all 5 DevOps lessons** (Prometheus/Grafana/Loki, MinIO/Velero DR, HashiCorp Vault, Kyverno/Trivy Operator/Falco, Istio mTLS/Canary/L7 AuthZ + Multi-Team RBAC) with **Terraform**, **Ansible** (single tagged playbook), **GitHub Actions DevSecOps CI**, and **LitmusChaos** resilience testing.

### 🚀 Execution Order
1. **Terraform (`terraform/main.tf`):** Provision Azure RG + AKS + ACR + `AcrPull`.
2. **Ansible (`ansible/playbook.yml`):** Install the full platform stack in one shot or phase-by-phase using `--tags observability|backup|vault|security|istio|litmus|app`.
3. **Kubernetes Policies & Mesh (`k8s/`):** Apply `app-stack.yaml`, `security-policies.yaml`, and `istio-mesh.yaml`.
4. **LitmusChaos (`k8s/litmus-chaos.yaml`):** Run `pod-delete` against `orders-api` and verify `Verdict: Pass` with zero downtime under `orders-pdb` + Istio.
