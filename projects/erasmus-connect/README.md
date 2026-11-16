# Erasmus Connect — Sıfırdan DevOps Uygulama ve Lab Rehberi (Helm + Calico + Azure AKS)

Bu proje, **Erasmus Connect** uygulamasını (**Next.js** frontend, **Express** backend, **Redis** önbellek/oturum katmanı, harici **MongoDB Atlas** ve **Supabase**) sıfır kopyala-yapıştır ile, her satırın mühendislik gerekçesini anlayarak **Kubernetes (Helm)** ve **Azure AKS (Terraform)** üzerine taşıman için hazırlanmış bilet tabanlı (ticket-driven) bir uygulama labıdır.

> [!IMPORTANT]
> **Lab Kuralı:** Bu repodaki [helm/erasmus-connect/](file:///home/ysf/k8s-hands-on-labs/projects/erasmus-connect/helm/erasmus-connect/Chart.yaml) ve [terraform/](file:///home/ysf/k8s-hands-on-labs/projects/erasmus-connect/terraform/main.tf) dosyaları **bilerek eksik (`# TODO`)** bırakılmıştır. Amacın kodu AI'a yazdırmak değil; kendi terminalindeki `kubectl explain`, `helm template`, `editor.networkpolicy.io` ve `registry.terraform.io` kaynaklarını okuyarak her bileti tek tek çözmektir.

---

## Mimari Genel Bakış

```text
  [ Kullanıcı Tarayıcısı ]
             │
             ▼
   [ NGINX Ingress Controller ]  ──( / )──────► [ Next.js Service ] ──► [ Next.js Pod (:3000) ]
             │                                                                    │
             └──( /api )─────────────────────► [ Express Service ] ◄──(SSR iç çağrı)
                                                      │
                                                      ▼
                                             [ Express Pod (:PORT) ]
                                                │      │       │
                          (Calico NetPol) ──────┘      │       └──────► [ Harici: MongoDB Atlas & Supabase ]
                                  │                    │
                                  ▼                    ▼
                     [ Redis Headless Svc ]    [ Secret: erasmus-app-secrets ]
                                  │
                                  ▼
                       [ Redis StatefulSet (:6379) ]
```

---

## Bölüm 0: Sıfırdan YAML ve Terraform Okuma/Yazma Rehberi

Bugüne kadar YAML veya Terraform'u sıfırdan yazmadıysan korkmana gerek yok. Girintileri ve tire (`-`) işaretlerini ezberlemek yerine şu **4 mekanik kuralı** kullanacaksın:

### 1. `kubectl explain` Çıktısını YAML'a Çevirme Kuralı

Terminalde `kubectl explain <yol>` çalıştırdığında `FIELDS:` altında alan tiplerini görürsün. Her tip YAML'da tek bir anlama gelir:

| `kubectl explain` Çıktısı | YAML'da Karşılığı | Örnek Mantık |
| :--- | :--- | :--- |
| `alanAdi <Object>` | Alt satıra geç, **2 boşluk** içeriden yaz | `resources:` yazıp alt satıra 2 boşlukla `requests:` yazmak |
| `alanAdi <[]Object>` | Alt satıra geç, **2 boşluk + `- ` (tire)** ile liste aç | `ports:` altında `- containerPort: ...` veya `from:` altında `- podSelector:` |
| `alanAdi <string>` / `<integer>` | Aynı satıra değer yaz | `type: ClusterIP` veya `port: 6379` |
| `alanAdi <map[string]string>` | Alt satıra **2 boşluk** içeriden `anahtar: değer` yaz | `matchLabels:` altında `app: erasmus-express` |
| `-required-` etiketi | Bu alan **zorunludur**, yazmazsan Kubernetes reddeder | `selector` veya `serviceName` gibi |

> [!TIP]
> **Tire (`-`) Ne Zaman Konur?**
> Sadece `kubectl explain` çıktısında köşeli parantez `[]` gördüğünde (`[]Object` veya `[]string`)! Köşeli parantez yoksa ASLA tire koyma, sadece 2 boşluk girinti bırak.

### 2. Helm Şablon Söz Dizimi (`{{ ... }}`)

Helm, `templates/` içindeki dosyaları alır ve `values.yaml` içindeki değerleri `{{ .Values.<yol> }}` yerlerine yerleştirir:
- `values.yaml` içinde `express:` -> `containerPort: 8080` yazarsan, şablonda `{{ .Values.express.containerPort }}` yazdığında Helm bunu `8080` olarak üretir.
- Eğer bir bloğu (`resources` gibi) olduğu gibi aktarmak istiyorsan `{{- toYaml .Values.express.resources | nindent 10 }}` kalıbı kullanılır (`nindent 10`, yeni satıra geçip 10 boşluk girinti verir).
- **Altın Kural:** Değişiklik yaptıktan sonra kümeye uygulamadan önce mutlaka `helm template` çalıştırıp üretilen ham YAML'ın girintilerini gözünle kontrol et!

### 3. Terraform HCL Söz Dizimi

Terraform dosyaları (`.tf`) `blok_türü "kaynak_türü" "yerel_isim" { ... }` şeklinde yazılır.
- `registry.terraform.io` dokümantasyonunda **Argument Reference** başlığı altındaki her madde `anahtar = değer` veya `alt_blok { ... }` şeklindedir.
- Bir başka kaynağın çıktısını referans vermek için `<kaynak_türü>.<yerel_isim>.<özellik>` yazılır (ör. `azurerm_resource_group.erasmus.name`).

---

## Faz 1: Helm İskeleti ve Temel İş Yükleri

Bu fazda yerel kümeni kuracak, Express, Next.js ve Redis iş yüklerini (Deployment, StatefulSet, Service) ayağa kaldıracaksın.

---

### Bilet 1: Yerel Calico Kümesini Hazırlama ve İlk Sıfır-AI İskelet Denemesi

**a) Görev Tanımı:**
- Kendi bilgisayarında NetworkPolicy destekleyen bir yerel Kubernetes kümesi (Calico CNI ile Minikube veya k3d) ayağa kaldır.
- `helm` aracının yerel iskeletimizi okuyabildiğini doğrula ve `--dry-run=client -o yaml` ile ham Kubernetes manifestosu üretme alışkanlığını test et.
- Bu aşamada `projects/erasmus-connect/helm/erasmus-connect/` içindeki `# TODO` dosyalarını incele, henüz eksikler olduğu için neden hata/boşluk çıktığını gözlemle.

