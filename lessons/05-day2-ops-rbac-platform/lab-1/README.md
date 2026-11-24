# Ders 05 / Lab 1 — Service Mesh (Istio mTLS & Canary) & Day-2 Ops RBAC Playground

> **[🇹🇷 Türkçe](#-türkçe-bölüm) | [🇬🇧 English](#-english-section)**  
> **Ortam / Runtime:** %100 Yerel Minikube (`-p mesh-lab-1`, `$0`) · **Mod:** Arıza labı değil — Istio Service Mesh ve Day-2 Ops kavramlarını canlı uygulayarak öğreneceğin **sağlıklı çalışma ortamı (Sandbox)**

---

<a id="-türkçe-bölüm"></a>
## 🇹🇷 Türkçe Bölüm

### 🧠 Konu Anlatımı: Sektörde Neler Var, Hangi Sorunu Çözer?

#### 1. Service Mesh Nedir? (Ingress / Reverse Proxy ile Farkı Ne?)
- **Ingress (NGINX / ALB / Traefik):** **North-South** trafiği (dış dünyadan cluster'a gelen istekleri) yönetir.
- **Service Mesh (Istio / Linkerd / Cilium):** **East-West** trafiğini (cluster içindeki **mikroservislerin birbirleriyle konuşmasını**) yönetir.
- **Hangi 3 büyük sorunu çözer?**
  1. **Zero-Trust mTLS Şifreleme:** Normalde K8s'te Pod A → Pod B trafiği şifresiz (`HTTP`) gider. Service Mesh, uygulama koduna tek satır yazmadan tüm pod'lar arası trafiği otomatik **karşılıklı TLS (mTLS)** ile şifreler ve kimlik doğrular (`SPIFFE` sertifikası).
  2. **Akıllı Trafik Yönetimi (Canary / Header Routing / Retry):** Standart K8s `Service` sadece replica sayısına göre kaba yük dağıtır. Service Mesh ile trafiğin tam **%80'ini `v1`'e, %20'sini `v2`'ye** gönderebilir veya `x-user: beta` header'ı taşıyan kullanıcıları doğrudan `v2`'ye yönlendirebilirsin.
  3. **L7 Yetkilendirme (`AuthorizationPolicy`):** Standart `NetworkPolicy` sadece L3/L4 (IP + Port) bilir. Service Mesh ise *"sadece `client-sa` servisi `reviews` servisine **`GET`** atabilsin, **`POST`/`DELETE`** atamasın"* diyebilir.

#### 2. Sektördeki Service Mesh Karşılaştırması
| Araç | Mimari | Sektörde Nerede Kullanılır? |
|---|---|---|
| **Istio (Sidecar)** | Her pod'un yanına **Envoy** sidecar ekler (`2/2 Ready`). | En yaygın kurumsal standart; zengin trafik ve güvenlik özellikleri. |
| **Istio Ambient Mesh** | **Sidecar-less:** Node başına hafif Rust **Ztunnel** (L4 mTLS) + gerekirse **Waypoint Proxy** (L7). | Sidecar RAM/CPU maliyetini azaltmak isteyen modern kurulumlar. |
| **Linkerd** | Ultra hafif Rust proxy (`linkerd2-proxy`). | "Basit olsun, en az kaynak tüketsin, hızlı mTLS versin" diyen ekipler. |
| **Cilium Service Mesh** | eBPF tabanlı CNI + Mesh bir arada. | Yüksek performanslı kernel seviyesi ağ + gözlemlenebilirlik (**Hubble**). |

#### 3. Day-2 Ops & Multi-Team RBAC Nedir?
- **Day-0:** Mimari tasarım · **Day-1:** Cluster kurulumu (Terraform/Ansible) · **Day-2:** Yaşayan cluster'ı kesintisiz işletmek (RBAC, zero-downtime upgrade, PDB, otomatik kurtarma, **Blameless Post-Mortem**).
- Çoklu takımlı bir cluster'da geliştiricilere `cluster-admin` verilmez; her takıma kendi namespace'inde **en az yetki (Least-Privilege)** `Role` / `RoleBinding` tanımlanır ve `kubectl auth can-i --as=...` ile doğrulanır.

---

### 🚀 Kurulum

```bash
cd lessons/05-day2-ops-rbac-platform/lab-1
./setup.sh
```

---

### Adım 1 — Otomatik Envoy Sidecar Enjeksiyonunu Gör (`2/2 Ready`)

`mesh-demo` namespace'inde `istio-injection: enabled` etiketi olduğu için Istio her pod'a otomatik `istio-proxy` (Envoy) container'ı ekledi:

```bash
kubectl --context mesh-lab-1 -n mesh-demo get pods
# Tüm pod'larda READY 2/2 görünmeli!

# İçindeki 2 container'ı (uygulama + istio-proxy) gör:
kubectl --context mesh-lab-1 -n mesh-demo get pod -l app=reviews,version=v1 -o jsonpath='{.items[0].spec.containers[*].name}'; echo ""
```

---

### Adım 2 — Canary Trafik Bölme (%80 `v1` / %20 `v2`) & Header Routing

Önce kural yokken `client` pod'undan `reviews` servisine 10 istek at (K8s Service ~%50/%50 dağıtır):
```bash
for i in $(seq 1 10); do
  kubectl --context mesh-lab-1 -n mesh-demo exec deploy/client -c client -- curl -s http://reviews:8080/
  echo ""
done
```

Şimdi [manifests/canary-80-20.yaml](./manifests/canary-80-20.yaml) (`DestinationRule` + `VirtualService`) uygula ve farkı gör:
```bash
kubectl --context mesh-lab-1 apply -f manifests/canary-80-20.yaml

# 1. Normal trafik -> ağırlıklı olarak v1 (%80) ve arada v2-canary (%20) gelecek:
for i in $(seq 1 10); do
  kubectl --context mesh-lab-1 -n mesh-demo exec deploy/client -c client -- curl -s http://reviews:8080/
  echo ""
done

# 2. Beta kullanıcısı header'ı (x-user: beta) -> %100 v2-canary'ye gider!
kubectl --context mesh-lab-1 -n mesh-demo exec deploy/client -c client -- \
  curl -s -H "x-user: beta" http://reviews:8080/; echo ""
```

---

### Adım 3 — Zero-Trust: `STRICT` mTLS & L7 `AuthorizationPolicy`

[manifests/mtls-and-authz.yaml](./manifests/mtls-and-authz.yaml) iki kural uygular:
- `PeerAuthentication (STRICT)`: `mesh-demo` içinde şifresiz (plain HTTP) trafik yasaklanır, tüm pod'lar arası trafik otomatik mTLS olur.
- `AuthorizationPolicy`: `reviews` servisine sadece `client-sa` kimliğiyle ve **sadece `GET`** metoduyla erişime izin verir (`POST` reddedilir!).

```bash
kubectl --context mesh-lab-1 apply -f manifests/mtls-and-authz.yaml

# 1. GET isteği -> 200 OK (izinli):
kubectl --context mesh-lab-1 -n mesh-demo exec deploy/client -c client -- \
  curl -i -s http://reviews:8080/

# 2. POST isteği -> 403 Forbidden (RBAC: access denied — Istio L7 katmanında engelledi!):
kubectl --context mesh-lab-1 -n mesh-demo exec deploy/client -c client -- \
  curl -i -s -X POST http://reviews:8080/
```

---

### Adım 4 — Day-2 Ops: En Az Yetki (Least-Privilege) RBAC Doğrulama

[manifests/rbac-multi-team.yaml](./manifests/rbac-multi-team.yaml) ile `dev-readonly-sa` için sadece `pods`, `pods/log`, `services` okuma yetkisi tanımla ve `kubectl auth can-i --as=...` ile test et:

```bash
kubectl --context mesh-lab-1 apply -f manifests/rbac-multi-team.yaml

# Pod listeleyebilir mi? -> yes
kubectl --context mesh-lab-1 auth can-i list pods -n mesh-demo \
  --as=system:serviceaccount:mesh-demo:dev-readonly-sa

# Secret okuyabilir mi? -> no
kubectl --context mesh-lab-1 auth can-i get secrets -n mesh-demo \
  --as=system:serviceaccount:mesh-demo:dev-readonly-sa

# Pod silebilir mi? -> no
kubectl --context mesh-lab-1 auth can-i delete pods -n mesh-demo \
  --as=system:serviceaccount:mesh-demo:dev-readonly-sa
```

---

### 🧹 Temizlik

```bash
./cleanup.sh
```

---

<a id="-english-section"></a>
## 🇬🇧 English Section

### 🎯 What Is Included?
A clean, healthy **100% local Minikube (`-p mesh-lab-1`, `$0`)** hands-on playground (not a broken troubleshooting lab) covering:
- **Istio Service Mesh (`istio-system`):** Official `istio/base` + `istio/istiod` Helm install with automatic Envoy sidecar injection (`2/2 Ready`) in `mesh-demo`.
- **Traffic Engineering (`manifests/canary-80-20.yaml`):** 80/20 weighted Canary split between `reviews-v1` and `reviews-v2` + `x-user: beta` header routing.
- **Zero-Trust Security (`manifests/mtls-and-authz.yaml`):** `STRICT` mTLS `PeerAuthentication` + L7 `AuthorizationPolicy` allowing only `GET` from `client-sa` and returning `403 RBAC: access denied` for `POST`.
- **Day-2 Ops Multi-Team RBAC (`manifests/rbac-multi-team.yaml`):** Least-privilege `Role`/`RoleBinding` verified via `kubectl auth can-i --as=...`.

### 🚀 Quick Start

```bash
cd lessons/05-day2-ops-rbac-platform/lab-1
./setup.sh
```

Follow Steps 1–4 above and tear down anytime with `./cleanup.sh`.
