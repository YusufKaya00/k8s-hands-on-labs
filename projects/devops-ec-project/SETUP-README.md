# Erasmus Connect — Adım Adım Kurulum ve DevOps Lab Rehberi (Helm + Calico + AKS)

> **[🇹🇷 Türkçe](#-türkçe-bölüm) | [🇬🇧 English](#-english-section)**  
> Mimari özet, proje yapısı ve uçtan uca akış için ana **[README.md](./README.md)** dosyasına bakabilirsin.

<a id="-türkçe-bölüm"></a> Bu dosya; yerel Minikube kümesinden Azure AKS + ACR + ArgoCD GitOps kurulumuna kadar tüm süreci adım adım (bilet tabanlı) ve gerçek kurulumda karşılaşılan hataların çözümleriyle anlatır.

Bu proje, **Erasmus Connect** uygulamasını (**Next.js** frontend, **Admin Vite** paneli, **Express** backend, **Redis** önbellek/oturum katmanı, harici **MongoDB Atlas** ve **Supabase**) her satırın mühendislik gerekçesini anlayarak **Kubernetes (Helm)** ve **Azure AKS (Terraform + Ansible + ArgoCD + ACR)** üzerine taşımak için hazırlanmış bilet tabanlı (ticket-driven) kurulum ve uygulama rehberidir.

> [!NOTE]
> **Rehber Yapısı:** Her bilet önce ne yapılacağını, ardından `kubectl explain` / `helm template` / `registry.terraform.io` referanslarını ve gerçek ortamda yaşanan tuzakları (troubleshooting notlarını) verir. `.env.*` ve `terraform.tfvars` gibi gizli dosyalar `.gitignore` içindedir; kendi değerlerini `.env.example` ve `terraform.tfvars.example` şablonlarından üretmelisin.

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
                     [ Redis Headless Svc ]    [ Secret + ConfigMap (envFrom) ]
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
- Bu aşamada `projects/devops-ec-project/helm/erasmus-connect/` içindeki `# TODO` dosyalarını incele, henüz eksikler olduğu için neden hata/boşluk çıktığını gözlemle.

**b) İpucu ve Referans:**
- Minikube ile Calico başlatma: `minikube start --network-plugin=cni --cni=calico` (veya `k3d` kullanıyorsan Calico CNI kurulumlu küme).
- Ingress addon kontrolü (Minikube): `minikube addons enable ingress`

> [!WARNING]
> **Eski Docker Volume Tuzağı (`K8S_APISERVER_MISSING`):** Daha önce Minikube kurup sildiysen ve geride eski `minikube` Docker volume'u kaldıysa, yeni başlatmada `kubelet` `/etc/kubernetes/bootstrap-kubelet.conf` hatasıyla API server ayağa kalkmayabilir. Çözüm: `minikube delete && docker volume rm minikube` veya izole yeni profil (`minikube start -p erasmus --network-plugin=cni --cni=calico`).
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
- [values.yaml](./helm/erasmus-connect/values.yaml) içinde `express.image` (`repository`, `tag`) ve `express.containerPort` değerlerini doldur.
- [express-deployment.yaml](./helm/erasmus-connect/templates/express-deployment.yaml) içindeki `[Bilet 2]` `# TODO` satırını kaldırıp `ports:` bloğunu yaz.
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
- [values.yaml](./helm/erasmus-connect/values.yaml) içindeki `express.service` altını (`type`, `port`) doldur.
- [express-service.yaml](./helm/erasmus-connect/templates/express-service.yaml) içindeki tüm `[Bilet 3]` `# TODO` bloklarını (`type`, `selector`, `ports`) yaz.
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
- [values.yaml](./helm/erasmus-connect/values.yaml) içindeki `nextjs` alanlarını (image, service, containerPort) doldur.
- [nextjs-deployment.yaml](./helm/erasmus-connect/templates/nextjs-deployment.yaml) içine `ports:` ve `env:` bloklarını (`[Bilet 4]`) ekle (`HOSTNAME=0.0.0.0`, `PORT`).
- [nextjs-service.yaml](./helm/erasmus-connect/templates/nextjs-service.yaml) içindeki `[Bilet 4]` `# TODO` kısımlarını doldur.
- **Frontend imajını lokal URL'lerle yeniden build et.** Docker Hub'daki `erasmus-connect-frontend:latest` imajı `NEXT_PUBLIC_API_URL=https://api.erasmusconnect.net` ile build edildi. Bu değer JS paketine gömülü olduğu için lokalde tarayıcın **canlı API'ye** gider, senin kümene değil.

> [!WARNING]
> **`NEXT_PUBLIC_*` & `VITE_*` = Build-time, Secret değil.** Frontend (`NEXT_PUBLIC_API_URL`) ve Admin paneli (`VITE_BACKEND_URL` / Vite `define`) değişkenleri build sırasında JavaScript'e gömülür; Pod'a `env:` olarak vermek **hiçbir şeyi değiştirmez**. Bu yüzden Secret/ConfigMap'e değil, [.env.frontend-build](./.env.frontend-build) dosyasından `docker build --build-arg` ile verilirler. Ayrıca Admin paneli Vite `base: '/'` ve `nginx:alpine` (:80) kullandığı için ayrı bir alt alan adına (`admin.<DOMAIN>`) yönlendirilir.
>
> **Mobil Tarayıcı Mixed Content Tuzağı:** Telefonda Chrome gibi tarayıcılar *HTTPS-First* moduyla `http://<IP>.nip.io` adresini otomatik `https://`ye yükseltip HTTP/WS API isteklerini bloklayabilir. Dev ortamında adresi açıkça `http://` ile açmalı veya prod için `cert-manager` ile TLS eklemelisin.

**b) İpucu ve Referans:**
- Terminalde çalıştır:
  `kubectl explain deployment.spec.template.spec.containers.env`
- `env` bir `<[]Object>` listesidir (`- name: ...` ve `value: "..."` alır).

> [!NOTE]
> **`containerPort` vs `env` (`PORT` + `| quote`) Kuralı:**
> - `ports[].containerPort` sadece **Kubernetes'e** bilgi verir (uygulamayı etkilemez, sayı/`<integer>` ister).
> - `env[].PORT` sadece **uygulama portu `process.env.PORT` üzerinden okuyorsa** (Next.js, Express gibi) yazılır; Redis (`6379`) veya Nginx (`80`) gibi sabit portlu hazır imajlarda `env` olarak `PORT` açmaya gerek yoktur.
> - `env` altında sayısal bir değer (`PORT` vb.) veriyorsan `| quote` **her zaman zorunludur**, çünkü `env.value` sadece metin (`<string>`) kabul eder.
- **Build-arg akışı (frontend repo'nda):**
  1. `Dockerfile`'ı aç. Her `NEXT_PUBLIC_*` için bir `ARG` satırı ve onu `ENV`'e aktaran satır, `RUN npm run build` satırından **önce** var mı? Yoksa ekle. Build sırasında sadece `ENV`'deki değerleri Next.js görür.
  2. `.env.frontend-build` içindeki her satırı `--build-arg` olarak ver. `docker build --help | grep build-arg` ile sözdizimine bak. Bash'te dosyadan otomatik üretmek için: `sed 's/^/--build-arg /' .env.frontend-build | grep -v '^--build-arg #' | xargs`
  3. İmajı Minikube'un içinde build et, Docker Hub'a pushlamana gerek kalmaz: `minikube image build --help` ya da `eval $(minikube docker-env)`.
  4. Lokal imaja farklı bir tag ver (ör. `local`) ve `values.yaml`'da `nextjs.image.tag` değerini ona çevir. `pullPolicy: Never` ya da `IfNotPresent` kullan.

<details>
<summary>🆘 Takılırsan Aç (Reveal): `env` Bloğu Yazım Kalıbı</summary>

`containers:` altındaki bir container içinde `env:` şu kalıpla yazılır:
- `env:` (10 boşluk)
- `  - name: <DEĞİŞKEN_ADI>` (12 boşluk + tire)
- `    value: "<DEĞER>"` (14 boşluk)
Dikkat: Sayı veya boolean bile olsa Kubernetes `env.value` alanı `<string>` tipindedir; tırnak (`"..."`) içinde yaz! Helm'de sayıyı string yapmak için: `{{ .Values.nextjs.containerPort | quote }}`

</details>

**c) Çözüm Kanıtı:**
```bash
helm template erasmus ./helm/erasmus-connect -s templates/nextjs-deployment.yaml
helm template erasmus ./helm/erasmus-connect -s templates/nextjs-service.yaml

# İmaja gerçekten lokal URL gömüldü mü? (canlı domain ÇIKMAMALI)
minikube image ls | grep frontend
kubectl exec deploy/erasmus-erasmus-connect-nextjs -- sh -c "grep -rl 'erasmus.local' .next/ | head -3"
kubectl exec deploy/erasmus-erasmus-connect-nextjs -- sh -c "grep -rl 'api.erasmusconnect.net' .next/ | head -3"
```
- İlk `grep` dosya bulmalı, ikincisi boş dönmeli.

---

### Bilet 5: Redis StatefulSet ve Headless Service (`clusterIP: None`)