**b) İpucu ve Referans:**
- Minikube ile Calico başlatma: `minikube start --network-plugin=cni --cni=calico` (veya `k3d` kullanıyorsan Calico CNI kurulumlu küme).
- Ingress addon kontrolü (Minikube): `minikube addons enable ingress`
- Sıfırdan YAML üretme pratiği (örnek referans komutu):
  `kubectl create deployment deneme --image=nginx --port=80 --dry-run=client -o yaml`
- Helm ilk durum kontrolü:
  `helm lint ./helm/erasmus-connect`

**c) Çözüm Kanıtı:**
```bash
kubectl get nodes -o wide
kubectl get pods -n kube-system | grep -E "calico|coredns"
kubectl get pods -n ingress-nginx
```
- Node durumu `Ready`, `calico-node` / `calico-kube-controllers` podları `Running` ve `ingress-nginx-controller` podu `Running` olmalıdır.

---

### Bilet 2: Express Backend (`values.yaml` ve `express-deployment.yaml`)

**a) Görev Tanımı:**
- [values.yaml](file:///home/ysf/k8s-hands-on-labs/projects/erasmus-connect/helm/erasmus-connect/values.yaml) içinde `express.image` (`repository`, `tag`) ve `express.containerPort` değerlerini doldur.
- [express-deployment.yaml](file:///home/ysf/k8s-hands-on-labs/projects/erasmus-connect/helm/erasmus-connect/templates/express-deployment.yaml) içindeki `[Bilet 2]` `# TODO` satırını kaldırıp `ports:` bloğunu yaz.
- **Kritik Mühendislik Kontrolü:** Express kodun içinde `app.listen(PORT, '127.0.0.1')` yazıyorsa Kubernetes Service trafiği pod içine **ulaşamaz**. Uygulamanın `0.0.0.0` (tüm arayüzler) dinlediğinden emin ol.

**b) İpucu ve Referans:**
- Terminalde çalıştır:
  `kubectl explain deployment.spec.template.spec.containers.ports`
- Çıktıda `ports` alanının `<[]Object>` olduğunu gör (`- containerPort: ...` gerektirir).
- Zorunlu ve opsiyonel alt alanları gör: `containerPort`, `name`, `protocol`.

<details>
<summary>🆘 Takılırsan Aç (Reveal): `ports` Yapısal Yazım Mantığı</summary>

1. `express-deployment.yaml` içinde `imagePullPolicy:` satırıyla aynı hizada (10 boşluk girinti) `ports:` yaz.
2. Alt satıra 12 boşluk girintiyle `- name: http` yaz (çünkü `ports` bir `[]Object` listesidir, bu yüzden `-` konur).
3. `-` işaretinin `n` harfiyle aynı hizada (14 boşluk) `containerPort: {{ .Values.express.containerPort }}` ve `protocol: TCP` ekle.
4. `values.yaml` içinde `containerPort: <UYGULAMANIN_PORTU>` (ör. `8080` veya `5000`) ve `image.repository` / `image.tag` değerlerini doldurmayı unutma.

</details>

**c) Çözüm Kanıtı:**
```bash
helm template erasmus ./helm/erasmus-connect -s templates/express-deployment.yaml
```
- Çıktıda `containers:` altında `ports:` ve senin belirlediğin `containerPort` sayısı hatasız YAML olarak görünmeli.

---

### Bilet 3: Express Service (`express-service.yaml`) — `port` vs `targetPort` Eşleşmesi

