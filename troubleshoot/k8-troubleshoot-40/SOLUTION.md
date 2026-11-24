# k8-troubleshoot-40 — PulseNova v23.0 Solution & Root Cause Analysis

> **[🇹🇷 Türkçe](#-türkçe-çözüm) | [🇬🇧 English](#-english-solution)**

---

<a id="-türkçe-çözüm"></a>
## 🇹🇷 Türkçe Çözüm

| # | Servis / Obje | Kategori | Kök Neden | Düzeltme (`values.yaml`) |
|---|---|---|---|---|
| 1 | `Ingress/status-ingress` | Ingress Host | `host: status.wrong.nip.io` (gerçek host `nova.<IP>.nip.io`). | `status.ingressHostOverride: ""` |
| 2 | `Ingress/ingest-ingress` | Ingress Body Size | `proxy-body-size: "256k"` 1.5 MB yüklemeyi `413` ile reddediyor. | `ingest.proxyBodySize: "5m"` |
| 3 | `Service/catalog-api` | Service Protocol | `protocol: UDP` (`TCP` olmalı). | `catalog.serviceProtocol: "TCP"` |
| 4 | `Service/vault-alias` & `NetworkPolicy` | ExternalName & NetPol | `vault-alias` `nova-edge` gösteriyor (`nova-data` olmalı) ve NetPol portu `9000` (`8080` olmalı). | `checkout.vaultExternalName: "vault-core.nova-data.svc.cluster.local"`, `netpolAllowedPort: 8080` |
| 5 | `Deployment/feature-api` | `env` vs `envFrom` | Açık `env` (`FEATURE_MODE: maintenance`), `ConfigMap/feature-flags` (`enabled`) değerini eziyor. | `features.overrideFeatureMode: ""` |
| 6 | `Deployment/analytics-api` | LivenessProbe Warmup | Uygulama 6 sn'de açılıyor ama `livenessProbe` `initialDelaySeconds: 1` ile 3–5. sn'de öldürüyor. | `analytics.livenessInitialDelaySeconds: 10` |
| 7 | `Deployment/pdf-api` | SecurityContext & Volume | `readOnlyRootFilesystem: true` aktifken `/tmp/pdf` yazılabilir değil. | `pdf.mountTmpVolume: true` (`emptyDir`) |
| 8 | `Deployment/token-api` | Secret Key | `secretKeyRef.key: API_KEY` (gerçek anahtar `TOKEN_KEY`). | `token.secretKeyRef: "TOKEN_KEY"` |
| 9 | `DaemonSet/node-agent` | Taint/Toleration | Toleration effect `NoExecute` (node taint `NoSchedule`). | `nodeAgent.tolerationEffect: "NoSchedule"` |
| 10 | `Deployment/ops-inspector` | LimitRange & RBAC | `memoryLimit: 512Mi` `LimitRange` (`256Mi`) sınırını aşıyor ve `serviceAccountName: default` (`ops-inspector-sa` olmalı). | `opsInspector.serviceAccountName: "ops-inspector-sa"`, `memoryRequest: "64Mi"`, `memoryLimit: "128Mi"` |

### Tek Komutla Çözüm Uygulama

```bash
export INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
export HOST="nova.${INGRESS_IP}.nip.io"

helm upgrade --install pulsenova ./helm/pulsenova \
  -f ./helm/pulsenova/values.yaml \
  -f ./solution/values-solution.yaml \
  --set global.ingressHost="${HOST}"

kubectl -n nova-edge rollout status deploy/feature-api deploy/analytics-api deploy/pdf-api deploy/token-api --timeout=90s
kubectl -n nova-data rollout status ds/node-agent deploy/ops-inspector --timeout=90s

./check.sh
```

---

<a id="-english-solution"></a>
## 🇬🇧 English Solution

1. **`Ingress/status-ingress`:** Wrong `host` (`status.wrong.nip.io`) -> clear `status.ingressHostOverride: ""`.
2. **`Ingress/ingest-ingress`:** `proxy-body-size: "256k"` rejects 1.5 MB uploads (`413`) -> `"5m"`.
3. **`Service/catalog-api`:** `protocol: UDP` -> `"TCP"`.
4. **`Service/vault-alias` & `NetworkPolicy/allow-checkout-to-vault`:** Fix `ExternalName` to `vault-core.nova-data.svc.cluster.local` and NetPol port `9000` -> `8080`.
5. **`Deployment/feature-api`:** Explicit `env` overrides `envFrom` ConfigMap -> clear `features.overrideFeatureMode: ""`.
6. **`Deployment/analytics-api`:** `livenessProbe` `initialDelaySeconds: 1` kills a 6s-warmup pod -> `10`.
7. **`Deployment/pdf-api`:** Mount `emptyDir` at `/tmp/pdf` (`pdf.mountTmpVolume: true`) while keeping `readOnlyRootFilesystem: true`.
8. **`Deployment/token-api`:** `secretKeyRef.key: API_KEY` -> `"TOKEN_KEY"`.
9. **`DaemonSet/node-agent`:** Toleration effect `NoExecute` -> `"NoSchedule"`.
10. **`Deployment/ops-inspector`:** Lower memory to `64Mi`/`128Mi` (within `LimitRange` `256Mi`) and set `serviceAccountName: "ops-inspector-sa"`.
