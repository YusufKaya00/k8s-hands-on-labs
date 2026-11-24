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

### 📋 Uygulama & Kurulum Rehberi
Tüm 8 fazın adım adım `# TODO` biletleri, Terraform/Ansible/kubectl komutları ve LitmusChaos doğrulama adımları için **[SETUP-README.md](./SETUP-README.md)** dosyasını takip et.

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