**a) Görev Tanımı:**
- [values.yaml](file:///home/ysf/k8s-hands-on-labs/projects/erasmus-connect/helm/erasmus-connect/values.yaml) içindeki `express.service` altını (`type`, `port`) doldur.
- [express-service.yaml](file:///home/ysf/k8s-hands-on-labs/projects/erasmus-connect/helm/erasmus-connect/templates/express-service.yaml) içindeki tüm `[Bilet 3]` `# TODO` bloklarını (`type`, `selector`, `ports`) yaz.
- **Neden Önemli?** `port`, Service'in küme içinde sunduğu porttur (ör. `80` veya `8080`); `targetPort` ise trafiği podun içindeki gerçek `containerPort`'a yönlendirir. Bu ikisi uyuşmazsa `Connection Refused` alırsın!

**b) İpucu ve Referans:**
- Terminalde çalıştır:
  `kubectl explain service.spec`
  `kubectl explain service.spec.ports`
- Dikkat et: `selector` bir `<map[string]string>` (tire YOK), `ports` ise `<[]Object>` (tire VAR).
- `selector` değeri, `express-deployment.yaml` içindeki `template.metadata.labels` ile birebir eşleşmelidir (`app: erasmus-express`).

<details>
<summary>🆘 Takılırsan Aç (Reveal): `Service` Yazım İskeleti</summary>

- `spec:` altında 2 boşlukla:
  - `type: {{ .Values.express.service.type }}` (values.yaml'da `ClusterIP`)
  - `selector:` altında 4 boşlukla `app: erasmus-express`
  - `ports:` altında `- port: {{ .Values.express.service.port }}`
  - Aynı liste elemanı altında `targetPort: {{ .Values.express.containerPort }}` (ve `protocol: TCP`, `name: http`)

</details>

**c) Çözüm Kanıtı:**
```bash
helm template erasmus ./helm/erasmus-connect -s templates/express-service.yaml
```
- Render edilen çıktıdaki `targetPort` değerinin `express-deployment.yaml` çıktıdaki `containerPort` ile birebir aynı olduğunu gözünle doğrula.

---

### Bilet 4: Next.js Frontend (`nextjs-deployment.yaml` & `nextjs-service.yaml`)

**a) Görev Tanımı:**
- [values.yaml](file:///home/ysf/k8s-hands-on-labs/projects/erasmus-connect/helm/erasmus-connect/values.yaml) içindeki `nextjs` alanlarını (image, service, containerPort) doldur.
- [nextjs-deployment.yaml](file:///home/ysf/k8s-hands-on-labs/projects/erasmus-connect/helm/erasmus-connect/templates/nextjs-deployment.yaml) içine `ports:` ve `env:` bloklarını (`[Bilet 4]`) ekle (`HOSTNAME=0.0.0.0`, `INTERNAL_API_URL` için Express Service DNS adı `http://erasmus-express-svc:<PORT>`).
- [nextjs-service.yaml](file:///home/ysf/k8s-hands-on-labs/projects/erasmus-connect/helm/erasmus-connect/templates/nextjs-service.yaml) içindeki `[Bilet 4]` `# TODO` kısımlarını doldur.

**b) İpucu ve Referans:**
- Terminalde çalıştır:
  `kubectl explain deployment.spec.template.spec.containers.env`
- `env` bir `<[]Object>` listesidir (`- name: ...` ve `value: "..."` alır).
- Next.js SSR (Server-Side Rendering) istekleri tarayıcıdan değil Next.js podunun içinden çıkar; bu yüzden dış domain yerine cluster-internal Service DNS'ini (`http://erasmus-express-svc`) kullanması gerekir. Tarayıcıdan gelen istekler ise Bilet 9'daki Ingress `/api` yolunu kullanır.

<details>
<summary>🆘 Takılırsan Aç (Reveal): `env` Bloğu Yazım Kalıbı</summary>

`containers:` altındaki bir container içinde `env:` şu kalıpla yazılır:
- `env:` (10 boşluk)
- `  - name: <DEĞİŞKEN_ADI>` (12 boşluk + tire)
- `    value: "<DEĞER>"` (14 boşluk)
Dikkat: Sayı veya boolean bile olsa Kubernetes `env.value` alanı `<string>` tipindedir; tırnak (`"..."`) içinde yaz!

</details>

**c) Çözüm Kanıtı:**
```bash
helm template erasmus ./helm/erasmus-connect -s templates/nextjs-deployment.yaml
helm template erasmus ./helm/erasmus-connect -s templates/nextjs-service.yaml
```

---

### Bilet 5: Redis StatefulSet ve Headless Service (`clusterIP: None`)

**a) Görev Tanımı:**
- [values.yaml](file:///home/ysf/k8s-hands-on-labs/projects/erasmus-connect/helm/erasmus-connect/values.yaml) içinde `redis` portu (`6379`) ve PVC boyutunu (ör. `1Gi`) tanımla.
- [redis-service.yaml](file:///home/ysf/k8s-hands-on-labs/projects/erasmus-connect/helm/erasmus-connect/templates/redis-service.yaml) içinde bu Service'i **Headless Service** yapacak kritik `clusterIP` ayarını, `selector` ve `ports` alanlarını yaz.
- [redis-statefulset.yaml](file:///home/ysf/k8s-hands-on-labs/projects/erasmus-connect/helm/erasmus-connect/templates/redis-statefulset.yaml) içinde `serviceName`, `ports`, `volumeMounts` (`/data`) ve `volumeClaimTemplates` alanlarını tamamla.

**b) İpucu ve Referans:**
- Terminalde çalıştır:
  `kubectl explain statefulset.spec`
  `kubectl explain statefulset.spec.volumeClaimTemplates`
  `kubectl explain service.spec.clusterIP`
- **Neden `clusterIP: None`?** StatefulSet podları kararlı DNS kimliklerine (`erasmus-redis-0.erasmus-redis-headless.<namespace>.svc.cluster.local`) ihtiyaç duyar. Normal ClusterIP yerine `clusterIP: None` verdiğinde kube-proxy sanal IP dağıtmaz; CoreDNS doğrudan pod IP'sini döner.
- `serviceName` alanı `redis-service.yaml` içindeki `metadata.name` (`erasmus-redis-headless`) ile birebir aynı olmalıdır.

<details>
<summary>🆘 Takılırsan Aç (Reveal): `volumeMounts` ve `volumeClaimTemplates` Bağlantısı</summary>

1. `container` altında:
   - `volumeMounts:` (`[]Object`) -> `- name: redis-data` ve `mountPath: /data`
2. `statefulset.spec:` altında (`template:` ile aynı hizada):
   - `volumeClaimTemplates:` (`[]Object`) -> `- metadata:` -> `name: redis-data` (yukarıdaki `volumeMounts.name` ile birebir aynı!)
   - Aynı liste elemanı altında `spec:` -> `accessModes: ["ReadWriteOnce"]` ve `resources:` -> `requests:` -> `storage: <BOYUT>`

</details>

**c) Çözüm Kanıtı:**
```bash
helm template erasmus ./helm/erasmus-connect -s templates/redis-service.yaml
helm template erasmus ./helm/erasmus-connect -s templates/redis-statefulset.yaml
```
- Kümeye ilk kurulumu test etmek istersen (`helm install --dry-run`):
  `helm lint ./helm/erasmus-connect`

---

## Faz 2: Secret Yönetimi, Kaynak Sınırları ve Probe'lar

Bu fazda hassas bağlantı dizelerini açık metinden çıkaracak, podların kaynak tüketimini sınırlayacak ve Kubernetes'in kendi kendine iyileşme (self-healing) mekanizmalarını yazacaksın.

---

### Bilet 6: `secrets.yaml` ve `secretKeyRef` — Veritabanı Anahtarlarını Koruma

**a) Görev Tanımı:**
- [values.yaml](file:///home/ysf/k8s-hands-on-labs/projects/erasmus-connect/helm/erasmus-connect/values.yaml) içinde `secrets:` altına `MONGODB_URI`, `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `REDIS_URL` ve `JWT_SECRET` için boş anahtar şemasını tanımla.
- [secrets.yaml](file:///home/ysf/k8s-hands-on-labs/projects/erasmus-connect/helm/erasmus-connect/templates/secrets.yaml) dosyasını tamamla (`type: Opaque` ve `stringData:` veya `b64enc` ile `data:`).
- [express-deployment.yaml](file:///home/ysf/k8s-hands-on-labs/projects/erasmus-connect/helm/erasmus-connect/templates/express-deployment.yaml) içindeki `[Bilet 6]` `# TODO` bölümünde ortam değişkenlerini düz `value:` olarak değil `valueFrom.secretKeyRef` ile bağla!

**b) İpucu ve Referans:**
- Terminalde çalıştır:
  `kubectl explain secret`
  `kubectl explain deployment.spec.template.spec.containers.env.valueFrom.secretKeyRef`
- `secretKeyRef` iki alan ister: `name` (`erasmus-app-secrets`) ve `key` (Secret içindeki anahtar adı, ör. `MONGODB_URI`).
- **Güvenlik Kuralı:** Gerçek MongoDB/Supabase şifrelerini `values.yaml` dosyasına yazıp Git'e atma! Yerel testte `.gitignore` içindeki `values-secret.yaml` dosyasını oluşturup `-f values-secret.yaml` ile ver.

<details>
<summary>🆘 Takılırsan Aç (Reveal): `secretKeyRef` Yazım Kalıbı</summary>

`env:` listesi içinde bir gizli değişkeni çekmek için `value:` yerine şunu yaz:
- `- name: MONGODB_URI`
- `  valueFrom:`
- `    secretKeyRef:`
- `      name: <SECRET_METADATA_NAME>`
- `      key: <SECRET_ICINDEKI_ANAHTAR>`

</details>

**c) Çözüm Kanıtı:**
```bash
helm template erasmus ./helm/erasmus-connect \
  --set secrets.MONGODB_URI="mongodb+srv://test" \
  --set secrets.REDIS_URL="redis://erasmus-redis-headless:6379" \
  -s templates/secrets.yaml -s templates/express-deployment.yaml
```
- `express-deployment.yaml` çıktısında hiçbir gerçek şifrenin/URI'nin açıkça geçmediğini, sadece `secretKeyRef` referanslarının göründüğünü doğrula.

---

### Bilet 7: Kaynak Sınırları (`resources`: `requests` ve `limits`)

**a) Görev Tanımı:**
- [values.yaml](file:///home/ysf/k8s-hands-on-labs/projects/erasmus-connect/helm/erasmus-connect/values.yaml) içinde `express`, `nextjs` ve `redis` için `resources:` altında `requests` ve `limits` değerlerini belirle.
- [express-deployment.yaml](file:///home/ysf/k8s-hands-on-labs/projects/erasmus-connect/helm/erasmus-connect/templates/express-deployment.yaml), [nextjs-deployment.yaml](file:///home/ysf/k8s-hands-on-labs/projects/erasmus-connect/helm/erasmus-connect/templates/nextjs-deployment.yaml) ve [redis-statefulset.yaml](file:///home/ysf/k8s-hands-on-labs/projects/erasmus-connect/helm/erasmus-connect/templates/redis-statefulset.yaml) içindeki `[Bilet 7]` `# TODO` kısımlarına `resources:` bloğunu ekle.
- **Kısıt Hesabı:** Faz 4'te Azure'da `Standard_B2s` (2 vCPU, 4 GB RAM) tek node kullanacaksın. Sistem podları (`kube-system`, `calico`, `ingress-nginx`) da bu RAM/CPU'dan yiyecektir! Toplam `requests` değerlerin tek bir node'a sığmayacak kadar büyük olursa podlar `Pending` kalır.

**b) İpucu ve Referans:**
- Terminalde çalıştır:
  `kubectl explain pod.spec.containers.resources`
- `cpu` birimleri: `100m` = 0.1 vCPU, `500m` = 0.5 vCPU.
- `memory` birimleri: `128Mi`, `256Mi`, `512Mi` (`Mi` Mebibyte, `M` Megabyte'tan farklıdır; standart `Mi` kullan).
- Node.js (Next.js / Express) uygulamaları başlangıçta anlık RAM sıçraması yapabilir; `limits.memory` değerini çok düşük (ör. 64Mi) verirsen `OOMKilled` (Exit Code 137) alırsın.

<details>
<summary>🆘 Takılırsan Aç (Reveal): `resources` Helm Şablon Bağlantısı</summary>

`values.yaml` içinde her servis için `requests:` (`cpu`, `memory`) ve `limits:` (`cpu`, `memory`) tanımladıktan sonra, şablon dosyalarında her satırı tek tek yazmak yerine container hizasında şu Helm yardımcısını kullanabilirsin:
`resources:`
`  {{- toYaml .Values.<servis>.resources | nindent <GIRINTI_SAYISI> }}`
(`express-deployment` ve `nextjs-deployment` için container içi 10 boşluk olduğundan `resources:` 10 boşluk, altındaki içerik `nindent 12` alır.)

</details>

**c) Çözüm Kanıtı:**
```bash
helm template erasmus ./helm/erasmus-connect | grep -A 8 "resources:"
```
- Çıktıda 3 pod için de `requests` ve `limits` değerlerinin düzgün girintilendiğini doğrula; toplam `cpu` ve `memory` request'lerinin tek bir `Standard_B2s` node kapasitesini aşmadığını hesapla.

---

### Bilet 8: Sağlık Kontrolleri (`readinessProbe` & `livenessProbe`)

**a) Görev Tanımı:**
- [values.yaml](file:///home/ysf/k8s-hands-on-labs/projects/erasmus-connect/helm/erasmus-connect/values.yaml) içinde `express.healthPath` alanını doldur (uygulaman `/health` veya `/api/health` dönmüyorsa Express koduna 200 OK dönen bir endpoint ekle!).
- [express-deployment.yaml](file:///home/ysf/k8s-hands-on-labs/projects/erasmus-connect/helm/erasmus-connect/templates/express-deployment.yaml), [nextjs-deployment.yaml](file:///home/ysf/k8s-hands-on-labs/projects/erasmus-connect/helm/erasmus-connect/templates/nextjs-deployment.yaml) ve [redis-statefulset.yaml](file:///home/ysf/k8s-hands-on-labs/projects/erasmus-connect/helm/erasmus-connect/templates/redis-statefulset.yaml) içindeki `[Bilet 8]` `# TODO` kısımlarını doldur.
- **Karar:** `readinessProbe` başarısız olursa Service bu poda trafik göndermeyi keser (restart etmez). `livenessProbe` başarısız olursa Kubelet container'ı öldürüp yeniden başlatır. Next.js/Express geç açılıyorsa `initialDelaySeconds` değerini kısa tutarsan CrashLoopBackOff yaşarsın!

**b) İpucu ve Referans:**
- Terminalde çalıştır:
  `kubectl explain pod.spec.containers.readinessProbe`
  `kubectl explain pod.spec.containers.readinessProbe.httpGet`
  `kubectl explain pod.spec.containers.livenessProbe.exec`
- Express & Next.js için: `httpGet` (`path`, `port`).
- Redis için: `exec` (`command: ["redis-cli", "ping"]`) veya `tcpSocket` (`port: 6379`). (`redis-cli ping` sadece portun açık olmasını değil, Redis motorunun `PONG` yanıtı verebildiğini de doğrular!)

<details>
<summary>🆘 Takılırsan Aç (Reveal): `httpGet` ve `exec` Probe Yapısı</summary>

`httpGet` yapısı (Express / Next.js):
- `readinessProbe:` (container alanlarıyla aynı hizada)
- `  httpGet:`
- `    path: <ENDPOINT_YOLU>`
- `    port: <CONTAINER_PORT>`
- `  initialDelaySeconds: <SANIYE>`
- `  periodSeconds: <SANIYE>`

`exec` yapısı (Redis):
- `readinessProbe:`
- `  exec:`
- `    command: ["redis-cli", "ping"]`
- `  initialDelaySeconds: <SANIYE>`
- `  periodSeconds: <SANIYE>`

</details>

**c) Çözüm Kanıtı:**
Kümeye yüklediğinde tüm podlar `1/1 Running` olmalı ve `kubectl describe pod <pod-adi>` çıktısında `Readiness` / `Liveness` hatası olmamalıdır:
```bash
helm upgrade --install erasmus ./helm/erasmus-connect -f values-secret.yaml
kubectl get pods -w
kubectl get endpoints
```
- `kubectl get endpoints` çıktısında Express, Next.js ve Redis için IP:Port eşleşmeleri `<none>` DEĞİL, gerçek Pod IP'leri olarak görünmelidir.

