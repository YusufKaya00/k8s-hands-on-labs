[🇹🇷 Türkçe](#-türkçe) | [🇬🇧 English](#-english)

---

# 🇹🇷 Türkçe

Bu klasör **NovaMesh v12.0 (Lab 29)** için tüm 10 ağ arızasının düzeltilmiş Helm values dosyasını (`values-solution.yaml`) içerir.

Ayrıntılı kök neden analizleri için üst dizindeki [SOLUTION.md](../SOLUTION.md) dosyasına bakın.

### Hızlı Çözüm Uygulaması

```bash
INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
helm upgrade novamesh ../helm/novamesh \
  --namespace novamesh-edge \
  -f ./values-solution.yaml \
  --set global.ingressHost="novamesh.${INGRESS_IP}.nip.io"

cd .. && ./check.sh
```

---

# 🇬🇧 English

This directory contains the corrected Helm values file (`values-solution.yaml`) resolving all 10 networking issues in **NovaMesh v12.0 (Lab 29)**.

See [SOLUTION.md](../SOLUTION.md) in the parent directory for detailed root-cause explanations and manual `kubectl` commands.

### Apply Full Solution

```bash
INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
helm upgrade novamesh ../helm/novamesh \
  --namespace novamesh-edge \
  -f ./values-solution.yaml \
  --set global.ingressHost="novamesh.${INGRESS_IP}.nip.io"

cd .. && ./check.sh
```
