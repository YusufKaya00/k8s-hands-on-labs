# ✅ K8s Troubleshoot Lab 37: ZephyrMesh v20.0 — Çözüm & Kök Neden Analizi (RCA)

> **[🇹🇷 Türkçe](#-türkçe-bölüm) | [🇬🇧 English](#-english-section)**

---

<a id="-türkçe-bölüm"></a>
## 🇹🇷 Türkçe Bölüm

### 📊 10 Bilet Özet Kök Neden Tablosu

| Bilet | Semptom / HTTP | Kök Neden (Broken State) | Dosya & Anahtar (`values.yaml`) | Çözüm (`values-solution.yaml`) |
| :-: | :--- | :--- | :--- | :--- |
| **1** | `/api/catalog/items` → `404` | `Ingress/zephyr-catalog-ingress` üzerinde `ingressClassName: "traefik"` ayarlı; NGINX controller bu Ingress'i yok saydı. | `ingress.catalogIngressClassName` (`ingress.yaml`) | `"nginx"` |
| **2** | `/api/uploads/document` (2 MB) → `413` | `Ingress/zephyr-upload-ingress` annotasyonu `proxy-body-size: "512k"`; NGINX 2 MB gövdeyi reddetti. | `ingress.uploadProxyBodySize` (`ingress.yaml`) | `"10m"` |
| **3** | `/api/fx/rates` → `502` | `Service/fx-api` `targetPort: 9083` olarak tanımlı; `fx-api` podu `containerPort: 8083` dinliyor. | `fxApi.serviceTargetPort` (`services.yaml`) | `8083` |
| **4** | `/api/checkout/verify` → `502` DNS | `Service/fraud-bridge` (`ExternalName`) yanlış namespace'e işaret ediyordu (`fraud-engine.zephyr-security.svc.cluster.local`). | `fraudBridge.externalName` (`services.yaml`) | `"fraud-engine.zephyr-data.svc.cluster.local"` |
| **5** | `/api/vault/token` → `504` | `NetworkPolicy/vault-store-netpol` (`zephyr-data`) `podSelector` içinde `app: token-proxy` bekliyordu; kaynak pod etiketi `app: token-gateway`. | `vaultStore.networkPolicy.allowedPodApp` (`networkpolicy.yaml`) | `"token-gateway"` |
| **6** | `/api/auth/verify` → `503` (`CreateContainerConfigError`) | `Deployment/auth-api` `Secret/auth-jwt-secret` içinden `JWT_SIGNING_KEY` anahtarını okumaya çalışıyordu; gerçek anahtar `AUTH_SHARED_SECRET`. | `authApi.secretKeyRef` (`app-workloads.yaml`) | `"AUTH_SHARED_SECRET"` |
| **7** | `/api/billing/charge` → `503` (`0/1` / CrashLoop) | `billing-api` `BIND_HOST="127.0.0.1"` dinlediği için kubelet `<PodIP>:8089/healthz` probe'ları `Connection refused` yedi. | `billingApi.bindHost` (`app-workloads.yaml`) | `"0.0.0.0"` |
| **8** | `/api/reports/generate` → `503` (`0/1` pod yok) | `LimitRange/zephyr-app-limits` `max.memory: 512Mi` sınırı koyarken `report-api` `1024Mi` istediği için ReplicaSet pod oluşturamadı. | `reportApi.resources.limits.memory` (`app-workloads.yaml`) | `"256Mi"` |
| **9** | `/api/audit/services` → `500` (`403 Forbidden`) | `Deployment/audit-inspector` `serviceAccountName: "default"` kullanıyordu; `audit-role` ise `audit-sa` hesabına bağlıydı. | `auditInspector.podServiceAccountName` (`data-workloads.yaml`) | `"audit-sa"` |
| **10** | `DaemonSet/node-log-agent` → `1/2 Ready` | 2. düğümdeki taint `zephyr-pool=analytics:NoSchedule`, ancak DaemonSet toleration `effect: "NoExecute"` yazılıydı. | `nodeAgent.tolerationEffect` (`data-workloads.yaml`) | `"NoSchedule"` |

### ⚡ Referans Çözümü Tek Komutta Uygulama

```bash
export INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
export HOST="zephyr.${INGRESS_IP}.nip.io"

helm upgrade zephyrmesh ./helm/zephyrmesh \
  -f ./helm/zephyrmesh/values.yaml \
  -f ./solution/values-solution.yaml \
  --set global.ingressHost="${HOST}"

kubectl rollout status deploy -n zephyr-app --timeout=90s
kubectl rollout status deploy -n zephyr-data --timeout=90s
kubectl rollout status ds/node-log-agent -n zephyr-data --timeout=90s

./check.sh
```

---

<a id="-english-section"></a>
## 🇬🇧 English Section

### Root Cause Matrix (10 Tickets)

1. **Ticket 1 (IngressClass):** `zephyr-catalog-ingress` used `ingressClassName: "traefik"` instead of `"nginx"`.
2. **Ticket 2 (Body Limit):** `zephyr-upload-ingress` annotation `nginx.ingress.kubernetes.io/proxy-body-size` was `"512k"`, rejecting 2 MB uploads (`413`) -> set `"10m"`.
3. **Ticket 3 (`targetPort` Mismatch):** `Service/fx-api` pointed `targetPort: 9083` instead of pod `containerPort: 8083`.
4. **Ticket 4 (`ExternalName` Drift):** `Service/fraud-bridge` pointed to `fraud-engine.zephyr-security.svc.cluster.local` instead of `fraud-engine.zephyr-data.svc.cluster.local`.
5. **Ticket 5 (Cross-NS NetPol):** `vault-store-netpol` matched `podSelector.app: token-proxy` instead of `token-gateway`.
6. **Ticket 6 (Secret Key Mismatch):** `auth-api` referenced `JWT_SIGNING_KEY` inside `auth-jwt-secret`, while the actual key is `AUTH_SHARED_SECRET`.
7. **Ticket 7 (Loopback Bind):** `billing-api` bound to `127.0.0.1` instead of `0.0.0.0`, failing kubelet probes.
8. **Ticket 8 (`LimitRange` Rejection):** `report-api` requested `limits.memory: 1024Mi` in `zephyr-app`, exceeding `zephyr-app-limits` (`max.memory: 512Mi`) -> reduce to `"256Mi"`.
9. **Ticket 9 (RBAC ServiceAccount):** `audit-inspector` ran with `serviceAccountName: "default"` instead of `"audit-sa"` bound to `Role/audit-role`.
10. **Ticket 10 (Toleration Effect):** `node-log-agent` DaemonSet tolerated `effect: "NoExecute"` while the node taint uses `effect: "NoSchedule"`.

### Apply Reference Solution

```bash
export INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
export HOST="zephyr.${INGRESS_IP}.nip.io"

helm upgrade zephyrmesh ./helm/zephyrmesh \
  -f ./helm/zephyrmesh/values.yaml \
  -f ./solution/values-solution.yaml \
  --set global.ingressHost="${HOST}"

./check.sh
```