---

## Faz 3: NGINX Ingress ve Post-DNAT Calico NetworkPolicy

Bu faz projenin ağ ve güvenlik omurgasıdır. Özellikle Calico altında **Post-DNAT** davranışını pratik edeceksin.

---

### Bilet 9: NGINX Ingress ile Path Routing (`ingress.yaml`)

**a) Görev Tanımı:**
- [values.yaml](file:///home/ysf/k8s-hands-on-labs/projects/erasmus-connect/helm/erasmus-connect/values.yaml) içinde `ingress.className` (`nginx`) ve `ingress.host` (ör. `erasmus.local`) alanlarını doldur.
- [ingress.yaml](file:///home/ysf/k8s-hands-on-labs/projects/erasmus-connect/helm/erasmus-connect/templates/ingress.yaml) dosyasındaki `[Bilet 9]` `# TODO` kısımlarını tamamla:
  - `/api` yolu -> `erasmus-express-svc`
  - `/` yolu -> `erasmus-nextjs-svc`
- **Mimari Soru:** Express uygulaman route'ları `/api/auth`, `/api/users` şeklinde tanımlıyorsa `rewrite-target: /$2` annotation'ı **KOYMAMALISIN** (yoksa `/api` kırpılır ve Express `404` döner). Eğer Express route'ların `/auth`, `/users` ise o zaman rewrite annotation'ı gerekir. Kendi backend koduna göre karar ver!

**b) İpucu ve Referans:**
- Görsel/terminal referansları:
  `kubectl explain ingress.spec`
  `kubectl explain ingress.spec.rules.http.paths`
  `kubectl explain ingress.spec.rules.http.paths.backend.service`
- `backend.service.port.number` alanına Deployment `containerPort`'unu değil, **Service'in sunduğu `port` numarasını** yazmalısın!

<details>
<summary>🆘 Takılırsan Aç (Reveal): Ingress `rules` ve `paths` Hiyerarşisi</summary>

`spec:` altında:
- `ingressClassName: <SINIF_ADI>`
- `rules:` (`[]Object`)
- `  - host: <DOMAIN>`
- `    http:`
- `      paths:` (`[]Object`)
- `        - path: /api`
- `          pathType: Prefix`
- `          backend:`
- `            service:`
- `              name: erasmus-express-svc`
- `              port:`
- `                number: <EXPRESS_SVC_PORT>`
(İkinci `- path: /` maddesini de aynı şekilde `erasmus-nextjs-svc` için altına ekle.)

</details>

**c) Çözüm Kanıtı:**
Yerel kümede Ingress Controller IP'sini (`minikube ip` veya `kubectl get svc -n ingress-nginx`) kullanarak `Host` header'ı ile test et:
```bash
kubectl get ingress
curl -i -H "Host: erasmus.local" http://<INGRESS_IP>/
curl -i -H "Host: erasmus.local" http://<INGRESS_IP>/api/health
```
- `/` isteği Next.js HTML/200 dönmeli, `/api/health` isteği Express JSON/200 dönmelidir.

