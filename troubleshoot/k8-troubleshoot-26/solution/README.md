# NetVortex v9.0 — Solution Guide

> **[🇹🇷 Türkçe](#-türkçe)** | **[🇬🇧 English](#-english)**

---

<a id="-türkçe"></a>
## 🇹🇷 Türkçe

Bu dizin, NetVortex v9.0 ağ arızalarının tamamını çözen referans `values-solution.yaml` dosyasını içerir.

### Çözümü Uygulama

```bash
# 1. NetVortex release'ini düzeltilmiş konfigürasyon ile güncelleyin:
helm upgrade --install netvortex ./helm/netvortex \
  -n netvortex-edge \
  -f ./solution/values-solution.yaml

# 2. StatefulSet tanımı değiştiğinde (spec.serviceName güncellendiğinde) mevcut StatefulSet podunu yeniden başlatın:
kubectl delete sts ledger-db -n netvortex-data --cascade=orphan 2>/dev/null || true
helm upgrade --install netvortex ./helm/netvortex \
  -n netvortex-edge \
  -f ./solution/values-solution.yaml

# 3. Kontrol scripti ile tüm ağ testlerini doğrulayın:
./check.sh
```

Ayrıntılı kök neden analizi, L4/L7 paket akışları ve teknik açıklamalar için ana dizindeki [SOLUTION.md](../SOLUTION.md) dosyasını inceleyin.

---

<a id="-english"></a>
## 🇬🇧 English

This directory provides the reference `values-solution.yaml` that resolves all NetVortex v9.0 networking and zero-trust outages.

### Applying the Solution

```bash
# 1. Upgrade the NetVortex release using the fixed solution values:
helm upgrade --install netvortex ./helm/netvortex \
  -n netvortex-edge \
  -f ./solution/values-solution.yaml

# 2. Re-create the StatefulSet to adopt the updated spec.serviceName:
kubectl delete sts ledger-db -n netvortex-data --cascade=orphan 2>/dev/null || true
helm upgrade --install netvortex ./helm/netvortex \
  -n netvortex-edge \
  -f ./solution/values-solution.yaml

# 3. Run the verification script:
./check.sh
```

For comprehensive root cause analysis, L4/L7 packet traces, and networking internals, refer to [SOLUTION.md](../SOLUTION.md).
