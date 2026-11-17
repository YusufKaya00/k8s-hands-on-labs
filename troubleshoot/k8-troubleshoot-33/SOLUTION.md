[🇹🇷 Türkçe](#-türkçe-çözüm-rehberi) | [🇬🇧 English](#-english-solution-guide)

---

# 🇹🇷 Türkçe Çözüm Rehberi

Bu doküman **MeridianPay v16.0 (Lab 33)** içerisindeki 10 karışık genel tekrar biletinin kök nedenlerini ve çözümlerini içerir.

> [!TIP]
> Tüm çözümleri Helm üzerinden tek seferde uygulamak için (dikkat: Bilet 7 ve 10 için immutable `PVC` ve `StatefulSet` önce silinmelidir):
> ```bash
> kubectl delete pvc invoice-archive-pvc -n meridian-core --ignore-not-found=true
> kubectl delete sts cache-db -n meridian-data --ignore-not-found=true
> INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
> helm upgrade meridianpay ./helm/meridianpay \
>   -f ./solution/values-solution.yaml \
>   --set global.ingressHost="meridian.${INGRESS_IP}.nip.io"
> ./check.sh
> ```

---

## Bilet 1 — Yanlış `ingressClassName` (`meridian-payments-ingress`)
* **Katman:** Ağ / NGINX Ingress
* **Teşhis:** `kubectl get ingress -A` çıktısında `meridian-payments-ingress` `CLASS: external-lb` ve boş `ADDRESS` ile görünür.
* **Çözüm:** `ingress.paymentsIngressClassName` değerini `"nginx"` yapın.

## Bilet 2 — Egress NetworkPolicy İçinde CoreDNS (`:53`) Eksik (`risk-gateway-netpol`)
* **Katman:** Ağ / Calico Egress NetworkPolicy + CoreDNS
* **Teşhis:** `risk-gateway` içinden `risk-engine` Pod IP'si çalışırken `nslookup risk-engine.meridian-data.svc.cluster.local` başarısız olur (`timed out`). `risk-gateway-netpol` yalnızca `TCP 8082` çıkışına izin verir.
* **Çözüm:** Politikayı **silmeden** `riskGateway.networkPolicy.egressRules` altına `kube-system` (`k8s-app: kube-dns`) için `UDP 53` ve `TCP 53` izni ekleyin.

## Bilet 3 — Service Named `targetPort` Uyuşmazlığı (`fx-service`)
* **Katman:** Ağ / Service & Endpoints
* **Teşhis:** Pod `1/1 Running` ama `kubectl get ep fx-service -n meridian-core` boş/uyumsuz görünür; Service `targetPort: grpc-web` isterken Deployment port adı `http-api`'dir.
* **Çözüm:** `fxService.service.targetPort` değerini `"http-api"` (veya `8083`) yapın.

## Bilet 4 — Reverse Proxy `proxy_read_timeout` Çok Kısa (`edge-proxy-conf`)
* **Katman:** Ağ / NGINX Reverse Proxy
* **Teşhis:** `edge-proxy` podu içinden `wget -qO- -T 5 http://slow-reporter.meridian-core.svc.cluster.local:8084/api/reports/slow` `2.5s` sonra `200 OK` döner (NetPol yok), ancak `edge-proxy-conf` içinde `/api/reports` için `proxy_read_timeout 1s;` tanımlıdır.
* **Çözüm:** `edgeProxy.reportsReadTimeout` değerini `"5s"` yapın (ConfigMap elle düzenlenirse `kubectl rollout restart deploy/edge-proxy -n meridian-edge` çalıştırın).

## Bilet 5 — Ortam Değişkeni Önceliği: `env` vs `envFrom` (`billing-api`)
* **Katman:** Uygulama Konfigürasyonu (`env` override)
* **Teşhis:** `billing-config` ConfigMap içinde `VAULT_URL` doğru FQDN (`http://vault-core.meridian-data.svc.cluster.local:8086/verify`) olarak yazılıdır; ancak `billing-api` Deployment'ındaki açık `env:` bloğu `VAULT_URL`'yi eksik kısa adla (`http://vault-core:8086/verify`) ezmektedir.
* **Çözüm:** `billingApi.overrideVaultUrl` değerini `""` yapın (veya Deployment'tan hatalı `env` override'ını kaldırın).

## Bilet 6 — `OOMKilled` (`Exit Code 137` / Yetersiz Memory Limit) (`fraud-checker`)
* **Katman:** Uygulama Runtime & Kaynak Limitleri
* **Teşhis:** `kubectl get pods -n meridian-core` çıktısında `fraud-checker` `OOMKilled` / `CrashLoopBackOff` gösterir. `kubectl describe pod` altında `Last State: Terminated, Reason: OOMKilled, Exit Code: 137` görülür (`limits.memory: 24Mi` iken uygulama `32 MiB` önbellek ayırır).
* **Çözüm:** `fraudChecker.resources.limits.memory` değerini `"128Mi"` (`requests.memory: "48Mi"`) yapın.

## Bilet 7 — Immutable `PVC` `AccessMode: ReadWriteMany` Hatası on `managed-csi` (`invoice-archive-pvc`)
* **Katman:** Depolama (`PVC` / Azure Disk CSI)
* **Teşhis:** `kubectl describe pvc invoice-archive-pvc -n meridian-core` içinde Azure Disk (`managed-csi`) sürücüsünün `ReadWriteMany` desteklemediği görülür.
* **Çözüm:** `invoiceArchiver.storage.accessMode` değerini `"ReadWriteOnce"` yapın, ardından immutable eski PVC'yi silip Helm upgrade çalıştırın:
  ```bash
  kubectl delete pvc invoice-archive-pvc -n meridian-core
  ```

## Bilet 8 — Pod Üzerinde `serviceAccountName` Unutulmuş (`audit-collector`)
* **Katman:** Güvenlik / RBAC
* **Teşhis:** `kubectl logs deploy/audit-collector -n meridian-core` çıktısında `403 Forbidden` görülür (`events` kaynağı `default` SA'ya yasaktır). `meridian-core` içinde `audit-collector-sa` ve `Role`/`RoleBinding` zaten tanımlıdır ama Deployment `serviceAccountName` belirtmediği için `default` SA ile açılmaktadır.
* **Çözüm:** `auditCollector.serviceAccountName` değerini `"audit-collector-sa"` yapın.

## Bilet 9 — `ResourceQuota` Aşımı (`session-api` `0/1` Pod Yok)
* **Katman:** Kota & Zamanlama (`ResourceQuota` / `ReplicaSet`)
* **Teşhis:** `kubectl get deploy,rs,pods,resourcequota -n meridian-data` çıktısında `session-api` `0/1` görünür ama pod yoktur. `kubectl describe rs -n meridian-data` Events altında `exceeded quota: data-resource-quota` (`requests.memory=512Mi`, kota sınırı `256Mi`, kullanılan `144Mi`) yazar.
* **Çözüm:** Kotayı **silmeden** `sessionApi.resources.requests.memory` değerini `"48Mi"` (`limits.memory: "128Mi"`) yapın (veya `data-resource-quota` sınırını makul seviyeye yükseltin).

## Bilet 10 — Immutable `StatefulSet` `spec.serviceName` Headless DNS Uyuşmazlığı (`cache-db`)
* **Katman:** StatefulSet & Headless CoreDNS
* **Teşhis:** `cache-proxy` logunda/yanıtında `cache-db-0.cache-headless.meridian-data.svc.cluster.local` çözülemediği görünür. `kubectl get sts cache-db -n meridian-data -o yaml` içinde `serviceName: cache-internal` yazılıdır, oysa Headless Service adı `cache-headless`'tır.
* **Çözüm:** `cacheDb.statefulSetServiceName` değerini `"cache-headless"` yapın ve **immutable** olan eski StatefulSet'i silip Helm upgrade çalıştırın:
  ```bash
  kubectl delete sts cache-db -n meridian-data
  ```

---

# 🇬🇧 English Solution Guide

1. **Ticket 1 (`meridian-payments-ingress`):** Set `ingress.paymentsIngressClassName` from `"external-lb"` to `"nginx"`.
2. **Ticket 2 (`risk-gateway-netpol`):** Add `kube-system` (`k8s-app: kube-dns`, `UDP/TCP 53`) egress rule without deleting the NetworkPolicy.
3. **Ticket 3 (`fx-service`):** Fix Service `targetPort` from `"grpc-web"` to `"http-api"` (or `8083`).
4. **Ticket 4 (`edge-proxy-conf`):** Increase `/api/reports` `proxy_read_timeout` from `1s` to `5s`.
5. **Ticket 5 (`billing-api`):** Remove the explicit `env` `VAULT_URL` override (`billingApi.overrideVaultUrl: ""`) so `billing-config` ConfigMap's FQDN takes effect.
6. **Ticket 6 (`fraud-checker`):** Increase `limits.memory` from `24Mi` to `128Mi` (`OOMKilled` Exit 137).
7. **Ticket 7 (`invoice-archive-pvc`):** Change `accessMode` from `ReadWriteMany` to `ReadWriteOnce` (`managed-csi` Disk CSI), delete the immutable PVC, and upgrade.
8. **Ticket 8 (`audit-collector`):** Set `auditCollector.serviceAccountName: "audit-collector-sa"` on the Deployment instead of defaulting to `default`.
9. **Ticket 9 (`session-api`):** Lower `sessionApi.resources.requests.memory` from `512Mi` to `48Mi` (`limits.memory: 128Mi`) to fit within `data-resource-quota` (keep quota intact).
10. **Ticket 10 (`cache-db`):** Change `StatefulSet.spec.serviceName` from `cache-internal` to `cache-headless`, delete the immutable StatefulSet (`kubectl delete sts cache-db -n meridian-data`), and upgrade.