---

### Bilet 10: Redis Zero-Trust İzolasyonu (`networkpolicy-redis.yaml`)

**a) Görev Tanımı:**
- [networkpolicy-redis.yaml](file:///home/ysf/k8s-hands-on-labs/projects/erasmus-connect/helm/erasmus-connect/templates/networkpolicy-redis.yaml) dosyasındaki `[Bilet 10]` `# TODO` kısımlarını doldur.
- Kural amacı: Redis poduna (`app: erasmus-redis`) **SADECE** Express podları (`app: erasmus-express`) ve **SADECE** TCP `6379` portundan bağlanabilsin. Next.js podu veya kümedeki başka herhangi bir pod Redis'e erişemesin!

**b) İpucu ve Referans:**
- Görsel araç: Tarayıcıda **`editor.networkpolicy.io`** adresini açıp seçicileri görsel olarak dene ve YAML yapısını incele.
- Terminalde çalıştır:
  `kubectl explain netpol.spec`
  `kubectl explain netpol.spec.ingress`
  `kubectl explain netpol.spec.ingress.from`
- **Sınav Tuzağı (AND vs OR Mantığı):**
  - `from:` ve `ports:` aynı `-` liste elemanı altında yazılırsa: `(Express POD'undan VE 6379 portuna)` demektir (İstediğimiz budur!).
  - Eğer ayrı `- from:` ve `- ports:` maddeleri yaparsan: `(Express'ten TÜM portlara VEYA HERKESTEN 6379 portuna)` anlamına gelir ve **güvenlik açığı** oluşur!