**a) Görev Tanımı:**
- [values.yaml](./helm/erasmus-connect/values.yaml) içinde `redis` portu (`6379`) ve PVC boyutunu (ör. `1Gi`) tanımla.
- [redis-service.yaml](./helm/erasmus-connect/templates/redis-service.yaml) içinde bu Service'i **Headless Service** yapacak kritik `clusterIP` ayarını, `selector` ve `ports` alanlarını yaz.
- [redis-statefulset.yaml](./helm/erasmus-connect/templates/redis-statefulset.yaml) içinde `serviceName`, `ports`, `volumeMounts` (`/data`) ve `volumeClaimTemplates` alanlarını tamamla.

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

### Bilet 6: `.env` → Secret + ConfigMap → `envFrom` (Secret'lar Git'e Girmeden)

**a) Görev Tanımı:**
- Railway'den aldığın değişkenler 3 dosyaya ayrıldı (hepsi `.gitignore`'da, Git'e sadece değer içermeyen [.env.example](./.env.example) girer):

| Dosya | Kümede neye dönüşür? | Kural |
| :--- | :--- | :--- |
| `.env.backend-secrets` | **Secret** `erasmus-backend-secrets` | Sızarsa zarar verir (DB şifresi, JWT, API key) |
| `.env.backend-config` | **ConfigMap** `erasmus-backend-config` | Sızsa da sorun olmaz (log level, URL, port) |
| `.env.frontend-build` | Kümeye **gitmez**, `docker build --build-arg` | `NEXT_PUBLIC_*` build-time değerler (Bilet 4) |

- Bu Secret ve ConfigMap'i **Helm değil, sen** terminalden oluşturacaksın. Chart sadece onların **adını** bilir.
- [values.yaml](./helm/erasmus-connect/values.yaml) içindeki `envFrom.backendSecretName` ve `envFrom.backendConfigMapName` `# TODO`'larını doldur.
- [express-deployment.yaml](./helm/erasmus-connect/templates/express-deployment.yaml) içindeki iki `[Bilet 6]` `# TODO`'yu doldur: küçük bir `env:` (`HOST`, `PORT`) ve `envFrom:`.

**Neden böyle?** Azure'a geçtiğinde (Faz 4) aynı isimli Secret'ı Azure Key Vault CSI Driver oluşturacak. Chart'ta tek satır değişmeyecek, sadece Secret'ı oluşturan şey değişecek.

**b) İpucu ve Referans:**
- Secret ve ConfigMap'i dosyadan oluşturmanın bayrağını kendin bul:
  `kubectl create secret generic --help | grep -A3 "from-env-file"`
  `kubectl create configmap --help | grep -A3 "from-env-file"`
- `envFrom` yapısını incele:
  `kubectl explain pod.spec.containers.envFrom`
  `kubectl explain pod.spec.containers.envFrom.secretRef`
- `env` + `secretKeyRef` farkı: `secretKeyRef` her key için 5 satır ister (30 değişken için 150 satır). `envFrom` ise Secret'taki **tüm** key'leri tek seferde env değişkeni yapar.
- **Tekrar çalıştırma tuzağı:** `kubectl create` ikinci kez çalışınca `AlreadyExists` hatası verir. `.env` değişince güncellemek için standart kalıp: `kubectl create ... --dry-run=client -o yaml | kubectl apply -f -`
- **Değişiklik pod'a otomatik yansımaz:** Secret/ConfigMap'i güncelledikten sonra `envFrom` ile okunan değerler ancak pod yeniden başlayınca değişir: `kubectl rollout restart deploy/<ad>`.
- `.env` formatı: `--from-env-file` tırnakları **silmez**, değerin parçası olarak alır. Bu yüzden dosyalarda değerler tırnaksız yazıldı (`KEY=value`). Railway'den tırnaklı kopyalarsan dikkat.

<details>
<summary>🆘 Takılırsan Aç (Reveal): Terminalden Secret Oluşturma ve `express-deployment.yaml` (`env` + `envFrom`) Yazım Kalıbı</summary>

**Adım 1 — Terminalde `.env` dosyalarından Secret ve ConfigMap'i kümeye yükle (`values.yaml` içine şifre YAZILMAZ!):**
```bash
kubectl create secret generic erasmus-backend-secrets \
  --from-env-file=.env.backend-secrets \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create configmap erasmus-backend-config \
  --from-env-file=.env.backend-config \
  --dry-run=client -o yaml | kubectl apply -f -
```

**Adım 2 — `express-deployment.yaml` içinde `imagePullPolicy:` ile aynı hizada (10 boşluk) `env:` ve `envFrom:` yaz:**
```yaml
          env:
            - name: HOST
              value: "0.0.0.0"
            - name: PORT
              value: {{ .Values.express.containerPort | quote }}
          envFrom:
            - configMapRef:
                name: {{ .Values.envFrom.backendConfigMapName }}
            - secretRef:
                name: {{ .Values.envFrom.backendSecretName }}
```
Sıra önemlidir: aynı key iki yerde varsa **listede sonra gelen kazanır**. `env:` ile verilen değerler ise `envFrom`'un hepsini ezer.

</details>

**c) Çözüm Kanıtı:**
```bash
# 1. Git'e secret girmiyor mu?
git status --short          # .env.backend-secrets görünMEMELİ
git check-ignore -v .env.backend-secrets

# 2. Secret ve ConfigMap kümede mi? (describe değerleri GÖSTERMEZ, sadece key ve byte sayısı)
kubectl describe secret erasmus-backend-secrets
kubectl describe configmap erasmus-backend-config

# 3. Render edilen YAML'da hiç gerçek değer yok, sadece isimler var mı?
helm template erasmus ./helm/erasmus-connect -s templates/express-deployment.yaml | grep -A6 envFrom
helm template erasmus ./helm/erasmus-connect | grep -i "mongodb+srv"   # BOŞ dönmeli

# 4. Pod içinde değişkenler gerçekten yüklendi mi? (değeri basma, sadece varlığını kontrol et)
kubectl exec deploy/erasmus-erasmus-connect-express -- sh -c 'env | cut -d= -f1 | sort'
```

> [!NOTE]
> `kubectl get secret erasmus-backend-secrets -o yaml` çıktısındaki değerler base64'tür, **şifreli değildir**. `echo <değer> | base64 -d` ile herkes çözer. Kümede de Secret'ları kimin okuyabileceğini RBAC ile sınırlamak gerekir.

---

### Bilet 7: Kaynak Sınırları (`resources`: `requests` ve `limits`)

**a) Görev Tanımı:**
- [values.yaml](./helm/erasmus-connect/values.yaml) içinde `express`, `nextjs` ve `redis` için `resources:` altında `requests` ve `limits` değerlerini belirle.
- [express-deployment.yaml](./helm/erasmus-connect/templates/express-deployment.yaml), [nextjs-deployment.yaml](./helm/erasmus-connect/templates/nextjs-deployment.yaml) ve [redis-statefulset.yaml](./helm/erasmus-connect/templates/redis-statefulset.yaml) içindeki `[Bilet 7]` `# TODO` kısımlarına `resources:` bloğunu ekle.
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
- [values.yaml](./helm/erasmus-connect/values.yaml) içinde `express.healthPath` alanını doldur (uygulaman `/health` veya `/api/health` dönmüyorsa Express koduna 200 OK dönen bir endpoint ekle!).
- [express-deployment.yaml](./helm/erasmus-connect/templates/express-deployment.yaml), [nextjs-deployment.yaml](./helm/erasmus-connect/templates/nextjs-deployment.yaml) ve [redis-statefulset.yaml](./helm/erasmus-connect/templates/redis-statefulset.yaml) içindeki `[Bilet 8]` `# TODO` kısımlarını doldur.
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
# Bilet 9'daki ingress.yaml henüz boşsa kurulumda geçici kapatabilirsin:
helm upgrade --install erasmus ./helm/erasmus-connect --set ingress.enabled=false
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
- [values.yaml](./helm/erasmus-connect/values.yaml) içinde `ingress.className` (`nginx`) ve `ingress.host` (ör. `erasmus.local`) alanlarını doldur.
- [ingress.yaml](./helm/erasmus-connect/templates/ingress.yaml) dosyasındaki `[Bilet 9]` `# TODO` kısımlarını tamamla:
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

