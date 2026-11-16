[🇹🇷 Türkçe](#-türkçe-çözüm-rehberi) | [🇬🇧 English](#-english-solution-guide)

---

# 🇹🇷 Türkçe Çözüm Rehberi

Bu doküman **AtlasFlow v15.0 (Lab 32)** içerisindeki 10 karışık genel tekrar biletinin teşhis akışını, kök nedenlerini ve çözümlerini içerir.

> [!TIP]
> Tüm çözümleri Helm ile tek seferde uygulamak için (dikkat: Bilet 6 için önce immutable PVC silinmelidir):
> ```bash
> kubectl delete pvc report-archive-pvc -n atlas-core --ignore-not-found=true
> INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
> helm upgrade atlasflow ./helm/atlasflow \
>   -f ./solution/values-solution.yaml \
>   --set global.ingressHost="atlas.${INGRESS_IP}.nip.io"
> ./check.sh
> ```

---

## Bilet 1 — Ingress `pathType: Exact` Hatası (`atlas-main-ingress`)
* **Katman:** Ağ / NGINX Ingress (L7)
* **Nasıl Bulunur?** `/api/catalog` `200 OK` dönerken `/api/catalog/featured` `404` dönüyorsa `kubectl get ingress -n atlas-edge -o yaml` incelenir.
* **Kök Neden:** `/api/catalog` yolu `pathType: Exact` olarak tanımlandığı için `/api/catalog/featured` alt yolu eşleşmez.
* **Çözüm:** `ingress.catalogPathType` (`pathType`) değerini `Prefix` yapın.

## Bilet 2 — Cross-Namespace NetworkPolicy `namespaceSelector` Eksik (`core-pricing-netpol`)
* **Katman:** Ağ / Calico NetworkPolicy
* **Nasıl Bulunur?** `504 Gateway Time-out` geldiğinde `edge-proxy` içinden `pricing-engine` Pod IP'sine `wget` timeout yer; `kubectl get netpol -n atlas-core -o yaml` içinde `from:` kuralına bakılır.
* **Kök Neden:** `core-pricing-netpol` yalnızca `podSelector: { app: edge-proxy }` içerir; `edge-proxy` `atlas-edge` namespace'inde olduğu için `namespaceSelector` olmadan aynı `from:` öğesi eşleşmez.
* **Çözüm:** Politikayı **silmeden** aynı `- from:` maddesinin içine `namespaceSelector: { matchLabels: { kubernetes.io/metadata.name: atlas-edge } }` ekleyin (`networkPolicies.pricingFrom`).

## Bilet 3 — Loopback `127.0.0.1` Soket Dinleme Hatası (`vault-api`)
* **Katman:** Ağ / Container Soket Bind
* **Nasıl Bulunur?** Pod `1/1 Running` ve `kubectl get ep vault-api -n atlas-data` dolu olduğu halde `502` dönüyorsa `kubectl logs deploy/vault-api -n atlas-data` okunur (`binding socket on 127.0.0.1:8085`).
* **Kök Neden:** `vault-api`, `BIND_HOST="127.0.0.1"` üzerinde dinlediği için kube-proxy/diğer podlardan gelen paketlere `Connection refused` verir.
* **Çözüm:** `vaultApi.bindHost` değerini `"0.0.0.0"` yapın.

## Bilet 4 — `readinessProbe` Yanlış Path Hatası (`checkout-api`)
* **Katman:** Uygulama Yaşam Döngüsü / Probe + Service Endpoints
* **Nasıl Bulunur?** `kubectl get pods -n atlas-core` çıktısında pod `0/1 Running`, `kubectl get ep checkout-api -n atlas-core` ise `<none>` görünür. `kubectl describe pod` Events bölümünde `Readiness probe failed: HTTP probe failed with statuscode: 404` yazar.
* **Kök Neden:** Uygulama `/healthz` yolunu sunarken `readinessProbe.httpGet.path` alanı `/readyz` olarak ayarlanmıştır.
* **Çözüm:** `checkoutApi.readinessPath` değerini `"/healthz"` yapın.

## Bilet 5 — Secret Key Uyuşmazlığı (`settlement-worker`)
* **Katman:** Uygulama Konfigürasyonu / Secret
* **Nasıl Bulunur?** `kubectl get pods -n atlas-core` çıktısında `settlement-worker` **`CreateContainerConfigError`** durumundadır. `kubectl describe pod` Events satırında `couldn't find key api-token in Secret atlas-core/settlement-credentials` yazar.
* **Kök Neden:** Secret `auth-token` anahtarıyla tanımlıyken Pod `secretKeyRef.key: api-token` istemektedir.
* **Çözüm:** `settlementWorker.secretKeyRef` değerini `"auth-token"` yapın.

## Bilet 6 — Var Olmayan `StorageClass` & Immutable PVC (`report-archive-pvc` / `report-exporter`)
* **Katman:** Depolama (`PVC` / `StorageClass`)
* **Nasıl Bulunur?** `report-exporter` podu `Pending`, `kubectl get pvc -n atlas-core` çıktısında `report-archive-pvc` `Pending` görünür. `kubectl describe pvc` çıktısı `storageclass.storage.k8s.io "atlas-nvme-fast" not found` uyarısı verir; `kubectl get sc` ile kümedeki gerçek sınıfın `managed-csi` (`default`) olduğu görülür.
* **Kök Neden:** PVC yanlış `storageClassName: "atlas-nvme-fast"` ile açılmıştır ve `PVC.spec` alanları **immutable** olduğu için yerinde `edit` ile değişmez.
* **Çözüm:** `reportExporter.storage.storageClassName` değerini `"managed-csi"` yapın, ardından eski PVC'yi silip Helm upgrade uygulayın:
  ```bash
  kubectl delete pvc report-archive-pvc -n atlas-core
  ```

## Bilet 7 — RBAC `Role` Yetki Eksikliği (`topology-watcher`)
* **Katman:** Güvenlik / RBAC (`ServiceAccount`, `Role`, `RoleBinding`)
* **Nasıl Bulunur?** `topology-watcher` `CrashLoopBackOff` durumundadır. `kubectl logs deploy/topology-watcher -n atlas-core` çıktısında `HTTP Error 403: Forbidden` görülür.
* **Kök Neden:** `topology-watcher-role` yalnızca `resources: ["configmaps"]` izni vermektedir; uygulamanın ihtiyaç duyduğu `pods` ve `services` kaynakları eksiktir.
* **Çözüm:** `topologyWatcher.rbac.allowedResources` listesini `["pods", "services"]` yapın (gerekirse `kubectl rollout restart deploy/topology-watcher -n atlas-core` ile beklemeyi hızlandırın).

## Bilet 8 — `nodeSelector` Uyuşmazlığı (`audit-store`) & Eksik `Toleration` (`node-guardian`)
* **Katman:** Zamanlama (`Scheduling`: `nodeSelector` + `Taints & Tolerations`)
* **Nasıl Bulunur?**
  * `audit-store` `Pending` durumundadır; `kubectl describe pod` Events satırı `didn't match Pod's node affinity/selector` der.
  * `kubectl get nodes` çıktısı `2` düğüm gösterirken `kubectl get ds node-guardian -n atlas-data` `DESIRED: 1` gösterir. `kubectl describe node` ile 2. düğümde `dedicated=guardian:NoSchedule` taint'i olduğu görülür.
* **Kök Neden:**
  * `audit-store` kümede hiçbir node üzerinde olmayan `hardware-profile: dedicated-nvme` `nodeSelector` etiketiyle kısıtlanmıştır.
  * `node-guardian` DaemonSet'inde `dedicated=guardian:NoSchedule` taint'i için `toleration` eksiktir.
* **Çözüm:**
  * `auditStore.nodeSelectorEnabled: false` yapın (veya `nodeSelector` alanını kaldırın).
  * Node taint'ini **silmeden**, `nodeGuardian.tolerations` altına matching `Equal` (`key: dedicated`, `value: guardian`, `effect: NoSchedule`) toleration ekleyin.

## Bilet 9 — HPA Eksik `requests.cpu` & PDB `minAvailable` Kilidi (`catalog-api`)
* **Katman:** Ölçekleme & Dayanıklılık (`HPA` + `PodDisruptionBudget`)
* **Nasıl Bulunur?** `kubectl get hpa,pdb -n atlas-core` çıktısında HPA `TARGETS: cpu: <unknown>/70%`, PDB ise `ALLOWED DISRUPTIONS: 0` gösterir. `kubectl describe hpa catalog-api-hpa -n atlas-core` `missing request for cpu` uyarısı verir.
* **Kök Neden:**
  * `catalog-api` container'ında `resources.requests.cpu` tanımlı olmadığı için `metrics-server` CPU kullanım yüzdesini hesaplayamaz.
  * `catalog-api` `2` replica iken `catalog-api-pdb` `minAvailable: 2` istediği için hiçbir pod gönüllü tahliye (`drain`) edilemez.
* **Çözüm:**
  * `catalogApi.resources.requestsCpu: "30m"` ekleyin.
  * `catalogApi.pdb.minAvailable` değerini `1` yapın.

## Bilet 10 — Reverse Proxy Cross-Namespace Kısa DNS Hatası (`edge-proxy-conf`)
* **Katman:** Ağ / NGINX Reverse Proxy (`ConfigMap`) + CoreDNS
* **Nasıl Bulunur?** `502 Bad Gateway` geldiğinde `kubectl logs deploy/edge-proxy -n atlas-edge` içinde `analytics-api could not be resolved (3: Host not found)` görünür.
* **Kök Neden:** `analytics-api` `atlas-data` namespace'indedir ancak `atlas-edge` içindeki `edge-proxy-conf` bunu kısa isimle (`analytics-api:8088`) çağırmaktadır.
* **Çözüm:** `edgeProxy.analyticsUpstream` değerini `"analytics-api.atlas-data.svc.cluster.local:8088"` yapın.

---

# 🇬🇧 English Solution Guide

> [!TIP]
> Apply all fixes at once via Helm (delete the immutable broken PVC first):
> ```bash
> kubectl delete pvc report-archive-pvc -n atlas-core --ignore-not-found=true
> INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
> helm upgrade atlasflow ./helm/atlasflow \
>   -f ./solution/values-solution.yaml \
>   --set global.ingressHost="atlas.${INGRESS_IP}.nip.io"
> ./check.sh
> ```

1. **Ticket 1 (`atlas-main-ingress`):** `/api/catalog` has `pathType: Exact`; change `ingress.catalogPathType` to `Prefix`.
2. **Ticket 2 (`core-pricing-netpol`):** Cross-namespace `podSelector` lacks `namespaceSelector: { matchLabels: { kubernetes.io/metadata.name: atlas-edge } }` in the same `- from:` item (do not delete the NetPol).
3. **Ticket 3 (`vault-api`):** Socket binds to `127.0.0.1:8085`; set `vaultApi.bindHost` to `"0.0.0.0"`.
4. **Ticket 4 (`checkout-api`):** `readinessProbe` requests `/readyz` instead of `/healthz`; update `checkoutApi.readinessPath` to `"/healthz"`.
5. **Ticket 5 (`settlement-worker`):** `CreateContainerConfigError` because `secretKeyRef.key` is `api-token` while Secret `settlement-credentials` defines `auth-token`.
6. **Ticket 6 (`report-archive-pvc`):** PVC references nonexistent `atlas-nvme-fast` StorageClass; set `storageClassName: "managed-csi"`, delete the immutable old PVC, and upgrade.
7. **Ticket 7 (`topology-watcher`):** `Role/topology-watcher-role` only grants `configmaps`; add `["pods", "services"]`.
8. **Ticket 8 (`audit-store` & `node-guardian`):** Remove invalid `nodeSelector` (`auditStore.nodeSelectorEnabled: false`) and add `toleration` (`dedicated=guardian:NoSchedule`) to `node-guardian` without deleting the node taint.
9. **Ticket 9 (`catalog-api-hpa` & `catalog-api-pdb`):** Add `resources.requests.cpu: "30m"` to `catalog-api` so HPA computes CPU %, and reduce `catalog-api-pdb` `minAvailable` from `2` to `1`.
10. **Ticket 10 (`edge-proxy-conf`):** Cross-namespace upstream uses short name `analytics-api:8088` from `atlas-edge`; change to `"analytics-api.atlas-data.svc.cluster.local:8088"`.