<details>
<summary>🆘 Takılırsan Aç (Reveal): `NetworkPolicy` AND Kuralı Yapısı</summary>

`spec:` altında:
- `podSelector:` -> `matchLabels:` -> `app: erasmus-redis`
- `policyTypes:` -> `- Ingress`
- `ingress:` (`[]Object`)
- `  - from:` (tek bir kural maddesi başlat)
- `      - podSelector:`
- `          matchLabels:`
- `            app: erasmus-express`
- `    ports:` (`from` ile aynı girintide -> AND mantığı!)
- `      - protocol: TCP`
- `        port: 6379`

</details>

**c) Çözüm Kanıtı:**
Policy uygulandıktan sonra 2 farklı poddan Redis'e bağlantı testi yap (biri başarılı, diğeri timeout olmalı!):
```bash
# 1. Next.js podundan Redis'e erişim ENGELLENMELİ (timeout):
kubectl exec deploy/erasmus-erasmus-connect-nextjs -- sh -c "nc -zv -w 3 erasmus-redis-headless 6379"

# 2. Express podundan Redis'e erişim BAŞARILI OLMALI:
kubectl exec deploy/erasmus-erasmus-connect-express -- sh -c "nc -zv -w 3 erasmus-redis-headless 6379"
```
*(Eğer image içinde `nc` yoksa geçici `busybox` test poduna uygun `app: erasmus-express` vs `app: test-intruder` etiketi vererek `kubectl run --labels=...` ile test edebilirsin.)*

---

### Bilet 11: Post-DNAT Calico NetworkPolicy (`networkpolicy-express.yaml`)

