# 03 — 5 Uygulamalı DevSecOps Laboratuvar Senaryosu (Hands-On Labs)

Kurulum (`terraform apply` + `ansible-playbook site.yml`) tamamlandıktan sonra Harbor, Trivy, Jenkins ve Kubernetes'in nasıl birlikte çalıştığını bizzat deneyimlemek için aşağıdaki **5 uygulamalı deneyi** sırasıyla yapabilirsiniz.

Önce `vm-master` sunucusuna SSH ile bağlanın ve IP değişkenlerini yükleyin:

```bash
MASTER_IP=$(cd /home/ysf/k8s-hands-on-labs/projects/devops-capstone-project-6/terraform && terraform output -raw master_public_ip)
APP_IP=$(cd /home/ysf/k8s-hands-on-labs/projects/devops-capstone-project-6/terraform && terraform output -raw app_worker_public_ip)
ssh ysf@$MASTER_IP
```

---

## 🧪 Lab 1: Harbor Arayüzünü, Trivy CVE Raporunu ve Güvenlik Kapısını İnceleme

### Adım 1: Tarayıcıdan Harbor'a Giriş Yapın
1. Tarayıcınızda `http://harbor.<MASTER_IP>.nip.io` adresini açın.
2. Kullanıcı adı: **`admin`**, Şifre: **`AdminPassword2026!`** ile giriş yapın.
3. **Projects** altında Ansible tarafından otomatik oluşturulmuş 2 projeyi göreceksiniz:
   - `supplyshield` (Uygulama imajlarımız ve Helm chart'larımız)
   - `dockerhub-proxy` (Docker Hub Proxy Cache)
4. `supplyshield` -> **Repositories** -> `supplyshield/supplyshield-api` içine tıklayın.
5. `1.0.0` etiketli imajın yanındaki **Vulnerability** sütununda Trivy'nin çıkardığı güvenlik raporunu (veya üzerine gelerek CVE listesini) inceleyin!

### Adım 2: Terminalden Harbor API ile Trivy Raporunu Çekin
`vm-master` terminalinde şu komutu çalıştırarak aynı veriyi REST API üzerinden JSON olarak görün:

```bash
MASTER_IP=$(curl -s ifconfig.me)
curl -s -u 'admin:AdminPassword2026!' \
  "http://harbor.${MASTER_IP}.nip.io/api/v2.0/projects/supplyshield/repositories/supplyshield-api/artifacts/1.0.0?with_scan_overview=true" | jq '.scan_overview'
```

---

## 🧪 Lab 2: Jenkins'te Dinamik Kubernetes Pod Ajanı ile Build Çalıştırma

Bu deneyde Jenkins'in normalde 0 ajan podu çalıştırdığını, siz **Build Now** dediğiniz anda Kubernetes üzerinde geçici bir pod başlatıp iş bitince sildiğini canlı izleyeceğiz!

### Adım 1: Terminalde Pod İzleyiciyi (`watch`) Açın
`vm-master` üzerinde şu komutu çalıştırıp açık bırakın:

```bash
kubectl get pods -n jenkins -w
```
Şu anda sadece `jenkins-0` (`Running`) podunu göreceksiniz.

### Adım 2: Jenkins'ten Pipeline'ı Tetikleyin (veya Tam 7 Aşamalı Jenkinsfile'ı Yükleyin)
1. Tarayıcınızda `http://jenkins.<MASTER_IP>.nip.io` adresine gidin (`admin` / `AdminPassword2026!`).
2. Ana ekrandaki **`supplyshield-pipeline`** işine tıklayın.
3. İsterseniz tam 7 aşamalı (Kaniko + Trivy + Helm OCI push) pipeline'ı çalıştırmak için sol menüden **Configure** -> **Pipeline** -> **Script** kutusuna `/home/ysf/Jenkinsfile` içeriğini (`cat ~/Jenkinsfile`) yapıştırıp **Save** deyin.
4. Sol menüden **Build Now** butonuna tıklayın!

### Adım 3: Terminalde ve Console Output'ta İzleyin
- Terminaldeki `kubectl get pods -n jenkins -w` ekranında anında `supplyshield-pipeline-1-xxxx` adında yeni bir podun `Pending` -> `ContainerCreating` -> `Running` olduğunu göreceksiniz!
- Jenkins'te **#1** -> **Console Output** ekranına tıkladığınızda:
  - Pytest birim testlerinin geçtiğini,
  - Bandit SAST taramasının temiz çıktığını,
  - Kaniko'nun yeni imajı (`1.0.1`) derleyip Harbor'a gönderdiğini,
  - Helm Chart'ın `oci://harbor.../supplyshield/charts` altına yüklendiğini,
  - Canlı uygulamanın (`namespace: app`) yeni sürüme güncellendiğini göreceksiniz!
- Derleme bittiği saniyede terminaldeki geçici pod `Completed` -> `Terminating` olup silinecektir!

---

## 🧪 Lab 3: Harbor Proxy Cache (`dockerhub-proxy`) ile Docker Hub Rate-Limit Aşma

Docker Hub'dan doğrudan imaj çekmek yerine Harbor'ın **Proxy Cache** özelliğini test edelim:

```bash
MASTER_IP=$(curl -s ifconfig.me)

# Harbor'daki 'dockerhub-proxy' projesi üzerinden busybox:1.36 imajını kullanan bir test podu başlatalım:
kubectl run proxy-cache-test \
  --image="harbor.${MASTER_IP}.nip.io/dockerhub-proxy/library/busybox:1.36" \
  --restart=Never \
  --command -- sh -c "echo 'Harbor Proxy Cache uzerinden basariyla calisti!' && sleep 5"

# Podun durumunu ve logunu kontrol edelim:
kubectl wait --for=condition=Ready pod/proxy-cache-test --timeout=60s || true
kubectl logs proxy-cache-test
kubectl delete pod proxy-cache-test
```

Şimdi Harbor Web Arayüzünde **`dockerhub-proxy`** -> **Repositories** sekmesine girin: `library/busybox` imajının otomatik olarak Harbor'a indirildiğini ve önbelleğe alındığını göreceksiniz! Artık kümedeki diğer yüzlerce pod bu imajı Docker Hub kotası harcamadan doğrudan yerel Harbor'dan çekebilir.

---

## 🧪 Lab 4: Helm Chart'larını OCI Artifact Olarak Harbor'da Yönetme

Harbor'ın sadece Docker imajı değil, Helm Chart deposu olarak nasıl çalıştığını bizzat deneyin:

```bash
MASTER_IP=$(curl -s ifconfig.me)

# 1) Helm ile Harbor OCI kayıt defterine giriş yap:
echo "AdminPassword2026!" | helm registry login "harbor.${MASTER_IP}.nip.io" \
  --username admin --password-stdin --plain-http

# 2) Uygulama Helm chart'ını 1.2.0 versiyonuyla paketle:
helm package ~/app/chart --version 1.2.0 --app-version 1.2.0 -d /tmp

# 3) Paketi OCI protokolüyle Harbor'a gönder:
helm push /tmp/supplyshield-1.2.0.tgz "oci://harbor.${MASTER_IP}.nip.io/supplyshield/charts" --plain-http

# 4) Harbor API veya UI üzerinden yüklenen Helm Chart artifact'ini doğrula:
curl -s -u 'admin:AdminPassword2026!' \
  "http://harbor.${MASTER_IP}.nip.io/api/v2.0/projects/supplyshield/repositories/charts%2Fsupplyshield/artifacts" | jq '.[0] | {type, tags: .tags[].name}'
```

Harbor arayüzünde `supplyshield` -> **Repositories** -> `supplyshield/charts/supplyshield` altında üzerinde **Helm logosu** bulunan paketinizi görebilirsiniz!

---

## 🧪 Lab 5: Harbor "Vulnerability Prevention" (Zafiyetli İmaj Engelleme) Testi

Gerçek bir SecOps senaryosu: İçinde `CRITICAL` veya `HIGH` güvenlik açığı bulunan imajların Kubernetes'te çalıştırılmasını Harbor üzerinden yasaklayalım!

### Adım 1: Harbor'da Güvenlik Kapısını Aktif Edin
İsterseniz Harbor UI'dan (`supplyshield` -> **Configuration** -> **Prevent potential vulnerable images from being deployed** kutucuğunu işaretleyip **Severity: High** veya **Critical** seçip Save deyin), isterseniz tek komutla API üzerinden açın:

```bash
MASTER_IP=$(curl -s ifconfig.me)

# 'supplyshield' projesinde CRITICAL veya HIGH açık içeren imajların çekilmesini yasakla:
curl -i -u 'admin:AdminPassword2026!' -X PUT \
  "http://harbor.${MASTER_IP}.nip.io/api/v2.0/projects/supplyshield" \
  -H "Content-Type: application/json" \
  -d '{
    "metadata": {
      "public": "true",
      "auto_scan": "true",
      "prevent_vul": "true",
      "severity": "high"
    }
  }'
```

Artık Trivy taramasında `High` veya `Critical` CVE tespit edilen hiçbir imaj (istisnaya / CVE Allowlist'e eklenmediği sürece) üretim ortamına çekilemez! Testiniz bittikten sonra `"prevent_vul": "false"` yaparak tekrar esnek moda dönebilirsiniz.
