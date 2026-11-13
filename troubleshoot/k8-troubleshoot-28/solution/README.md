# FinEdge v11.0 — Solution Guide

> **[🇹🇷 Türkçe](#-türkçe)** | **[🇬🇧 English](#-english)**

---

<a id="-türkçe"></a>
## 🇹🇷 Türkçe

Bu dizin, FinEdge v11.0 kurumsal ağ ve canlı üretim arızalarının tamamını çözen referans `values-solution.yaml` dosyasını içerir.

### Çözümü Uygulama

```bash
# 1. Ingress IP'sini alın:
INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# 2. clusterIP alanı immutable olduğu için Headless olması gereken servisi silin:
kubectl delete svc ledger-headless -n finedge-ledger --ignore-not-found=true

# 3. FinEdge release'ini düzeltilmiş konfigürasyon ile güncelleyin:
helm upgrade --install finedge ./helm/finedge \
  -n finedge-edge \
  --set global.ingressHost="finedge.${INGRESS_IP}.nip.io" \
  -f ./solution/values-solution.yaml

# 4. Canlı HTTP uç noktalarını ve ağ denetimini doğrulayın:
./check.sh
```

Ayrıntılı kök neden analizi, paket izleme adımları ve teknik açıklamalar için ana dizindeki [SOLUTION.md](../SOLUTION.md) dosyasını inceleyin.

---

<a id="-english"></a>
## 🇬🇧 English

This directory provides the reference `values-solution.yaml` that resolves all FinEdge v11.0 production Kubernetes networking and cloud LoadBalancer outages.

### Applying the Solution

```bash
# 1. Retrieve the Ingress Public IP:
INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# 2. Delete ledger-headless Service because spec.clusterIP is immutable:
kubectl delete svc ledger-headless -n finedge-ledger --ignore-not-found=true

# 3. Upgrade the FinEdge release using the fixed solution values:
helm upgrade --install finedge ./helm/finedge \
  -n finedge-edge \
  --set global.ingressHost="finedge.${INGRESS_IP}.nip.io" \
  -f ./solution/values-solution.yaml

# 4. Run the live end-to-end verification script:
./check.sh
```

For comprehensive root cause analysis and networking internals, refer to [SOLUTION.md](../SOLUTION.md).
