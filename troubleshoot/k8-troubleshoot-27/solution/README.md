# CloudApex v10.0 — Solution Guide

> **[🇹🇷 Türkçe](#-türkçe)** | **[🇬🇧 English](#-english)**

---

<a id="-türkçe"></a>
## 🇹🇷 Türkçe

Bu dizin, CloudApex v10.0 kurumsal ağ ve Azure LoadBalancer arızalarının tamamını çözen referans `values-solution.yaml` dosyasını içerir.

### Çözümü Uygulama

```bash
# 1. Ingress IP'sini alın:
INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# 2. CloudApex release'ini düzeltilmiş konfigürasyon ile güncelleyin:
helm upgrade --install cloudapex ./helm/cloudapex \
  -n cloudapex-edge \
  --set global.ingressHost="cloudapex.${INGRESS_IP}.nip.io" \
  -f ./solution/values-solution.yaml

# 3. StatefulSet tanımı değiştiğinde (spec.serviceName güncellendiğinde) mevcut StatefulSet podunu yeniden başlatın:
kubectl delete sts inventory-cache -n cloudapex-inventory --cascade=orphan 2>/dev/null || true
helm upgrade --install cloudapex ./helm/cloudapex \
  -n cloudapex-edge \
  --set global.ingressHost="cloudapex.${INGRESS_IP}.nip.io" \
  -f ./solution/values-solution.yaml

# 4. Kontrol scripti ile tüm ağ testlerini doğrulayın:
./check.sh
```

Ayrıntılı kök neden analizi, L4/L7 paket akışları ve teknik açıklamalar için ana dizindeki [SOLUTION.md](../SOLUTION.md) dosyasını inceleyin.

---

<a id="-english"></a>
## 🇬🇧 English

This directory provides the reference `values-solution.yaml` that resolves all CloudApex v10.0 enterprise networking and Azure LoadBalancer outages.

### Applying the Solution

```bash
# 1. Retrieve the Ingress Public IP:
INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# 2. Upgrade the CloudApex release using the fixed solution values:
helm upgrade --install cloudapex ./helm/cloudapex \
  -n cloudapex-edge \
  --set global.ingressHost="cloudapex.${INGRESS_IP}.nip.io" \
  -f ./solution/values-solution.yaml

# 3. Re-create the StatefulSet to adopt the updated spec.serviceName:
kubectl delete sts inventory-cache -n cloudapex-inventory --cascade=orphan 2>/dev/null || true
helm upgrade --install cloudapex ./helm/cloudapex \
  -n cloudapex-edge \
  --set global.ingressHost="cloudapex.${INGRESS_IP}.nip.io" \
  -f ./solution/values-solution.yaml

# 4. Run the verification script:
./check.sh
```

For comprehensive root cause analysis, L4/L7 packet traces, and networking internals, refer to [SOLUTION.md](../SOLUTION.md).