> [!WARNING]
> **Timeout Tuzağı (Boş NetworkPolicy'ler):** `networkpolicy-redis.yaml` ve `networkpolicy-express.yaml` içindeki `# TODO` kısımları henüz boşken `helm upgrade` yaptığında kümede `podSelector: {}` (Default-Deny-All) uygulanır ve Calico tüm trafiği keser (`Operation timed out`). Bu yüzden:
> - Ya Bilet 10 & 11'i de doldurduktan sonra `curl` testini çalıştır,
> - Ya da sadece Ingress'i şimdi görmek için boş policy'leri geçici sil (`kubectl delete netpol erasmus-express-post-dnat erasmus-redis-isolation`), test et ve hemen Bilet 10–11'e geç.

Yerel kümede Ingress Controller IP'sini (`minikube ip` veya `kubectl get ingress`) kullanarak `Host` header'ı ile test et (`--reset-values` ile Bilet 8'deki `--set ingress.enabled=false` önbelleğini temizle):
```bash
helm upgrade --install erasmus ./helm/erasmus-connect --reset-values
kubectl get ingress
curl -i -H "Host: erasmus.local" http://<INGRESS_IP>/
curl -i -X POST -H "Host: erasmus.local" http://<INGRESS_IP>/api/v1/ping
```
- `/` isteği Next.js HTML/200 dönmeli, `/api/v1/ping` isteği Express `{"ok":true}`/200 dönmelidir.

---

### Bilet 10: Redis Zero-Trust İzolasyonu (`networkpolicy-redis.yaml`)

**a) Görev Tanımı:**
- [networkpolicy-redis.yaml](./helm/erasmus-connect/templates/networkpolicy-redis.yaml) dosyasındaki `[Bilet 10]` `# TODO` kısımlarını doldur.
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
- [networkpolicy-express.yaml](./helm/erasmus-connect/templates/networkpolicy-express.yaml) dosyasındaki `[Bilet 11]` `# TODO` kısımlarını doldur.
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
# 1. Tarayıcı / Ingress üzerinden /api/v1/ping erişimi hala 200 OK dönmeli:
curl -i -X POST -H "Host: erasmus.local" http://<INGRESS_IP>/api/v1/ping

# 2. Yetkisiz bir test podundan Express'e doğrudan erişim ENGELLENMELİ:
kubectl run intruder --rm -it --restart=Never --image=busybox:1.36 -- wget -qO- --timeout=3 http://erasmus-express-svc:<SVC_PORT>/health
```
- İlk komut başarılı, ikinci komut (`intruder`) timeout ile başarısız olmalıdır.

---

## Faz 4: Terraform ile Azure AKS Altyapısı

Yerel kümede Helm chart'ın kusursuz çalıştıktan sonra şimdi bulut altyapısını Terraform ile kodlayacaksın.

---

### Bilet 12: Terraform Provider ve Öğrenci Bütçesi Değişkenleri (`versions.tf` & `variables.tf`)

**a) Görev Tanımı:**
- [versions.tf](./terraform/versions.tf) içinde `required_version`, `azurerm` provider kaynağı (`version = "~> 4.0"` sabitlemesi) ve boş `features {}` bloğunu yaz.
- [variables.tf](./terraform/variables.tf) içindeki tüm değişkenlere `description`, `type` ve öğrenci bütçesine uygun `default` değerlerini tanımla (`node_count = 1`, `vm_size = "Standard_B2s"`).

> [!WARNING]
> **Provider Sürüm Tuzağı (`azurerm 5.x`):** `versions.tf` içinde `version = "~> 4.0"` sabitlemesi koymazsan Terraform yeni `azurerm 5.x` sürümünü çekip `node_provisioning_profile` gibi yeni zorunlu alanlar veya breaking change hataları çıkarabilir.
>
> **Değişken Öncelik Kuralı:** `terraform.tfvars` dosyasındaki değerler her zaman `variables.tf` içindeki `default` değerlerini ezer. İleride `node_count` gibi bir ayarı değiştirdiğinde `terraform.tfvars` dosyanı da kontrol et.

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
- [main.tf](./terraform/main.tf) içindeki `[Bilet 13]` `# TODO` kısımlarını tamamla:
  - `azurerm_resource_group` argümanları
  - `azurerm_kubernetes_cluster` temel argümanları (`name`, `location`, `resource_group_name`, `dns_prefix`)
  - `default_node_pool` (`name`, `node_count`, `vm_size`, `os_disk_size_gb`)
  - `identity` (`type = "SystemAssigned"`)
  - `network_profile` (`network_plugin` ve `network_policy = "calico"`)
- [outputs.tf](./terraform/outputs.tf) içinde küme adı, resource group adı ve `kube_config_raw` (`sensitive = true`) çıktılarını yaz.

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
- [terraform.tfvars.example](./terraform/terraform.tfvars.example) dosyasını `terraform.tfvars` olarak kopyalayıp değerlerini doldur.
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
curl -i -X POST -H "Host: <DOMAIN>" http://<AKS_INGRESS_EXTERNAL_IP>/api/v1/ping
```
- AKS node'unun `Ready`, tüm Erasmus Connect podlarının `Running`, `curl` isteğinin ise `200 OK` döndüğünü doğrula.

*(Elle `az aks get-credentials` ve tek tek `helm` komutları çalıştırmak yerine aşağıdaki **Faz 5 (Ansible)** ile bu adımların tamamını tek komutla otomatikleştirebilirsin!)*

---

## Faz 5: Ansible ile AKS Üzerine Otomatik Kurulum ve Helm Orkestrasyonu

Terraform ile altyapıyı (AKS kümesini) kurduktan sonra, küme içindeki **NGINX Ingress Controller + Secret/ConfigMap + Erasmus Connect Helm Chart** kurulumunu tek bir idempotent `ansible-playbook` komutuyla otomatikleştireceksin. İlk kurulumu Ansible ile yapıp, sonraki uygulama güncellemelerini doğrudan `helm upgrade` (veya playbook'u tekrar koşarak) yöneteceksin.

> [!NOTE]
> **AKS'te Ansible Neden `localhost` Üzerinde Çalışır?**
> RKE2/K3s lablarında Ansible VM'lere SSH atıp Kubernetes kuruyordu. **Azure AKS yönetilen (managed) bir Kubernetes servisi** olduğu için node'lara SSH atılmaz; Ansible senin bilgisayarında (`ansible_connection=local`) çalışır ve `az` + `kubectl` + `kubernetes.core.helm` modüllerini orkestre eder.

---

### Bilet 15: Ansible Envanteri, AKS Kubeconfig ve NGINX Ingress Kurulumu

**a) Görev Tanımı:**
- [ansible.cfg](./ansible/ansible.cfg) ve [inventory.ini](./ansible/inventory.ini) dosyalarını incele (`localhost ansible_connection=local` yapısını anla).
- [playbook.yml](./ansible/playbook.yml) içindeki `vars:` bölümünde `resource_group` ve `cluster_name` (`[Bilet 15]`) değişkenlerini doldur.
- [playbook.yml](./ansible/playbook.yml) içindeki **ADIM 1, 2 ve 3** `# TODO` görevlerini yaz:
  1. `az aks get-credentials` ile AKS kubeconfig'i al.
  2. `kubernetes.core.helm_repository` ile `ingress-nginx` Helm deposunu ekle.
  3. `kubernetes.core.helm` ile `ingress-nginx` controller'ını `ingress-nginx` namespace'ine kur (`wait: true`).
  - **Azure LoadBalancer Health Probe Ayarı:** `ingress-nginx` kurulurken Service annotation olarak `service.beta.kubernetes.io/azure-load-balancer-health-probe-request-path: "/healthz"` mutlaka verilmelidir. Aksi halde Azure LB, controller'ın `/` yoluna `Host` header'ı olmadan istek atar, NGINX `404` döner ve Azure dış trafiği keser (`Connection timed out`)!

**b) İpucu ve Referans:**
- Terminalde modül dokümantasyonunu oku:
  `ansible-doc kubernetes.core.helm_repository`
  `ansible-doc kubernetes.core.helm`
- **Idempotency (Tekrar Çalıştırılabilirlik):** Playbook'u 2. kez çalıştırdığında hata vermemeli; `kubernetes.core.helm` zaten `helm upgrade --install` gibi çalışır ve kurulu release'i günceller.
- `az aks get-credentials` komutuna `--overwrite-existing` eklemezsen ikinci çalıştırmada `y/n` sorusu sorup Ansible'ı kilitler!

<details>
<summary>🆘 Takılırsan Aç (Reveal): Bilet 15 Ansible Görev Şeması</summary>

`tasks:` altında her görev `- name: ...` ile başlar:
- ADIM 1 (`ansible.builtin.command`):
  `cmd: az aks get-credentials --resource-group {{ resource_group }} --name {{ cluster_name }} --overwrite-existing`
  `changed_when: false`
- ADIM 2 (`kubernetes.core.helm_repository`):
  `name: ingress-nginx`
  `repo_url: https://kubernetes.github.io/ingress-nginx`
- ADIM 3 (`kubernetes.core.helm`):
  `name: ingress-nginx`, `chart_ref: ingress-nginx/ingress-nginx`, `release_namespace: ingress-nginx`, `create_namespace: true`, `wait: true`

</details>

**c) Çözüm Kanıtı:**
```bash
cd ansible
ansible-playbook --syntax-check playbook.yml
ansible-playbook playbook.yml
kubectl get pods -n ingress-nginx
```
- `ingress-nginx-controller` podunun AKS üzerinde `1/1 Running` olduğunu doğrula.

---

### Bilet 16: Secret/ConfigMap Yükleme, Helm Deploy ve Sonraki Güncellemeler

