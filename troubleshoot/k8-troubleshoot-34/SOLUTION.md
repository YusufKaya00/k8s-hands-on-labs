[🇹🇷 Türkçe](#-türkçe-çözüm-rehberi) | [🇬🇧 English](#-english-solution-guide)

---

# 🇹🇷 Türkçe Çözüm Rehberi

Bu doküman **HeliosCore v17.0 (Lab 34)** içerisindeki 10 karışık genel tekrar biletinin kök nedenlerini ve çözümlerini içerir.

> [!TIP]
> Tüm çözümleri Helm ile tek seferde uygulamak için (dikkat: Bilet 8 için eski immutable `archive-pvc` önce silinmelidir):
> ```bash
> kubectl delete pvc archive-pvc -n helios-core --ignore-not-found=true
> INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
> helm upgrade helioscore ./helm/helioscore \
>   -f ./solution/values-solution.yaml \
>   --set global.ingressHost="helios.${INGRESS_IP}.nip.io"
> ./check.sh
> ```

---

## Bilet 1 — Ingress `backend-protocol: "HTTPS"` Uyuşmazlığı (`helios-admin-ingress`)
* **Katman:** Ağ / NGINX Ingress Annotasyonu
* **Teşhis:** `kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --tail=20` altında `SSL_do_handshake() failed` görülür. `edge-proxy` düz HTTP (`80`) sunarken `helios-admin-ingress` annotasyonu `nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"` ayarlıdır.
* **Çözüm:** `ingress.adminBackendProtocol` değerini `"HTTP"` yapın.

## Bilet 2 — Service Yanlış `protocol: UDP` (`notification-api`)
* **Katman:** Ağ / Service L4 Protokolü
* **Teşhis:** `kubectl get svc notification-api -n helios-core` çıktısında port `8081/UDP` görünür; oysa uygulama HTTP (`TCP`) sunmaktadır (`PodIP:8081` çalışır ama Service `8081/UDP` yönlendirir).
* **Çözüm:** `notificationApi.service.protocol` değerini `"TCP"` yapın.

## Bilet 3 — Calico Post-DNAT Port Tuzağı (`ledger-sync-netpol`)
* **Katman:** Ağ / Calico Ingress NetworkPolicy (`Post-DNAT`)
* **Teşhis:** `ledger-sync` Service'i `port: 80` $\rightarrow$ `targetPort: 8083` çevirir. `ledger-sync-netpol` `port: 80` izni verdiği için DNAT sonrası (`8083`) gelen paketleri düşürür (`504`).
* **Çözüm:** Politikayı **silmeden** `ledgerSync.networkPolicy.allowedPort` değerini `8083` yapın.

## Bilet 4 — Service `selector` Etiket Uyuşmazlığı (`orders-api`)
* **Katman:** Ağ / Service & Endpoints
* **Teşhis:** `orders-api` podu `1/1 Running` görünür ama `kubectl get ep orders-api -n helios-core` çıktısı `<none>` döner. Pod etiketi `version: v1` iken Service `selector` içinde `version: v2` aramaktadır.
* **Çözüm:** `ordersApi.serviceSelectorVersion` değerini `"v1"` yapın.

## Bilet 5 — `InitContainer` Yanlış Hedef Port (`settlement-api`)
* **Katman:** Uygulama Yaşam Döngüsü / `InitContainer`
* **Teşhis:** `kubectl logs -n helios-core deploy/settlement-api -c init-verify-vault` çıktısında `vault-service.helios-data.svc.cluster.local:8090` adresine `Connection refused` alınır; `vault-service` ise `:8086` dinlemektedir.
* **Çözüm:** `settlementApi.initVaultPort` değerini `8086` yapın.

## Bilet 6 — `livenessProbe` Yavaş Açılan Uygulamayı Öldürüyor (`worker-engine`)
* **Katman:** Uygulama Yaşam Döngüsü / Probe Zamanlaması
* **Teşhis:** `worker-engine` model indeksini yüklemek için `8` saniye ısınma süresine ihtiyaç duyar; ancak `livenessProbe` `initialDelaySeconds: 2, periodSeconds: 2, failureThreshold: 2` (toplam ~`6s`) ayarlı olduğu için Kubelet container'ı daha açılmadan öldürür (`CrashLoopBackOff`).
* **Çözüm:** `workerEngine.livenessProbe.initialDelaySeconds` değerini `12` yapın (`periodSeconds: 5, failureThreshold: 3` veya `startupProbe` ekleyin).

## Bilet 7 — `readOnlyRootFilesystem: true` + Eksik `emptyDir` Mount (`telemetry-sink`)
* **Katman:** Pod Güvenlik Sertleştirme (`securityContext`) & Volume
* **Teşhis:** `kubectl logs -n helios-core deploy/telemetry-sink` çıktısında `OSError: [Errno 30] Read-only file system: '/var/cache/telemetry'` görülür. Güvenlik gereği `readOnlyRootFilesystem: true` kalmalı, yalnızca yazılabilir `/var/cache/telemetry` dizinine `emptyDir` bağlanmalıdır.
* **Çözüm:** `telemetrySink.cacheMountEnabled: true` yapın (politikayı devre dışı bırakmayın).

## Bilet 8 — Statik `PV` (`2Gi`) vs `PVC` (`5Gi`) Kapasite Uyuşmazlığı (`archive-pvc`)
* **Katman:** Depolama (`PV` / `PVC` Eşleşmesi)
* **Teşhis:** `kubectl get pv,pvc -n helios-core` çıktısında `archive-pv` `2Gi Available` iken `archive-pvc` `5Gi` talep ettiği için `Pending` kalır (`2Gi < 5Gi`).
* **Çözüm:** `archiveWorker.storage.pvcSize` değerini `"2Gi"` yapıp eski `Pending` PVC'yi silerek Helm upgrade uygulayın *(veya `archive-pv` kapasitesini `5Gi` artırın)*:
  ```bash
  kubectl delete pvc archive-pvc -n helios-core
  ```

## Bilet 9 — Cluster-Scoped `nodes` İçin Namespace `Role` Kullanılmış (`node-inspector`)
* **Katman:** Güvenlik / RBAC Kapsamı (`Role` vs `ClusterRole`)
* **Teşhis:** `kubectl logs -n helios-core deploy/node-inspector` çıktısında `403 Forbidden` görülür. Mevcut `Role` yalnız namespace içi kaynakları yetkilendirebilir; `/api/v1/nodes` cluster-scoped olduğu için `ClusterRole` + `ClusterRoleBinding` gerekir.
* **Çözüm:** `nodeInspector.clusterRbacEnabled: true` yapın (gerekirse backoff'u beklememek için `kubectl rollout restart deploy/node-inspector -n helios-core` çalıştırın).

## Bilet 10 — `HPA` `scaleTargetRef` & `PDB` `matchLabels` Yazım Hataları (`payment-engine`)
* **Katman:** Ölçekleme (`HPA`) & Dayanıklılık (`PDB`)
* **Teşhis:** `kubectl describe hpa,pdb -n helios-core` çıktısında HPA `FailedGetScale: deployments.apps "payment-api-v1" not found` uyarısı verir; PDB ise `app: payment-v1` seçicisiyle hiç pod eşleştiremediği için `expectedPods: 0, disruptionsAllowed: 0` gösterir.
* **Çözüm:** `paymentEngine.hpa.targetDeploymentName` ve `paymentEngine.pdb.selectorApp` değerlerini `"payment-engine"` yapın.

---

# 🇬🇧 English Solution Guide

1. **Ticket 1 (`helios-admin-ingress`):** Set `ingress.adminBackendProtocol` from `"HTTPS"` to `"HTTP"`.
2. **Ticket 2 (`notification-api`):** Change `notificationApi.service.protocol` from `"UDP"` to `"TCP"`.
3. **Ticket 3 (`ledger-sync-netpol`):** Change allowed Post-DNAT port from `80` to `8083` (keep NetPol active).
4. **Ticket 4 (`orders-api`):** Fix Service selector `ordersApi.serviceSelectorVersion` from `"v2"` to `"v1"`.
5. **Ticket 5 (`settlement-api`):** Update `settlementApi.initVaultPort` from `8090` to `8086`.
6. **Ticket 6 (`worker-engine`):** Increase `livenessProbe.initialDelaySeconds` from `2` to `12` (`8s` warmup time).
7. **Ticket 7 (`telemetry-sink`):** Keep `readOnlyRootFilesystem: true` and mount an `emptyDir` volume at `/var/cache/telemetry` (`telemetrySink.cacheMountEnabled: true`).
8. **Ticket 8 (`archive-pvc`):** Match `archiveWorker.storage.pvcSize` (`"2Gi"`) to `archive-pv` (`2Gi`), delete the stuck `Pending` PVC, and upgrade.
9. **Ticket 9 (`node-inspector`):** Enable `ClusterRole` + `ClusterRoleBinding` for cluster-scoped `nodes` (`nodeInspector.clusterRbacEnabled: true`).
10. **Ticket 10 (`payment-engine`):** Fix `paymentEngine.hpa.targetDeploymentName` and `paymentEngine.pdb.selectorApp` to `"payment-engine"`.
