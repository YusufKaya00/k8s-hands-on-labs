# 04 — Harbor, Jenkins, Kaniko ve RKE2 Sorun Çözme Rehberi (Troubleshooting Playbook)

Bu doküman, kendi sunucunuzda (Self-Hosted) Harbor, Trivy, Jenkins ve RKE2 çalıştırırken gerçek hayatta en sık karşılaşılan **6 kritik hatayı**, kök nedenlerini ve çözüm komutlarını içerir.

---

## 1. Hata: `ErrImagePull: http: server gave HTTP response to HTTPS client` veya `x509: certificate signed by unknown authority`

### Belirti
`kubectl describe pod -n app <pod-adi>` çıktısında şu hata görülür:
```text
Failed to pull image "harbor.<IP>.nip.io/supplyshield/supplyshield-api:1.0.0":
rpc error: code = Unknown desc = failed to pull and unpack image:
http: server gave HTTP response to HTTPS client
```

### Kök Neden
Kubernetes düğümündeki `containerd` çalışma zamanı, aksi belirtilmedikçe tüm kayıt defterlerine **HTTPS** ile bağlanmaya çalışır. Eğer yeni bir işçi düğüm (worker node) eklediyseniz ve o düğümde `/etc/rancher/rke2/registries.yaml` dosyası yoksa veya RKE2 servisi yeniden başlatılmadıysa bu hata oluşur.

### Çözüm
İlgili düğümde `/etc/rancher/rke2/registries.yaml` dosyasını kontrol edin ve RKE2 servisini yeniden başlatın:
```bash
sudo cat /etc/rancher/rke2/registries.yaml
# Master düğümde:
sudo systemctl restart rke2-server
# Worker düğümde:
sudo systemctl restart rke2-agent
```

---

## 2. Hata: Jenkins Build Başlatıldığında Agent Pod `Pending` Durumunda Kalıyor

### Belirti
Jenkins'te **Build Now** dediğinizde iş `"Waiting for next available executor"` mesajında bekliyor ve `kubectl get pods -n jenkins` çıktısında oluşan ajan podu `Pending` durumunda kalıyor.

### Kök Neden
1. **Taint Eksikliği:** `vm-worker-secops` düğümümüzde `dedicated=secops:NoSchedule` Taint'i vardır. Eğer yazdığınız `Jenkinsfile` içerisindeki pod şablonunda (`yaml`) bu Taint için `tolerations` tanımlanmadıysa Scheduler podu yerleştiremez.
2. **RAM / CPU Yetersizliği:** `vm-worker-secops` düğümü 4 GB RAM'e sahiptir. Ajan podunun içindeki konteynerlere çok yüksek `requests.memory` (ör. `2Gi`) verirseniz `0/3 nodes are available: Insufficient memory` hatası alırsınız.

### Çözüm
```bash
kubectl describe pod -n jenkins <jenkins-agent-pod-adi>
```
`Jenkinsfile` içindeki `tolerations` bloğunun `dedicated=secops:NoSchedule` içerdiğinden ve konteyner `requests.memory` toplamının `384Mi` civarında olduğundan emin olun.

---

## 3. Hata: Kaniko Push Sırasında `UNAUTHORIZED: authentication required`

### Belirti
Jenkins Pipeline'ının 3. aşamasında (Kaniko Build & Push) şu hata alınır:
```text
error pushing image: failed to push to destination harbor.<IP>.nip.io/supplyshield/supplyshield-api:1.0.1:
UNAUTHORIZED: authentication required
```

### Kök Neden
1. `jenkins` namespace'i içindeki `harbor-regcred` Secret'ı eksik veya yanlış IP adresiyle oluşturulmuş olabilir.
2. Harbor içerisinde `supplyshield` projesi henüz oluşturulmamış olabilir.

### Çözüm
```bash
# 1) Secret içeriğini çözüp doğru Harbor adresini barındırdığını kontrol edin:
kubectl get secret harbor-regcred -n jenkins -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d | jq .

# 2) Harbor'da 'supplyshield' projesinin var olduğunu doğrulayın:
MASTER_IP=$(curl -s ifconfig.me)
curl -u 'admin:AdminPassword2026!' "http://harbor.${MASTER_IP}.nip.io/api/v2.0/projects?name=supplyshield"
```

---

## 4. Hata: Harbor Trivy Tarayıcısı `Pending` veya `Error` Veriyor

### Belirti
Harbor'a imaj yüklendiğinde Trivy tarama durumu `Error` oluyor.

### Kök Neden
`harbor-trivy-0` podu ilk kurulduğunda GitHub Container Registry (`ghcr.io/aquasecurity/trivy-db`) üzerinden ~50 MB boyutundaki güncel CVE zafiyet veritabanını indirir. Eğer `vm-worker-secops` düğümünün NAT Gateway internet çıkışı yoksa veya disk doluysa indirme başarısız olur.

### Çözüm
```bash
# Trivy pod loglarını inceleyin:
kubectl logs -n harbor statefulset/harbor-trivy --tail=50
```

---

## 5. Hata: Harbor `Prevent Vulnerable Images` Açıkken Podlar `ErrImagePull (412 Precondition Failed)` Alıyor

### Belirti
Canlı ortamdaki podlar imaj çekerken şu hatayı verir:
```text
Error response from daemon: current image with "X" vulnerabilities cannot be deployed
due to configured policy in 'Prevent images with vulnerability severity of "High" or higher from running.'
```

### Kök Neden
Bu bir sistem arızası değil, **Lab 5'te açtığınız DevSecOps güvenlik kapısının (Security Gate) görevini yapmasıdır!** İmajda bulunan zafiyet, belirlediğiniz eşik değerinin üzerindedir.

### Çözüm
1. **Gerçek Çözüm:** `app/Dockerfile` içindeki taban imajı ve paketleri güncelleyip (`apt-get upgrade -y` / güncel `requirements.txt`) yeni bir Jenkins derlemesi başlatmak.
2. **Politikayı Esnetmek:** Harbor UI -> `supplyshield` -> **Configuration** altından `Prevent potential vulnerable images from being deployed` kutucuğunun işaretini kaldırmak.