**a) Görev Tanımı:**
- [playbook.yml](./ansible/playbook.yml) içindeki **ADIM 4, 5 ve 6** `# TODO` görevlerini doldur:
  - **ADIM 4:** `../.env.backend-secrets` ve `../.env.backend-config` dosyalarından `erasmus-backend-secrets` ile `erasmus-backend-config` nesnelerini idempotent şekilde (`--dry-run=client -o yaml | kubectl apply -f -`) oluştur. *(Faz 8'de ACR + `AcrPull`'a geçmeden önce geçici olarak private Docker Hub kullanıyorsan `dockerhub-secret` oluşturma adımını ekle; Docker Hub PAT yetkisi `Public Repo Read-only` değil, **`Read-only` (Private + Public)** olmalıdır, yoksa `insufficient_scope: authorization failed` hatası alırsın.)*
  - **ADIM 5:** `kubernetes.core.helm` modülü ile `../helm/erasmus-connect` chart'ını AKS'e kur (`wait: true`). *(Not: `kubernetes.core.helm`, `helm diff` eklentisi kurulu değilse lokal template/values değişikliklerini her zaman algılamayabilir; hızlı güncellemeler için doğrudan `helm upgrade --install erasmus ./helm/erasmus-connect -f ./helm/erasmus-connect/values.yaml -f ./helm/erasmus-connect/values-aks.yaml` kullanabilirsin.)*
  - **ADIM 6:** `ingress-nginx-controller` Service'inin Azure LoadBalancer External IP'sini çekip `ansible.builtin.debug` ile ekrana yazdır.
- **Dikkat (AKS İmaj ve Domain Farkı):** Minikube'daki `yusufk00/erasmus-connect-frontend:local` imajı sadece Minikube içindeydi! AKS'te kullanmak için ya canlı domain ile build alıp registry'ye (Docker Hub / ACR) pushla ya da `values` override'ı ile registry tag'ini ver (`kubernetes.core.helm` modülünün `values:` parametresiyle).

**b) İpucu ve Referans:**
- `ansible-doc kubernetes.core.helm` içinde `values:` (dictionary) parametresine bak — sadece AKS'e özel değişen değerleri (`nextjs.image.tag`, `ingress.host` gibi) doğrudan playbook üzerinden override edebilirsin.
- **Sonraki Güncelleme İş Akışı (Day-2 Operations):**
  - Altyapı bir kez Ansible ile kurulduktan sonra, uygulama kodunda/Helm chart'ında bir değişiklik yaptığında ister `helm upgrade erasmus ./helm/erasmus-connect` ile doğrudan güncelle, ister `ansible-playbook playbook.yml` komutunu tekrar çalıştır — ikisi de aynı Helm release'ini günceller!

<details>
<summary>🆘 Takılırsan Aç (Reveal): ADIM 4 & 5 Görev Şeması</summary>

- ADIM 4 (`ansible.builtin.shell`):
  `kubectl create secret generic erasmus-backend-secrets --from-env-file=../.env.backend-secrets --dry-run=client -o yaml | kubectl apply -f -`
  *(Aynısını `configmap` ve `../.env.backend-config` için de yaz.)*
- ADIM 5 (`kubernetes.core.helm`):
  `name: "{{ release_name }}"`
  `chart_ref: "{{ chart_path }}"`
  `release_namespace: "{{ app_namespace }}"`
  `wait: true`
  *(İstersen altına `values:` ekleyip `ingress: { host: "<CANLI_DOMAIN_VEYA_NIP_IO>" }` geçebilirsin.)*

</details>

**c) Çözüm Kanıtı:**
```bash
cd ansible
ansible-playbook --syntax-check playbook.yml
ansible-playbook playbook.yml
helm list -A
kubectl get pods,svc,ingress -n default
```
- `helm list -A` çıktısında hem `ingress-nginx` hem `erasmus` release'lerinin `deployed` olduğunu ve Ingress External IP'sinin alındığını doğrula.

---

## Faz 6: Yüksek Erişilebilirlik (HPA & PDB) ve Kaos Mühendisliği (Chaos Mesh)

Uygulama canlı AKS üzerinde sorunsuz çalıştıktan sonra şimdi sistemi yük altında otomatik ölçekleyecek (`HPA`), bakım/kesinti anında ayakta tutacak (`PDB`) ve **Chaos Mesh** ile kasıtlı olarak bozup dayanıklılığını test edeceksin.

---

### Bilet 17: Replica Artışı, `Standard_B2s` Kapasite Ayarı ve HPA (`hpa-express.yaml`, `hpa-nextjs.yaml`)

**a) Görev Tanımı:**
- **Önce Kapasite Gerçeğini Gör:** AKS `Standard_B2s` düğümünde (2 vCPU, ~3.2 GB kullanılabilir RAM) `kubectl top nodes` ile mevcut kullanımın ~%61 RAM (~1946Mi) civarında olduğunu gördük; oysa gerçekte `express` 58Mi, `nextjs` 129Mi RAM harcıyor!
- [values.yaml](./helm/erasmus-connect/values.yaml) içinde:
  - Express ve Next.js `resources.requests.memory` değerlerini `256Mi`'dan gerçekçi seviyelere (`128Mi` / `160Mi`, CPU `50m`) çek ki node üzerinde 2–4 kopyaya yer açılsın!
  - `express.replicaCount` ve `nextjs.replicaCount` değerlerini `2` yap (veya HPA'nın altına `hpa.enabled: true` ile `minReplicas: 2`, `maxReplicas: 4` tanımla).
- [hpa-express.yaml](./helm/erasmus-connect/templates/hpa-express.yaml) ve [hpa-nextjs.yaml](./helm/erasmus-connect/templates/hpa-nextjs.yaml) içindeki `[Bilet 17]` `# TODO` kısımlarını doldur.
- **Helm + HPA Çakışması:** `express-deployment.yaml` ve `nextjs-deployment.yaml` içinde `replicas:` satırını `{{- if not .Values.express.hpa.enabled }}` ile sarmalarsan sonraki `helm upgrade` komutları HPA'nın ölçeklediği pod sayısını ezmez!

**b) İpucu ve Referans:**
- Terminalde çalıştır:
  `kubectl explain hpa.spec --api-version=autoscaling/v2`
  `kubectl explain hpa.spec.metrics --api-version=autoscaling/v2`
- `metrics-server` AKS'te zaten kurulu (`kubectl top pods` çalışıyor); ama **HPA'nın çalışması için Deployment'ta `resources.requests.cpu` tanımlı olmak ZORUNDADIR** (çünkü `averageUtilization: 60`, `requests.cpu`'nun %60'ına göre hesaplanır!).

<details>
<summary>🆘 Takılırsan Aç (Reveal): `HorizontalPodAutoscaler` (`autoscaling/v2`) Yapısı</summary>

`spec:` altında (2 boşluk):
- `scaleTargetRef:` -> `apiVersion: apps/v1`, `kind: Deployment`, `name: <DEPLOYMENT_ADI>`
- `minReplicas: <SAYI>`
- `maxReplicas: <SAYI>`
- `metrics:` (`[]Object`) -> `- type: Resource` -> `resource:` -> `name: cpu`, `target:` -> `type: Utilization`, `averageUtilization: <YÜZDE>`

</details>

**c) Çözüm Kanıtı:**
```bash
helm template erasmus ./helm/erasmus-connect -s templates/hpa-express.yaml | kubectl apply --dry-run=server -f -
# Ansible veya helm upgrade sonrası:
kubectl get hpa -n default
kubectl get pods -n default -o wide
```
- `kubectl get hpa` çıktısında `TARGETS` sütununun `<unknown>/60%` değil, gerçek yüzde (ör. `4%/60%`) gösterdiğini ve her iki Deployment'tan en az 2 podun `Running` olduğunu doğrula.

---

### Bilet 18: `PodDisruptionBudget` (`pdb.yaml`) ve Sıfır Kesinti Koruması

**a) Görev Tanımı:**
- [values.yaml](./helm/erasmus-connect/values.yaml) içinde `pdb.enabled: true` ve `minAvailable: 1` ayarla (**DİKKAT:** Bilet 17'de replika sayısını en az `2` yaptıktan sonra etkinleştir; aksi halde 1 replikalı podda `minAvailable: 1` node bakımını kilitler!).
- [pdb.yaml](./helm/erasmus-connect/templates/pdb.yaml) içindeki `[Bilet 18]` `# TODO` kısımlarını hem Express hem Next.js için doldur.

**b) İpucu ve Referans:**
- Terminalde çalıştır:
  `kubectl explain pdb.spec --api-version=policy/v1`
- PDB (`PodDisruptionBudget`), Kubernetes node güncellemesi veya `kubectl drain` sırasında aynı anda kaç podun ayakta kalmak zorunda olduğunu garanti eder.

<details>
<summary>🆘 Takılırsan Aç (Reveal): `PodDisruptionBudget` Yapısı</summary>

`spec:` altında:
- `minAvailable: 1`
- `selector:` -> `matchLabels:` -> `app: erasmus-express` (ikinci PDB'de `app: erasmus-nextjs`)

</details>

**c) Çözüm Kanıtı:**
```bash
kubectl get pdb -n default
```
- `MIN AVAILABLE: 1` ve `ALLOWED DISRUPTIONS: 1` (2 replika varken 1 podun kesintiye izinli olduğu) görünmelidir.

---

### Bilet 19: Chaos Mesh Kurulumu ve 3 Kaos Deneyi (`chaos/`)