**a) Görev Tanımı:**
- [networkpolicy-express.yaml](file:///home/ysf/k8s-hands-on-labs/projects/erasmus-connect/helm/erasmus-connect/templates/networkpolicy-express.yaml) dosyasındaki `[Bilet 11]` `# TODO` kısımlarını doldur.
- **Post-DNAT Gerçeğini Uygula:**
  1. Dışarıdan gelen trafik önce NGINX Ingress Controller poduna, oradan `erasmus-express-svc` Service'ine (ör. port `80`) gider. `kube-proxy` (veya eBPF) paketi Express poduna iletmeden **önce DNAT** yapar; yani hedef IP pod IP'sine, hedef port ise Express'in **`containerPort`** değerine dönüşür.
  2. Bu yüzden Calico NetworkPolicy pod seviyesinde değerlendirme yaparken Service portunu (`80`) DEĞİL, **`containerPort`** değerini görür! `ports:` kısmına Express'in `containerPort` değerini yazmalısın.
  3. Ayrıca NGINX Ingress Controller genellikle `ingress-nginx` namespace'inde çalışır! Aynı namespace dışındaki bir poddan gelen trafiğe izin vermek için `from:` altında tek başına `podSelector` yazarsan **çalışmaz** (aynı namespace'te arar); **`namespaceSelector`** + **`podSelector`** birlikte kullanmalısın!

**b) İpucu ve Referans:**
- İlk olarak Ingress Controller'ın hangi namespace'te ve hangi etiketlerle çalıştığını kendi kümeden öğren:
  `kubectl get pods -A --show-labels | grep ingress`
  `kubectl get ns ingress-nginx --show-labels`
- Terminalde çalıştır:
  `kubectl explain netpol.spec.ingress.from.namespaceSelector`
- **Kritik Girinti Tuzağı (`namespaceSelector` + `podSelector`):**
  - Aynı `-` altında `namespaceSelector:` ve `podSelector:` yazarsan = **"O namespace'teki O pod"** (AND).
  - Ayrı `- namespaceSelector:` ve `- podSelector:` yazarsan = **"O namespace'teki HERKES veya bu namespace'teki o pod"** (OR - aşırı izin!).
- Next.js SSR podundan gelen iç çağrılar için ayrı bir `- podSelector:` kaynağı daha `from:` listesine eklemelisin.

<details>
<summary>🆘 Takılırsan Aç (Reveal): Cross-Namespace `from` Yazımı</summary>

`ingress:` altındaki tek kuralda `from:` listesi iki izinli kaynak içerir:
1. Kaynak (Next.js - aynı namespace):
   `- podSelector:` -> `matchLabels:` -> `app: erasmus-nextjs`
2. Kaynak (NGINX Ingress - farklı namespace):
   `- namespaceSelector:` -> `matchLabels:` -> `kubernetes.io/metadata.name: <INGRESS_NAMESPACE>`
   `  podSelector:` (aynı `-` maddesi içinde, tire OLMADAN!) -> `matchLabels:` -> `<INGRESS_POD_ETİKETİ>`
Ve `ports:` altında:
- `protocol: TCP`
- `port: {{ .Values.express.containerPort }}` (Service portu değil, Post-DNAT containerPort!)

</details>

**c) Çözüm Kanıtı:**
```bash
# 1. Tarayıcı / Ingress üzerinden /api/health erişimi hala 200 OK dönmeli:
curl -i -H "Host: erasmus.local" http://<INGRESS_IP>/api/health

# 2. Yetkisiz bir test podundan Express'e doğrudan erişim ENGELLENMELİ:
kubectl run intruder --rm -it --restart=Never --image=busybox:1.36 -- wget -qO- --timeout=3 http://erasmus-express-svc:<SVC_PORT>/api/health
```
- İlk komut başarılı, ikinci komut (`intruder`) timeout ile başarısız olmalıdır.

---

## Faz 4: Terraform ile Azure AKS Altyapısı

Yerel kümede Helm chart'ın kusursuz çalıştıktan sonra şimdi bulut altyapısını Terraform ile kodlayacaksın.

---

### Bilet 12: Terraform Provider ve Öğrenci Bütçesi Değişkenleri (`versions.tf` & `variables.tf`)

**a) Görev Tanımı:**
- [versions.tf](file:///home/ysf/k8s-hands-on-labs/projects/erasmus-connect/terraform/versions.tf) içinde `required_version`, `azurerm` provider kaynağı ve boş `features {}` bloğunu yaz.
- [variables.tf](file:///home/ysf/k8s-hands-on-labs/projects/erasmus-connect/terraform/variables.tf) içindeki tüm değişkenlere `description`, `type` ve öğrenci bütçesine uygun `default` değerlerini tanımla (`node_count = 1`, `vm_size = "Standard_B2s"`).

**b) İpucu ve Referans:**
- Resmi dokümantasyon: `registry.terraform.io/providers/hashicorp/azurerm/latest/docs`
- Azure CLI ile aboneliğinde `Standard_B2s` VM'in seçtiğin bölgede (ör. `polandcentral`, `germanywestcentral`, `westeurope`) kotasının açık olduğunu kontrol et:
  `az vm list-skus --location westeurope --size Standard_B2s --output table`
- `azurerm` provider'da `provider "azurerm" { features {} }` bloğu zorunludur; yazmazsan `terraform validate` hata verir.

**c) Çözüm Kanıtı:**
```bash
cd terraform
terraform init
terraform validate
```
- `Success! The configuration is valid.` çıktısını gör.

---

### Bilet 13: Azure AKS Kümesi ve Calico `network_profile` (`main.tf` & `outputs.tf`)

