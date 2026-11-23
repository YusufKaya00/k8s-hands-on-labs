# Ders 04 / Lab 1 — DevSecOps & Runtime Security Playground (Kyverno + Trivy Operator + Falco)

> **[🇹🇷 Türkçe](#-türkçe-bölüm) | [🇬🇧 English](#-english-section)**  
> **Ortam / Runtime:** %100 Yerel Minikube (`-p devsecops-lab-1`, `$0`) · **Mod:** Arıza labı değil — her aracı ne işe yaradığını anlayarak canlı deneyeceğin **sağlıklı çalışma ortamı (Sandbox)**

---

<a id="-türkçe-bölüm"></a>
## 🇹🇷 Türkçe Bölüm

### 🧠 Büyük Resim: Bu Araçlar Nedir, Hangi Sorunu Çözer?

Kubernetes güvenliği tek bir araçla değil, **katmanlı savunma (Defense in Depth)** ile yapılır. Bir isteğin/uygulamanın geçtiği 5 katman ve her katmandaki aracın gerçek görevi:

| Katman | Araçlar | Nedir & Hangi Sorunu Çözer? |
|---|---|---|
| **1. Kod & Paket (CI Öncesi)** | **SAST** (SonarQube/Semgrep) · **SCA** (Trivy/OWASP) · **DAST** (OWASP ZAP) | Kod daha image olmadan güvenlik açıklarını (SQLi, hardcoded şifre, eski kütüphane) yakalar. |
| **2. Image & Cluster İçi Sürekli Tarama** | **Trivy CLI** + **Trivy Operator** | CI'da `Trivy` ile taradığın image'da bugün açık olmayabilir ama **yarın yeni bir CVE (sıfır gün açığı)** çıkabilir. **Trivy Operator**, cluster içinde çalışan tüm pod'ları sürekli tarayıp `VulnerabilityReport` ve `ConfigAuditReport` olarak raporlar. |
| **3. Cluster Giriş Kapısı (Admission Control)** | **Kyverno** *(veya OPA Gatekeeper)* | Kubernetes API sunucusunun kapı görevlisidir. Biri `root` çalışan veya `:latest` etiketli güvensiz bir Pod YAML'ı göndermeye kalkarsa, pod daha **oluşturulmadan** kapıda reddeder (`Enforce`). |
| **4. Çalışma Anı (Runtime Security)** | **Falco** *(veya Tetragon)* | Tüm önlemlere rağmen bir saldırgan çalışan pod'un içine sızarsa ne olur? Falco, Linux çekirdeğindeki (eBPF) sistem çağrılarını (syscall) anlık izler: biri pod içinde `cat /etc/shadow`, `apk add` veya beklenmeyen shell açarsa **anında alarm üretir**. |
| **5. Ağ & Uygulama Duvarı (L7)** | **WAF** (ModSecurity/Cloudflare) · **Istio** (Service Mesh) | **WAF**, dışarıdan gelen HTTP isteklerindeki SQL Injection / XSS / bot saldırılarını Ingress kapısında engeller. **Istio** ise sadece reverse proxy değildir: her pod'un yanına Envoy sidecar koyarak **pod'lar arası şifreleme (mTLS)**, **L7 kimlik/yetki politikası** ve **Canary trafik bölme** yapar *(Ders 05'te detaylı işlenecek)*. |

---

### 🚀 Kurulum

```bash
cd lessons/04-devsecops-runtime-security/lab-1
./setup.sh
```
Kurulum şunları ayağa kaldırır:
- `kyverno` namespace → **Kyverno** (Policy Engine)
- `trivy-system` namespace → **Trivy Operator** (`demo-sec` namespace'ini izler)
- `falco` namespace → **Falco** (`modern_ebpf` ile canlı kernel izleme)
- `demo-sec` namespace → `web-target` (`nginx:1.25-alpine`) örnek uygulaması

---

### Adım 1 — Trivy Operator: Cluster İçi Sürekli Zafiyet & Konfigürasyon Taraması

`setup.sh` bittikten ~30–60 saniye sonra Trivy Operator `demo-sec` içindeki `web-target` pod'unu otomatik tarayıp Kubernetes CRD'leri olarak rapor üretir:

```bash
# Oluşan güvenlik raporlarını listele:
kubectl --context devsecops-lab-1 -n demo-sec get vulnerabilityreports,configauditreports

# Zafiyet raporunun özetini (CRITICAL / HIGH / MEDIUM sayıları) gör:
kubectl --context devsecops-lab-1 -n demo-sec get vulnerabilityreports -o wide

# Konfigürasyon denetim raporunu (ör. root çalışıyor mu, readOnlyRootFilesystem eksik mi?) incele:
kubectl --context devsecops-lab-1 -n demo-sec describe configauditreports
```
> **Ne öğrendik?** CI'da Trivy çalıştırmak tek seferliktir; **Trivy Operator** ise cluster'da çalışan iş yüklerini sürekli denetleyip Kubernetes API üzerinden (`kubectl get vulnerabilityreports`) görünür kılar.

---

### Adım 2 — Kyverno: Güvensiz Pod'ları Kapıda Engelleme (Policy as Code)

Şu an `demo-sec` namespace'inde hiç Kyverno kuralı yok. Şimdi [manifests/kyverno-policies.yaml](./manifests/kyverno-policies.yaml) dosyasını incele ve uygula:
- `disallow-latest-tag`: `:latest` kullanan pod'ları engeller.
- `require-run-as-nonroot`: `runAsNonRoot: true` olmayan pod'ları engeller.

```bash
# 1. Kyverno kurallarını cluster'a yükle:
kubectl --context devsecops-lab-1 apply -f manifests/kyverno-policies.yaml
kubectl --context devsecops-lab-1 get clusterpolicy

# 2. Güvensiz pod'u (nginx:latest + root) göndermeyi dene -> KAPIDA REDDEDİLECEK!
kubectl --context devsecops-lab-1 apply -f manifests/bad-pod.yaml

# 3. Sertleştirilmiş (hardened) pod'u gönder -> KABUL EDİLECEK!
kubectl --context devsecops-lab-1 apply -f manifests/good-pod.yaml
kubectl --context devsecops-lab-1 -n demo-sec get pods
```
> **Ne öğrendik?** Geliştirici yanlışlıkla `root` veya `:latest` kullanan bir YAML yazsa bile, **Kyverno** bunu daha pod çalışmadan Kubernetes API kapısında durdurur.

---

### Adım 3 — SecurityContext & Seccomp Hardening Deneyi

[manifests/good-pod.yaml](./manifests/good-pod.yaml) içindeki güvenlik kısıtlarını canlı test et (`runAsNonRoot`, `readOnlyRootFilesystem`, `capabilities.drop: [ALL]`, `seccompProfile: RuntimeDefault`):

```bash
# Pod'un hangi kullanıcıyla (UID 1000 — root değil!) çalıştığını gör:
kubectl --context devsecops-lab-1 -n demo-sec exec good-pod -- id

# Dosya sistemine yazmayı dene -> 'Read-only file system' hatası almalısın:
kubectl --context devsecops-lab-1 -n demo-sec exec good-pod -- touch /tmp/hack.txt
```

---

### Adım 4 — Falco (eBPF): Çalışan Pod İçinde Saldırı / Şüpheli Davranış Yakalama

Bir saldırganın `web-target` pod'unun içine sızdığını simüle et ve Falco'nun Linux kernel (eBPF) seviyesinde bunu saniyeler içinde nasıl yakaladığını izle:

```bash
# 1. Pod içinde shell açıp hassas dosya (/etc/shadow) oku:
kubectl --context devsecops-lab-1 -n demo-sec exec deploy/web-target -- sh -c "cat /etc/shadow >/dev/null 2>&1 || true"

# 2. Falco loglarına bak -> 'Terminal shell in container' ve 'Read sensitive file untrusted' alarmlarını göreceksin!
kubectl --context devsecops-lab-1 -n falco logs ds/falco --tail=25 | grep -E "Warning|Error|Notice|shadow|shell"
```
> **Ne öğrendik?** Trivy (image tarama) ve Kyverno (giriş kontrolü) **önleyici** katmandır; **Falco** ise çalışan pod içinde olağandışı bir şey olduğunda seni anında uyaran **runtime güvenlik kamerasıdır**.

---

### 🧹 Temizlik

```bash
./cleanup.sh
```

---

<a id="-english-section"></a>
## 🇬🇧 English Section

### 🎯 What Is Included?
A clean, healthy **100% local Minikube (`-p devsecops-lab-1`, `$0`)** hands-on playground (not a broken troubleshooting lab) demonstrating Kubernetes **Defense in Depth**:
- **Trivy Operator (`trivy-system`):** Continuous in-cluster `VulnerabilityReport` & `ConfigAuditReport` generation for `demo-sec`.
- **Kyverno (`kyverno`):** Admission-time policy enforcement blocking `:latest` tags and root pods (`manifests/kyverno-policies.yaml`).
- **Falco (`falco`, `modern_ebpf`):** Real-time Linux kernel syscall threat detection alerting on interactive shells or sensitive file reads (`/etc/shadow`).
- **Hardened Workload (`demo-sec`):** Comparing `manifests/bad-pod.yaml` vs `manifests/good-pod.yaml` (`runAsNonRoot`, `readOnlyRootFilesystem`, `seccompProfile: RuntimeDefault`, `drop: [ALL]`).

### 🚀 Quick Start

```bash
cd lessons/04-devsecops-runtime-security/lab-1
./setup.sh
```

Follow Steps 1–4 above to inspect Trivy Operator reports, test Kyverno admission blocking (`bad-pod.yaml` vs `good-pod.yaml`), verify `SecurityContext`/`Seccomp` hardening, and trigger live Falco eBPF runtime alerts. Tear down anytime with `./cleanup.sh`.