**a) Görev Tanımı:**
- AKS kümesine **Chaos Mesh** kur (Azure AKS `containerd` kullandığı için daemon soketini doğru parametreyle vermen şart!).
- [chaos/](./chaos/) klasöründeki 3 deney dosyasının `# TODO` alanlarını kendi ellerinle doldur:
  1. [01-pod-kill-express.yaml](./chaos/01-pod-kill-express.yaml) (`PodChaos`): Express podlarından sadece 1 tanesini öldürürken dışarıdan sürekli `curl` atarak **sıfır kesinti (0 HTTP hatası)** olduğunu kanıtla!
  2. [02-network-delay-redis.yaml](./chaos/02-network-delay-redis.yaml) (`NetworkChaos`): Redis poduna `300ms` ağ gecikmesi enjekte edip Express yanıt sürelerinin nasıl etkilendiğini ölç.
  3. [03-stress-cpu-express.yaml](./chaos/03-stress-cpu-express.yaml) (`StressChaos`): Express poduna %80 CPU yükü verip **Bilet 17'deki HPA'nın** pod sayısını otomatik `2 -> 3+` artırdığını canlı izle!

**b) İpucu ve Referans:**
- Chaos Mesh Helm kurulumu (**AKS `containerd` ayarlı!**):
  ```bash
  helm repo add chaos-mesh https://charts.chaos-mesh.org
  helm repo update
  helm upgrade --install chaos-mesh chaos-mesh/chaos-mesh \
    --namespace chaos-mesh --create-namespace \
    --set chaosDaemon.runtime=containerd \
    --set chaosDaemon.socketPath=/run/containerd/containerd.sock \
    --set dashboard.securityMode=false
  ```
- Chaos Mesh kurulduktan sonra terminalde şemaları incele:
  `kubectl explain podchaos.spec`
  `kubectl explain networkchaos.spec`
  `kubectl explain stresschaos.spec`

<details>
<summary>🆘 Takılırsan Aç (Reveal): Chaos Mesh `selector` ve `stressors` Kalıbı</summary>

Her Chaos CRD'sinde `spec.selector:` ortaktır:
- `selector:`
  - `namespaces: ["default"]`
  - `labelSelectors:` -> `app: <ETİKET>`
`01-pod-kill-express.yaml` için: `action: pod-kill`, `mode: one`, `duration: "30s"`.
`02-network-delay-redis.yaml` için: `action: delay`, `mode: one`, `direction: both`, `delay: { latency: "300ms", jitter: "50ms" }`, `duration: "60s"`.
`03-stress-cpu-express.yaml` için: `mode: one`, `stressors: { cpu: { workers: 1, load: 80 } }`, `duration: "120s"`.

</details>

**c) Çözüm Kanıtı:**
```bash
# 1. Chaos Mesh podlarının çalıştığını doğrula:
kubectl get pods -n chaos-mesh

# 2. PodKill sırasında sıfır kesinti testi (ayrı bir terminalde sürekli ping atarken deneyi uygula):
while true; do curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" -X POST http://<AKS_INGRESS_IP>.nip.io/api/v1/ping; sleep 0.5; done
kubectl apply -f ./chaos/01-pod-kill-express.yaml

# 3. CPU Stresi ile HPA ölçekleme testi:
kubectl apply -f ./chaos/03-stress-cpu-express.yaml
kubectl get hpa,pods -n default -w
```
- PodKill sırasında `200` kodunun kesilmediğini, StressChaos uygulandıktan 30–60 saniye sonra ise `kubectl get hpa` çıktısında `REPLICAS` sayısının arttığını doğrula! *(Test bitince `kubectl delete -f ./chaos/` ile deneyleri temizle.)*

---

## Faz 7: ArgoCD ile GitOps Otomatik Dağıtım

Bu fazda artık `helm upgrade` veya `ansible-playbook` çalıştırmayı bırakıp, **GitHub'a yaptığın her push'un AKS kümesine otomatik yansıdığı (GitOps)** ArgoCD yapısını kuracaksın.

---

### Bilet 20: Node Ölçekleme (`node_count = 2`) ve ArgoCD Kurulumu

**a) Görev Tanımı:**
- Tek `Standard_B2s` node'un 30 pod limitini (`Too many pods`) ve RAM sınırını açmak için [variables.tf](./terraform/variables.tf) (ve varsa [terraform.tfvars](./terraform/terraform.tfvars)) içindeki `node_count` değerini `2` yap ve `terraform apply` ile kümeyi silmeden **yerinde** 2. node'u ekle (`60 pod`, `4 vCPU`, `8 GB RAM`).
- AKS üzerine `argocd` namespace'ini açıp resmi ArgoCD Helm chart'ını (veya resmi manifestosunu) kur.
- ArgoCD arayüzüne internete açmadan `kubectl port-forward` ile eriş ve ilk `admin` şifresini al.

**b) İpucu ve Referans:**
- Terraform ile node artırma:
  ```bash
  cd terraform
  terraform apply   # Plan'da ~ node_count: 1 -> 2 (in-place update) görmelisin, destroy OLMAMALI!
  ```
- ArgoCD Helm kurulumu (öğrenci kümesinde gereksiz HA kopyaları yerine hafif kurulum):
  ```bash
  helm repo add argo https://argoproj.github.io/argo-helm
  helm repo update
  helm upgrade --install argocd argo/argo-cd \
    --namespace argocd --create-namespace \
    --set configs.params."server\.insecure"=true
  ```
  *(Not: `server.insecure=true` iç TLS'i kapatır, `port-forward` yaparken tarayıcıda sertifika uyarısı görmeden bağlanmanı sağlar.)*
- İlk `admin` şifresini çekme:
  `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo`
- ArgoCD Web UI erişimi:
  `kubectl port-forward svc/argocd-server -n argocd 8085:80` → Tarayıcıda **`http://localhost:8085`** (Kullanıcı: `admin`).

**c) Çözüm Kanıtı:**
```bash
kubectl get nodes
kubectl get pods -n argocd
```
- 2 adet `Ready` node ve tüm `argocd-*` podlarının `Running` olduğunu doğrula.

---

### Bilet 21: ArgoCD `Application` Manifestosu, `values-aks.yaml` ve HPA Çakışma Koruması

**a) Görev Tanımı:**
- [argocd/erasmus-app.yaml](./argocd/erasmus-app.yaml) dosyasındaki tüm `[Bilet 21]` `# TODO` kısımlarını doldur:
  1. `source`: Reponun GitHub URL'si (`https://github.com/YusufKaya00/k8s-hands-on-labs.git`), `targetRevision: main`, `path: projects/devops-ec-project/helm/erasmus-connect`.
  2. `source.helm.valueFiles`: `values.yaml` ve `values-aks.yaml` (`values-aks.yaml` sona yazılır ki AKS imaj tag'lerini ve `nip.io` hostlarını üzerine yazsın!).
  3. `syncPolicy.automated`: `prune: true` ve `selfHeal: true`.
  4. `ignoreDifferences`: `apps/Deployment` kaynaklarında `/spec/replicas` alanını yoksay (**KRİTİK:** HPA replika sayısını artırdığında ArgoCD'nin geri düşürmemesi için!).
- **Secret Kuralı:** `erasmus-backend-secrets`, `erasmus-backend-config` ve `dockerhub-secret` yine Git'te değildir (kümede hazır durur).

**b) İpucu ve Referans:**
- Terminalde CRD şemasını incele:
  `kubectl explain application.spec.source.helm`
  `kubectl explain application.spec.syncPolicy.automated`
  `kubectl explain application.spec.ignoreDifferences`
- **Dikkat (Helm Release Devralma ve Ingress Çakışması):** Daha önce `helm install erasmus ...` ile kurduğun nesneler zaten kümede duruyorsa ArgoCD yeni bir release adıyla (`erasmus-connect`) kurulum yaparken Ingress webhook'u **`host ... and path "/" is already defined in ingress default/erasmus-erasmus-connect-ingress`** hatası verir! Bu yüzden ArgoCD'ye geçerken önce manuel Helm release'ini kaldır ki ArgoCD tek yetkili olarak temiz kurulum yapsın:
  ```bash
  helm uninstall erasmus -n default
  ```

<details>
<summary>🆘 Takılırsan Aç (Reveal): `Application` CRD Yapısal Şeması</summary>

`spec.source:` altında:
```yaml
    repoURL: https://github.com/YusufKaya00/k8s-hands-on-labs.git
    targetRevision: main
    path: projects/devops-ec-project/helm/erasmus-connect
    helm:
      valueFiles:
        - values.yaml
        - values-aks.yaml
```
`spec:` altında `syncPolicy:` ve `ignoreDifferences:`:
```yaml
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
  ignoreDifferences:
    - group: apps
      kind: Deployment
      jsonPointers:
        - /spec/replicas
```

</details>

**c) Çözüm Kanıtı (Canlı GitOps Testi!):**
```bash
# 1. Application manifestosunu kümede oluştur:
kubectl apply -f ./argocd/erasmus-app.yaml
kubectl get applications -n argocd

# 2. Otomatik Sync testi:
#    - Kümeden örneğin bir Service'i veya PDB'yi elle sil:
kubectl delete pdb erasmus-erasmus-connect-express-pdb -n default
#    - 10-15 saniye bekle ve geri geldiğini gör (selfHeal!):
kubectl get pdb -n default

# 3. Git Push testi:
#    - values.yaml içinde küçük bir değişiklik (ör. hpa maxReplicas: 4 -> 5) yapıp GitHub'a pushla.
#    - ArgoCD UI'da (http://localhost:8085) veya CLI'da birkaç dakika içinde otomatik Synced olduğunu gör!
```