**a) Görev Tanımı:**
- [main.tf](file:///home/ysf/k8s-hands-on-labs/projects/erasmus-connect/terraform/main.tf) içindeki `[Bilet 13]` `# TODO` kısımlarını tamamla:
  - `azurerm_resource_group` argümanları
  - `azurerm_kubernetes_cluster` temel argümanları (`name`, `location`, `resource_group_name`, `dns_prefix`)
  - `default_node_pool` (`name`, `node_count`, `vm_size`, `os_disk_size_gb`)
  - `identity` (`type = "SystemAssigned"`)
  - `network_profile` (`network_plugin` ve `network_policy = "calico"`)
- [outputs.tf](file:///home/ysf/k8s-hands-on-labs/projects/erasmus-connect/terraform/outputs.tf) içinde küme adı, resource group adı ve `kube_config_raw` (`sensitive = true`) çıktılarını yaz.

**b) İpucu ve Referans:**
- Resmi dokümantasyon: Google'da `azurerm_kubernetes_cluster terraform` ara ve `registry.terraform.io` sayfasındaki **Example Usage** ve **Argument Reference** bölümlerini incele.
- **Kritik Mühendislik Kararı (`network_profile`):**
  - `network_policy = "calico"` ayarını vermezsen Faz 3'te yazdığın tüm `NetworkPolicy` YAML'ları AKS'te **hiçbir işe yaramadan sessizce yok sayılır**!
  - `network_plugin` için `"azure"` (Azure CNI) veya `"kubenet"` farkını incele: `Standard_B2s` gibi küçük bir VM'de `azure` CNI her pod için VNet IP'si ayırır (`max_pods` varsayılan 30'dur ve subnet boyutunu planlamak gerekir); basit öğrenci/tek-node kurulumlarda `network_plugin = "azure"` + `network_policy = "calico"` standart kombinasyonudur (`kubenet` ile Calico birlikte Azure'da desteklenmez!).

<details>
<summary>🆘 Takılırsan Aç (Reveal): `azurerm_kubernetes_cluster` Blok İsimleri</summary>

`resource "azurerm_kubernetes_cluster" "erasmus" { ... }` içinde şu alt blokları `Argument Reference`'a bakarak doldur:
- `default_node_pool { name = ... node_count = ... vm_size = ... }`
- `identity { type = "SystemAssigned" }`
- `network_profile { network_plugin = "azure" network_policy = "calico" }`
`outputs.tf` içinde hassas veri için:
- `output "kube_config" { value = azurerm_kubernetes_cluster.erasmus.kube_config_raw sensitive = true }`

</details>

**c) Çözüm Kanıtı:**
```bash
cd terraform
terraform fmt -check
terraform validate
```

---

### Bilet 14: `terraform plan`, Canlıya Çıkış, AKS'e Helm Deploy ve Uyku Modu

**a) Görev Tanımı:**
- [terraform.tfvars.example](file:///home/ysf/k8s-hands-on-labs/projects/erasmus-connect/terraform/terraform.tfvars.example) dosyasını `terraform.tfvars` olarak kopyalayıp değerlerini doldur.
- `terraform plan` çıktısını **satır satır oku**: Oluşacak ücretli kaynakları (VM, Managed Disk, LoadBalancer / Public IP) gör ve `terraform apply` ile kümeyi kur.
- AKS kubeconfig'i al, NGINX Ingress Controller'ı AKS'e kur ve Faz 1-3'te hazırladığın Helm chart'ını canlı AKS kümesine deploy et.
- Çalışman bittiğinde öğrenci kredini korumak için kümeyi durdur.

**b) İpucu ve Referans:**
- Azure girişi ve plan:
  `az login`
  `terraform plan -out=tfplan`
  `terraform apply tfplan`
- Kubeconfig çekme:
  `az aks get-credentials --resource-group <RG_ADI> --name <CLUSTER_ADI>`
- AKS üzerine NGINX Ingress kurulumu:
  `helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx`
  `helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx --namespace ingress-nginx --create-namespace`
- **Maliyet Koruma Komutu (Akşam Test Bitince Mutlaka Çalıştır!):**
  `az aks stop --resource-group <RG_ADI> --name <CLUSTER_ADI>`
  (Ertesi gün devam etmek için `az aks start ...`, işi tamamen bitirdiğinde ise `terraform destroy` kullan.)

**c) Çözüm Kanıtı:**
```bash
kubectl get nodes
kubectl get pods -A
kubectl get ingress
curl -i -H "Host: <DOMAIN>" http://<AKS_INGRESS_EXTERNAL_IP>/api/health
```
- AKS node'unun `Ready`, tüm Erasmus Connect podlarının `Running`, `curl` isteğinin ise `200 OK` döndüğünü doğrula.

---

## Kontrol Listesi (Kendini Değerlendir)

- [ ] Hiçbir şifre/connection string Git'e veya `values.yaml` içine açıkça yazılmadı.
- [ ] `express-deployment.yaml` ve `nextjs-deployment.yaml` podları `0.0.0.0` dinliyor ve `containerPort` ile Service `targetPort` eşleşiyor.
- [ ] Redis `StatefulSet` ve `Headless Service` (`clusterIP: None`) kararlı DNS ile çalışıyor.
- [ ] Tüm podların `requests` ve `limits` değerleri tek `Standard_B2s` node kapasitesine sığıyor.
- [ ] Next.js podu Redis `6379` portuna ulaşamıyor (Calico engelliyor), sadece Express podu ulaşabiliyor.
- [ ] Express `NetworkPolicy` kuralı **Post-DNAT** gerçekliğini (pod `containerPort` + Ingress `namespaceSelector`) doğru yansıtıyor.
- [ ] `terraform destroy` veya `az aks stop` ile gereksiz bulut maliyeti önlendi.