---

## Faz 8: Azure Container Registry (ACR) ve Şifresiz İmaj Çekme (`AcrPull`)

Bu fazda Docker Hub ve `dockerhub-secret` bağımlılığını kaldırıp Azure'un kendi özel registry'sini (**ACR**) kuracak, AKS'in imajları **Azure Managed Identity** ile şifresiz çekmesini sağlayacaksın.

---

### Bilet 22: Terraform ile ACR Kurulumu ve `AcrPull` Rol Ataması (`acr.tf` & `outputs.tf`)

**a) Görev Tanımı:**
- [terraform/acr.tf](./terraform/acr.tf) dosyasındaki `[Bilet 22]` `# TODO` bloklarını doldur:
  1. `azurerm_container_registry.erasmus`: `Basic` SKU, `admin_enabled = false`, global olarak benzersiz **tiresiz** bir isim (ör. `acrerasmusconnectysf01`).
  2. `azurerm_role_assignment.aks_acr_pull`: AKS düğümlerinin (`kubelet_identity[0].object_id`) ACR üzerinde **`AcrPull`** yetkisi almasını sağla.
- [terraform/outputs.tf](./terraform/outputs.tf) içine `acr_login_server` çıktısını ekle.
- `terraform plan` ve `terraform apply` çalıştır.

**b) İpucu ve Referans:**
- Resmi dokümantasyon: `registry.terraform.io` üzerinde `azurerm_container_registry` ve `azurerm_role_assignment` sayfalarına bak.
- **İsim Tuzağı:** ACR adında tire (`-`), alt çizgi (`_`) veya büyük harf **olamaz**; aksi halde Azure reddeder.
- **Yetki Notu:** `azurerm_role_assignment` için Azure hesabının abonelikte `Owner` veya `User Access Administrator` yetkisine sahip olması gerekir (Azure for Students'ta varsayılan olarak açıktır).

<details>
<summary>🆘 Takılırsan Aç (Reveal): `acr.tf` Yapısal Şeması</summary>

`azurerm_container_registry`:
*(HCL sözdiziminde satır başına `- ` konmaz! Aşağıdaki maddeler sadece okuma listesidir; `.tf` dosyasına doğrudan `name = ...` şeklinde yazılır.)*
- `name = "<BENZERSIZ_KUCUK_HARF_RAKAM>"`
- `resource_group_name = azurerm_resource_group.erasmus.name`
- `location = azurerm_resource_group.erasmus.location`
- `sku = "Basic"`
- `admin_enabled = false`

`azurerm_role_assignment`:
- `principal_id = azurerm_kubernetes_cluster.erasmus.kubelet_identity[0].object_id`
- `role_definition_name = "AcrPull"`
- `scope = azurerm_container_registry.erasmus.id`
- `skip_service_principal_aad_check = true`

</details>

**c) Çözüm Kanıtı:**
```bash
cd terraform
terraform validate
terraform plan -out=tfplan   # Mevcut AKS silinmeden sadece +2 yeni kaynak (ACR + Role Assignment) görmelisin!
terraform apply tfplan
terraform output acr_login_server
```

---

### Bilet 23: İmajları ACR'ye Pushlama ve `dockerhub-secret` Olmadan ArgoCD ile Yayınlama

**a) Görev Tanımı:**
- Mevcut `backend:latest`, `frontend:aks` ve `admin:aks` imajlarını ACR login server adınla (`<ACR_NAME>.azurecr.io/...`) etiketleyip ACR'ye pushla.
- [values-aks.yaml](./helm/erasmus-connect/values-aks.yaml) içinde `express.image`, `nextjs.image` ve `admin.image` için **hem `repository` hem de `tag` (`"v1"`)** alanlarını ACR adresine göre güncelle! *(Örn: sadece `repository` değiştirip `tag`'i güncellemezsen podlar `values.yaml`'daki `:local` veya `:aks` tag'ini çekmeye çalışır ve `ImagePullBackOff` hatası alırsın. Değişiklik sonrası `helm template erasmus ./helm/erasmus-connect -f ./helm/erasmus-connect/values.yaml -f ./helm/erasmus-connect/values-aks.yaml | grep "image:"` komutuyla doğrula!)*
- Deployment şablonlarında (`express-deployment.yaml`, `nextjs-deployment.yaml`, `admin-deployment.yaml`) `imagePullSecrets` (`dockerhub-secret`) bloğunu kaldır (artık `AcrPull` sayesinde şifre gerekmiyor!) ve `kubectl delete secret dockerhub-secret -n default` ile eski secret'ı sil.
- Değişiklikleri GitHub'a pushla; ArgoCD'nin yeni `:v1` imajlarını çektiğini doğrula (`git push` sonrası ArgoCD ~3 dakika polling bekler, istersen UI'dan **Refresh -> Sync** ile anında tetikleyebilirsin).

**b) İpucu ve Referans:**
- ACR'ye Docker girişi (`az login` açıkken şifre sormaz!):
  `az acr login --name <ACR_ADIN>`
- İmaj etiketleme ve pushlama kalıbı:
  ```bash
  ACR="<ACR_ADIN>.azurecr.io"
  docker tag yusufk00/erasmus-connect-backend:latest  $ACR/erasmus-connect-backend:v1
  docker tag yusufk00/erasmus-connect-frontend:aks    $ACR/erasmus-connect-frontend:v1
  docker tag yusufk00/erasmus-connect-admin:aks       $ACR/erasmus-connect-admin:v1
  docker push $ACR/erasmus-connect-backend:v1
  docker push $ACR/erasmus-connect-frontend:v1
  docker push $ACR/erasmus-connect-admin:v1
  ```

**c) Çözüm Kanıtı:**
```bash
# 1. ACR içindeki depoları listele:
az acr repository list --name <ACR_ADIN> -o table

# 2. Git push sonrası ArgoCD Synced + Podların ACR imajlarıyla Running olduğunu doğrula:
kubectl get pods -n default -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{range .spec.containers[*]}{.image}{"\n"}{end}{end}'
```
- Pod imajlarının artık `*.azurecr.io/...:v1` olduğunu ve `dockerhub-secret` olmadan `1/1 Running` çalıştığını gör! *(Not: ACR Basic ~5$/ay yazar; işin bittiğinde `terraform destroy` ile temizlemeyi unutma.)*

---

## Faz 9: Tek Komutla Ortam Kurulumu (Sabit IP + Ansible Bootstrap) ve CI Pipeline

Bu fazda kümeyi silip sıfırdan kurduğunda ortamın (ingress, ArgoCD, uygulama) **elle müdahale olmadan** ayağa kalkmasını ve imajların **CI ile otomatik** build edilip deploy edilmesini sağlayacaksın.

---

### Bilet 24: Terraform ile Sabit Public IP ([terraform/network.tf](./terraform/network.tf))

**a) Görev Tanımı:**
- `network.tf` içindeki `# TODO` satırlarını doldur: Standard SKU + Static `azurerm_public_ip` ve AKS cluster identity'sine bu resource group üzerinde `Network Contributor` rol ataması.
- [outputs.tf](./terraform/outputs.tf) içine `ingress_public_ip` çıktısını ekle.
- **Neden?** Her yeniden kurulumda LoadBalancer yeni IP alır; `NEXT_PUBLIC_API_URL` / `VITE_BACKEND_URL` build-time gömülü olduğu için IP değişince imajları yeniden build etmen gerekir. Sabit IP bunu önler.

**b) İpucu ve Referans:**
- `registry.terraform.io` -> `azurerm_public_ip`, `azurerm_role_assignment`
- `Standard` SKU LB, `Standard` SKU public IP ister.
- AKS identity'si (`identity[0].principal_id`) başka bir resource group'taki IP'yi ancak rol alırsa kullanabilir.

**c) Çözüm Kanıtı:**
```bash
cd terraform
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
terraform output ingress_public_ip
```
- [values-aks.yaml](./helm/erasmus-connect/values-aks.yaml) içindeki `ingress.host` ve `ingress.adminHost` değerlerini bu IP'ye (`<IP>.nip.io`, `admin.<IP>.nip.io`) çevir.

---

### Bilet 25: Ansible ile Komple Ortam Kurulumu (Ingress + Secret + ArgoCD + Chaos Mesh)

**a) Görev Tanımı:**
- [playbook.yml](./ansible/playbook.yml) içindeki **ADIM 5** `# TODO` görevlerini yaz:
  1. `ingress-nginx` values'una sabit IP (`controller.service.loadBalancerIP`) ve `azure-load-balancer-resource-group` annotation'ını ekle.
  2. `argo` Helm repo + `argo/argo-cd` chart'ını `argocd` namespace'ine kur (`server.insecure=true`).
  3. [argocd/erasmus-app.yaml](./argocd/erasmus-app.yaml) dosyasını uygula (`kubernetes.core.k8s`).
  4. (Opsiyonel) Chaos Mesh Helm kurulumu.
  5. ArgoCD ilk `admin` şifresini ekrana yazdır.
- **Önemli:** Playbook artık `helm upgrade --install erasmus` yapmaz; uygulamayı **yalnızca ArgoCD** yönetir (aksi halde Ingress çakışması: `validate.nginx.ingress.kubernetes.io ... already defined`).
- **Sıra:** Secret/ConfigMap, ArgoCD'den **önce** kümeye girmeli ki podlar ayağa kalkarken `envFrom` bulabilsin.

**b) İpucu ve Referans:**
- `ansible-doc kubernetes.core.k8s`, `ansible-doc kubernetes.core.helm`
- Mevcut ADIM 1-4 görevleri örnek kalıp olarak kullanılabilir.

**c) Çözüm Kanıtı (Sıfırdan Kurulum Testi):**
```bash
cd terraform && terraform destroy && terraform apply   # kümeyi sıfırla
cd ../ansible && ansible-playbook playbook.yml
kubectl get pods -A
kubectl get applications -n argocd
curl -i -X POST http://<SABIT_IP>.nip.io/api/v1/ping
```
- Playbook tek komutla hatasız bitmeli, ArgoCD `Synced/Healthy` olmalı ve `ping` `200` dönmelidir.

---

### Bilet 26: GitHub Actions İzole AKS CI Pipeline (Build -> ACR -> GitOps Tag)

**a) Görev Tanımı:**
- Canlı uygulama reposunun (`YusufKaya00/Erasmus-Connect`) mevcut CI'ına hiç dokunmadan, doğrudan bu repoda tanımlanan [`.github/workflows/erasmus-aks-ci.yml`](../../.github/workflows/erasmus-aks-ci.yml) workflow'unu incele ([ci/README.md](./ci/README.md)).
- Bu reponun (`YusufKaya00/k8s-hands-on-labs`) GitHub Actions Secrets bölümüne şu 5 secret'ı ekle:
  - `APP_REPO_TOKEN`: `YusufKaya00/Erasmus-Connect` için `Contents: Read-only` Fine-grained PAT (repo private olduğu için)
  - `AZURE_CREDENTIALS`: ACR üzerinde `AcrPush` yetkili Service Principal JSON çıktısı
  - `ACR_NAME`: `erasmusconnectv1`
  - `FRONTEND_BUILD_ENV`: `.env.frontend-build` içeriği (`NEXT_PUBLIC_*` URL'leri Bilet 24'teki **sabit IP**'ye işaret etmeli)
  - `ADMIN_BUILD_ENV`: `VITE_BACKEND_URL=http://<SABIT_IP>.nip.io` (ve varsa diğer `VITE_*` satırları)
- GitHub'da **Actions → Erasmus Connect AKS CI → Run workflow** diyerek `service` (`backend` / `frontend` / `admin` / `all`) ve `app_ref` (`develop` = root context `.`, `main` = klasör context) seçip çalıştır.

**b) İpucu ve Referans:**
- Service Principal oluşturma:
  ```bash
  ACR_ID=$(az acr show --name erasmusconnectv1 --query id -o tsv)
  az ad sp create-for-rbac --name "sp-erasmus-acr-push" --role AcrPush --scopes "$ACR_ID" --sdk-auth
  ```
- Workflow aynı repoda çalıştığı için `values-aks.yaml` commit'inde yerleşik `GITHUB_TOKEN` (`contents: write`) kullanır; ekstra `GITOPS_TOKEN` gerekmez.
- Pipeline imajı `ACR:<app-kısa-sha>` olarak pushlar, `values-aks.yaml` tag'ini günceller ve ArgoCD `automated` sync ile AKS'e deploy eder.

**c) Çözüm Kanıtı:**
```bash
# Actions'tan workflow başarıyla bittikten sonra:
az acr repository show-tags --name erasmusconnectv1 --repository erasmus-connect-backend -o table
git pull   # Bu repoda "ci(erasmus): ... -> <sha> (develop)" commit'i gelmeli
kubectl get pods -n default -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[*].image}{"\n"}{end}'
```
- Yeni `<app-kısa-sha>` tag'li imajın podlarda `Running` çalıştığını gör.

---

## Faz 10: Observability — Prometheus, Grafana, NGINX Metrikleri ve SRE Alarmları

Bu fazda 2x `Standard_B2s` kümenin RAM ve 60 pod sınırına sığacak şekilde hafif bir **kube-prometheus-stack** kuracak, **NGINX Ingress**'ten uygulama kodu değiştirmeden HTTP RED metriklerini (Rate, Errors, Duration) toplayacak ve **PrometheusRule** ile gerçek SRE alarmları yazıp canlı test edeceksin.

---

### Bilet 27: Hafif `kube-prometheus-stack` Kurulumu ([monitoring/values-prometheus.yaml](./monitoring/values-prometheus.yaml))

**a) Görev Tanımı:**
- [monitoring/values-prometheus.yaml](./monitoring/values-prometheus.yaml) dosyasındaki `[Bilet 27]` `# TODO` kısımlarını doldur:
  1. `prometheus.prometheusSpec`: `retention: "2d"`, `scrapeInterval: "30s"`, `serviceMonitorSelectorNilUsesHelmValues: false`, `ruleSelectorNilUsesHelmValues: false` ve kaynak sınırları (`requests: 100m / 256Mi`, `limits: 500m / 600Mi`).
  2. `grafana`: `adminPassword` ve hafif `resources` (`50m / 128Mi` → `250m / 256Mi`).
  3. `alertmanager.alertmanagerSpec`: hafif `resources` (`25m / 64Mi` → `100m / 128Mi`).
- `monitoring` namespace'ine Helm ile kur (istersen sonra [ansible/playbook.yml](./ansible/playbook.yml) içine `tags: [monitoring]` olarak da ekle!).

> [!IMPORTANT]
> **Neden `serviceMonitorSelectorNilUsesHelmValues: false`?**
> Varsayılan olarak `true` gelir ve Prometheus Operator **yalnızca kendi Helm release etiketini taşıyan** `ServiceMonitor`/`PrometheusRule` nesnelerini görür. `false` yapmazsan `ingress-nginx` namespace'indeki ServiceMonitor'ü veya kendi yazdığın alarmları sessizce yok sayar!

**b) İpucu ve Referans:**
```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  -f ./monitoring/values-prometheus.yaml
```
- **Arayüzlere erişim (internete açmadan):**
  - Grafana: `kubectl port-forward svc/monitoring-grafana -n monitoring 3001:80` → `http://localhost:3001` (kullanıcı: `admin`, şifre: `values-prometheus.yaml`'da belirlediğin).
  - Prometheus: `kubectl port-forward svc/monitoring-kube-prometheus-prometheus -n monitoring 9090:9090` → `http://localhost:9090`.
  - Alertmanager: `kubectl port-forward svc/monitoring-kube-prometheus-alertmanager -n monitoring 9093:9093` → `http://localhost:9093`.

**c) Çözüm Kanıtı:**
```bash
kubectl get pods -n monitoring
kubectl top nodes   # RAM %85'in altında ve tüm podlar Running olmalı
```

---

### Bilet 28: NGINX Ingress RED Metrikleri (`ServiceMonitor`) ve Grafana Dashboard

**a) Görev Tanımı:**
- [ansible/playbook.yml](./ansible/playbook.yml) içindeki `NGINX Ingress Controller to AKS` görevinin `values.controller:` altına `metrics` bloğunu ekle ve `ansible-playbook playbook.yml --tags ingress` ile uygula:
  - `metrics.enabled: true`
  - `metrics.serviceMonitor.enabled: true`
- Prometheus arayüzünde (**Status → Targets**) `ingress-nginx` hedefinin **`UP`** olduğunu doğrula.
- Grafana'da hazır **NGINX Ingress Controller** panosunu (**Dashboards → Import → ID: `9614`** veya **`14314`**) içeri aktar.

**b) İpucu ve Referans:**
- Prometheus Graph (`http://localhost:9090/graph`) ekranında şu 3 PromQL sorgusunu çalıştırıp anla:
  - **Saniyelik İstek (RPS):** `sum(rate(nginx_ingress_controller_requests[5m])) by (host, status)`
  - **p95 Yanıt Süresi:** `histogram_quantile(0.95, sum(rate(nginx_ingress_controller_request_duration_seconds_bucket[5m])) by (le, ingress))`
  - **Default Namespace Pod RAM Kullanımı:** `sum(container_memory_working_set_bytes{namespace="default", container!=""}) by (pod)`

**c) Çözüm Kanıtı:**
```bash
kubectl get servicemonitor -n ingress-nginx
# Trafik üret ve Grafana + Prometheus'ta grafiğin yükseldiğini gör:
for i in $(seq 1 30); do curl -s -o /dev/null -X POST http://9.205.93.250.nip.io/api/v1/ping; done
```

---

### Bilet 29: Özel SRE Alarmları (`PrometheusRule`) ve Canlı Alarm Testi

**a) Görev Tanımı:**
- [monitoring/prometheus-rules.yaml](./monitoring/prometheus-rules.yaml) dosyasındaki 3 `[Bilet 29]` `# TODO` alarm kuralını (`ErasmusExpressDown`, `ErasmusPodCrashLooping`, `ErasmusHigh5xxRate`) `kubectl explain prometheusrule.spec.groups.rules` çıktısına göre doldur ve kümeye uygula.
- **Canlı Alarm Testi (Game Day):** Express'i geçici olarak boz veya ölçeğini `0` yap (ya da Chaos Mesh `01-pod-kill-express.yaml` çalıştır), Prometheus **Alerts** ekranında (`http://localhost:9090/alerts`) alarmın `INACTIVE → PENDING → FIRING` geçişini ve **Alertmanager** (`http://localhost:9093`) ekranına düştüğünü canlı gözlemle!

> [!WARNING]
> **ArgoCD `selfHeal` Notu:** Express Deployment'ını elle `kubectl scale ... --replicas=0` yapsan da ArgoCD `ignoreDifferences: /spec/replicas` sayesinde dokunmaz — ancak **HPA** (`minReplicas: 2`) ~15 saniye içinde replikayı tekrar 2'ye çıkarır! `ErasmusExpressDown` alarmını canlı test etmek istersen geçici olarak HPA'yı durdurabilir (`kubectl patch hpa ...`) veya yanlış bir endpoint/port üzerinden 5xx/restart tetikleyebilirsin; test bitince geri almayı unutma!

**b) İpucu ve Referans:**
- `kubectl explain prometheusrule.spec.groups.rules`
- `kubectl apply -f ./monitoring/prometheus-rules.yaml`
- `kubectl get prometheusrule -n monitoring`

**c) Çözüm Kanıtı:**
```bash
kubectl get prometheusrule erasmus-connect-alerts -n monitoring
# Prometheus UI -> Alerts sayfasında 3 kuralın (ErasmusExpressDown, ErasmusPodCrashLooping, ErasmusHigh5xxRate) yüklendiğini ve en az 1 tanesinin test sırasında FIRING olduğunu doğrula!
```

---

## Kontrol Listesi (Kendini Değerlendir)

- [ ] Hiçbir şifre/connection string Git'e girmedi: değerler `.env.*` dosyalarında, kümede Secret/ConfigMap olarak duruyor; chart sadece isimlerini biliyor.
- [ ] `express-deployment.yaml` ve `nextjs-deployment.yaml` podları `0.0.0.0` dinliyor ve `containerPort` ile Service `targetPort` eşleşiyor.
- [ ] Redis `StatefulSet` ve `Headless Service` (`clusterIP: None`) kararlı DNS ile çalışıyor.
- [ ] Tüm podların `requests` ve `limits` değerleri `Standard_B2s` node kapasitesine sığıyor.
- [ ] Next.js podu Redis `6379` portuna ulaşamıyor (Calico engelliyor), sadece Express podu ulaşabiliyor.
- [ ] Express `NetworkPolicy` kuralı **Post-DNAT** gerçekliğini (pod `containerPort` + Ingress `namespaceSelector`) doğru yansıtıyor.
- [ ] Ortam silinip tek `terraform apply` + `ansible-playbook` ile sıfırdan kuruluyor; Ingress IP'si sabit kalıyor.
- [ ] GitHub Actions CI imajı ACR'ye pushluyor -> `values-aks.yaml` tag'i güncelleniyor -> ArgoCD otomatik deploy ediyor.
- [ ] Prometheus + Grafana çalışıyor, NGINX Ingress `ServiceMonitor` `UP`, özel `PrometheusRule` alarmları doğrulandı.
- [ ] `terraform destroy` veya `az aks stop` ile gereksiz bulut maliyeti önlendi.

---

<a id="-english-section"></a>
## 🇬🇧 English Section — Step-by-Step Setup & 10-Phase DevOps Lab Roadmap

This guide walks through building **Erasmus Connect** (**Next.js** frontend, **Vite/Nginx** admin SPA, **Express** backend, **Redis** cache, external **MongoDB Atlas** & **Supabase**) from local **Minikube + Calico** all the way to **Azure AKS + Terraform + Ansible + ArgoCD GitOps + ACR + GitHub Actions CI + Prometheus/Grafana Observability** across **10 Phases (29 Tickets)**:

### Phases Overview
1. **Phases 1–2 — Containerization & Helm Chart Packaging:** Package Express (`:4000`), Next.js (`:3000`, `HOSTNAME=0.0.0.0`), Admin SPA (`:80`), and Redis (`StatefulSet` + Headless `Service`, `clusterIP: None`) under [`helm/erasmus-connect/`](./helm/erasmus-connect/). Keep secrets out of Git using `.env.*` -> Kubernetes `Secret` & `ConfigMap` (`envFrom`), add resource requests/limits and `readinessProbe`/`livenessProbe`.
2. **Phase 3 — NGINX Ingress & Zero-Trust Post-DNAT Calico Policies:** Configure host/path routing (`/`, `/api`, `admin.*`) via `ingress-nginx`. Enforce **Post-DNAT Calico `NetworkPolicy`** rules targeting Pod `containerPort` (`4000` / `6379`) and `ingress-nginx` `namespaceSelector` so Redis accepts only Express and Express accepts only Ingress + Next.js.
3. **Phases 4–5 — Azure AKS Provisioning (Terraform) & Automated Bootstrap (Ansible):** Provision AKS (`Standard_B2s`, `Azure CNI` + `Calico`) in `DenmarkEast` via [`terraform/`](./terraform/main.tf). Run [`ansible/playbook.yml`](./ansible/playbook.yml) to fetch `kubeconfig`, deploy `ingress-nginx` with `service.beta.kubernetes.io/azure-load-balancer-health-probe-request-path: "/healthz"`, and create ConfigMaps/Secrets from `.env.*`.
4. **Phase 6 — High Availability & Chaos Engineering:** Enforce CPU **HPA** (`2–4` replicas @ `60%` CPU), **PodDisruptionBudget (`minAvailable: 1`)**, and run **Chaos Mesh** experiments under [`chaos/`](./chaos/01-pod-kill-express.yaml) (pod kill, Redis network delay, Express CPU stress).
5. **Phase 7 — Node Scaling & ArgoCD GitOps Migration:** Scale AKS `node_count` from `1 -> 2` in Terraform (overcoming the 30-pods-per-node Azure CNI cap), remove manual Helm releases to avoid NGINX ingress admission ownership conflicts, and onboard [`argocd/erasmus-app.yaml`](./argocd/erasmus-app.yaml) with `prune: true`, `selfHeal: true`, and `ignoreDifferences` on `/spec/replicas`.
6. **Phase 8 — Passwordless Azure Container Registry (`ACR`) + Managed Identity:** Provision ACR (`Basic`, `admin_enabled = false`) via [`terraform/acr.tf`](./terraform/acr.tf), assign the **`AcrPull`** RBAC role to the AKS `kubelet_identity`, push images (`values-aks.yaml`), and remove `imagePullSecrets` (`dockerhub-secret`).
7. **Phase 9 — One-Command Environment Rebuild & Isolated GitHub Actions CI:** Reserve a static Standard Public IP in [`terraform/network.tf`](./terraform/network.tf), bootstrap Ingress + Secrets + ArgoCD in [`ansible/playbook.yml`](./ansible/playbook.yml), and trigger [`.github/workflows/erasmus-aks-ci.yml`](../../.github/workflows/erasmus-aks-ci.yml) to build from `YusufKaya00/Erasmus-Connect`, push to ACR, and commit image tag bumps for ArgoCD.
8. **Phase 10 — Observability (Prometheus, Grafana, NGINX Metrics & SRE Alerts):** Deploy a tuned `kube-prometheus-stack` ([`monitoring/values-prometheus.yaml`](./monitoring/values-prometheus.yaml)), scrape NGINX Ingress RED metrics via `ServiceMonitor`, visualize traffic in Grafana, and verify custom alerts in [`monitoring/prometheus-rules.yaml`](./monitoring/prometheus-rules.yaml).

### Verification Checklist
- [ ] Zero secrets/connection strings committed to Git (`.env.*` and `terraform.tfvars` gitignored).
- [ ] Containers bind to `0.0.0.0`, and `Service.targetPort` matches `containerPort`.
- [ ] Redis `StatefulSet` + Headless Service resolves cleanly via DNS.
- [ ] `NetworkPolicy` isolates Redis (`:6379`) exclusively to Express and enforces Post-DNAT rules on `:4000`.
- [ ] ArgoCD syncs from ACR without `imagePullSecrets` and preserves HPA replica counts.
- [ ] Full cluster rebuild via `terraform apply` + `ansible-playbook` preserves the static Ingress IP.
- [ ] GitHub Actions CI builds & pushes to ACR and updates `values-aks.yaml` for ArgoCD auto-sync.
- [ ] Prometheus/Grafana running within node capacity, NGINX `ServiceMonitor` `UP`, and custom `PrometheusRule` alerts verified.
- [ ] Cluster stopped (`az aks stop`) or destroyed (`terraform destroy`) after verification to prevent idle cloud spend.
