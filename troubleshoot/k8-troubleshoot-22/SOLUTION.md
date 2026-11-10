# 🔐 SRE Incident Post-Mortem & Solution Key
## Lab 22 — VaultStream v6.0 Zero-Trust Payment Settlement & PCI-DSS Mesh

> **[🇬🇧 English Version](#-english-version) | [🇹🇷 Türkçe Versiyon](#-türkçe-versiyon)**

---

# 🇬🇧 English Version

# Incident Remediation Guide & Root Cause Analysis: Lab 22 (VaultStream PCI-DSS Mesh)

This document provides in-depth Root Cause Analysis (RCA), diagnostic procedures, and permanent Helm remediations for all **10 multi-layered Kubernetes defects** across the 4 deployment phases of `k8-troubleshoot-22`.

---

## 📑 Executive Incident Resolution Matrix

| Phase | Defect ID | Impacted Component | Root Cause (RCA) | Remediation Strategy | Severity |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Phase 1** | **Defect #1** | `DaemonSet/pci-node-auditor` | Non-existent node label `security.azure.com/fips-node: "true"` in `nodeSelector` (`DESIRED: 0`). | Remove `nodeSelector` from `08-auditor-daemonset.yaml`. | `P1 - Blocker` |
| **Phase 1** | **Defect #2** | `DaemonSet/pci-node-auditor` | Container code allocates 48MB RAM, but `auditor.memoryLimit: 32Mi` causes immediate `OOMKilled` (Exit Code 137). | Increase memory limit to `128Mi` in `values.yaml`. | `P1 - Blocker` |
| **Phase 1** | **Defect #3** | `Service/pci-auditor-svc` | Service selector requires `tier: compliance-agent` while pod carries `tier: auditor` (`Endpoints: <none>`). | Align Service selector to `tier: auditor` in `08-auditor-daemonset.yaml`. | `P1 - Blocker` |
| **Phase 2** | **Defect #4** | `StatefulSet/ledger-db` | Headless Service named `ledger-db`, but `values.yaml` specifies `ledger.serviceName: ledger-db-internal` (DNS failure). | Set `ledger.serviceName: ledger-db` in `values.yaml`. | `P1 - Blocker` |
| **Phase 2** | **Defect #5** | `NetworkPolicy/ledger-db-isolation` | Policy only permits `tier: settlement`. Engine has `tier: engine` and audit job has `tier: audit-job` (connection timed out). | Allow `tier: engine` and `tier: audit-job` in `06-network-policies.yaml`. | `P1 - Blocker` |
| **Phase 2** | **Defect #6** | `Deployment/settlement-engine` | Secret key mismatch: Secret has `hsm_signing_key` while `values.yaml` searches for `signing_key` (`CreateContainerConfigError`). | Set `engine.secretKeyName: hsm_signing_key` in `values.yaml`. | `P1 - Blocker` |
| **Phase 2** | **Defect #7** | `Deployment/settlement-engine` | Application listens on port 8081, but `engine.probePort: 8080` triggers failed probes and `CrashLoopBackOff`. | Set `engine.probePort: 8081` in `values.yaml`. | `P1 - Blocker` |
| **Phase 3** | **Defect #8** | `NetworkPolicy/pci-signer-isolation` | NetworkPolicy specifies port 9443 instead of 8443 (requests to PCI namespace timeout). | Update `signer.networkPolicyPort: 8443` in `values.yaml` and `06-network-policies.yaml`. | `P1 - Blocker` |
| **Phase 3** | **Defect #9** | `Service/edge-proxy` & Egress | Service selector drift (`selectorTier: edge-gateway`), targetPortName mismatch, missing CoreDNS egress (UDP/TCP 53), and non-FQDN upstream. | Correct selector to `proxy`, targetPort to `proxy-http`, allow DNS egress, and use full FQDN in Nginx proxy_pass. | `P1 - Blocker` |
| **Phase 4** | **Defect #10** | `Ingress/vaultstream-ingress` | `className: internal-nginx` is ignored by standard Nginx Ingress Controller; path mismatch `/api/v2/...` yields 404. | Set `ingress.className: nginx` and path to `/settlement/status` in `values.yaml`. | `P1 - Blocker` |

---

## 🛠️ Step-by-Step Incident Remediations

### Phase 1: `DaemonSet/pci-node-auditor` (3 Layered Defects)

#### Defect #1: Invalid `nodeSelector` (`DESIRED: 0`)
* **Diagnostics:** `kubectl get ds -n vaultstream-core` displays `DESIRED: 0, CURRENT: 0`.
* **Root Cause:** `08-auditor-daemonset.yaml` enforces `nodeSelector: security.azure.com/fips-node: "true"`. Cluster nodes do not carry this label.
* **Remediation:** Remove the `nodeSelector` block in `08-auditor-daemonset.yaml`:
  ```yaml
      tolerations:
        - operator: Exists
  ```

#### Defect #2: Memory Limit Exceeded (`OOMKilled` — Exit Code 137)
* **Diagnostics:** Pods transition to `CrashLoopBackOff`. `kubectl describe pod` indicates `OOMKilled: true (Exit Code 137)`.
* **Root Cause:** Container Python runtime allocates 48MB buffer, exceeding `auditor.memoryLimit: 32Mi`.
* **Remediation:** In `helm/vaultstream/values.yaml`, increase `auditor.memoryLimit` to `128Mi`:
  ```yaml
  auditor:
    memoryLimit: 128Mi
  ```

#### Defect #3: Service Selector Drift (`Endpoints: <none>`)
* **Diagnostics:** `kubectl get ep pci-auditor-svc -n vaultstream-core` returns `<none>`.
* **Root Cause:** `Service/pci-auditor-svc` specifies `tier: compliance-agent` while pod carries `tier: auditor`.
* **Remediation:** Update `Service` selector in `08-auditor-daemonset.yaml`:
  ```yaml
  spec:
    type: ClusterIP
    selector:
      app: pci-node-auditor
      tier: auditor
  ```

---

### Phase 2: `settlement-engine` & `ledger-db` (4 Layered Defects)

#### Defect #4: StatefulSet Headless Service Name Mismatch
* **Diagnostics:** `settlement-engine` initContainer logs error: `nc: bad address 'ledger-db-0.ledger-db'`.
* **Root Cause:** Headless Service is named `ledger-db`, but `values.yaml` specifies `ledger.serviceName: ledger-db-internal`.
* **Remediation:** In `values.yaml`, update `ledger.serviceName`:
  ```yaml
  ledger:
    serviceName: ledger-db
  ```

#### Defect #5: `ledger-db-isolation` NetworkPolicy Blocking Ingress
* **Diagnostics:** TCP connection to `ledger-db-0.ledger-db:6379` times out.
* **Root Cause:** `ledger-db-isolation` only permits `tier: settlement`. The engine pod has `tier: engine` and the verification Job has `tier: audit-job`.
* **Remediation:** In `06-network-policies.yaml`, permit `tier: engine` and `tier: audit-job`:
  ```yaml
    ingress:
      - from:
          - podSelector:
              matchLabels:
                tier: engine
          - podSelector:
              matchLabels:
                tier: audit-job
        ports:
          - protocol: TCP
            port: 6379
  ```

#### Defect #6: Secret Key Name Mismatch (`CreateContainerConfigError`)
* **Diagnostics:** `kubectl describe pod` shows `Error: couldn't find key signing_key in Secret vaultstream-core/vaultstream-hsm-secret`.
* **Root Cause:** `01-config-and-secrets.yaml` defines key `hsm_signing_key`, but `values.yaml` looks for `signing_key`.
* **Remediation:** In `values.yaml`, set `engine.secretKeyName: hsm_signing_key`:
  ```yaml
  engine:
    secretKeyName: hsm_signing_key
  ```

#### Defect #7: Probe Port Mismatch (`CrashLoopBackOff`)
* **Diagnostics:** Probe fails with `connection refused` on port 8080.
* **Root Cause:** Application listens on port 8081, but `engine.probePort` is set to 8080.
* **Remediation:** In `values.yaml`, set `engine.probePort: 8081`.

---

### Phase 3: `pci-signer`, `edge-proxy` & CoreDNS Egress (Defects 8 & 9)

#### Defect #8: PCI Signer NetworkPolicy Port Mismatch
* **Diagnostics:** HTTP requests to `pci-signer.vaultstream-pci.svc.cluster.local:8443` timeout.
* **Root Cause:** `signer.networkPolicyPort` is set to 9443 instead of 8443.
* **Remediation:** In `values.yaml` and `06-network-policies.yaml`, set port to 8443.

#### Defect #9: Edge Proxy Selector, Port, DNS Egress & FQDN Upstream
* **Remediations:**
  1. In `values.yaml`, set `proxy.selectorTier: proxy` and `proxy.targetPortName: proxy-http`.
  2. In `06-network-policies.yaml`, add UDP/TCP port 53 to egress rules for cluster DNS resolution.
  3. In `01-config-and-secrets.yaml` (`edge-proxy-conf`), proxy to full cross-namespace FQDN:
     ```nginx
     proxy_pass http://pci-signer.{{ .Values.global.pciNamespace }}.svc.cluster.local:8443/pci/verify;
     ```

---

### Phase 4: Ingress Class and Path (Defect 10)

#### Defect #10: Ingress Controller Class & Path Drift
* **Remediation:** In `values.yaml`, set `ingress.className: nginx` and `ingress.path: /settlement/status`.

---

## 🚀 End-to-End Verification

```bash
helm upgrade --install vaultstream ./helm/vaultstream
kubectl rollout restart deploy/edge-proxy -n vaultstream-core
kubectl delete job vaultstream-e2e-audit -n vaultstream-core --ignore-not-found
helm upgrade --install vaultstream ./helm/vaultstream

# Follow verification job logs:
kubectl logs -n vaultstream-core job/vaultstream-e2e-audit -f
```

**Expected Result:** All 4/4 verification stages report `[PASS]`!

---

# 🇹🇷 Türkçe Versiyon

# 🇹🇷 Türkçe Çözüm Kılavuzu (Adım Adım Kök Neden Analizi)

Bu belge, **Lab 22 (`k8-troubleshoot-22`)** içerisindeki 10 çok katmanlı Kubernetes ağ, iş yükü ve güvenlik hatasının kök nedenlerini ve tam çözümlerini içerir.

---

## 🛠️ AŞAMA 1 Çözümleri: `DaemonSet/pci-node-auditor` (3 Katmanlı Hata)

### Hata 1: Geçersiz `nodeSelector` (`DESIRED: 0`)
* **İlgili Dosyalar:** `helm/vaultstream/templates/08-auditor-daemonset.yaml` ve `helm/vaultstream/values.yaml`
* **Belirti:** `kubectl get ds -n vaultstream-core` çıktısında `DESIRED: 0` görünür.
* **Kök Neden:** `08-auditor-daemonset.yaml` içinde `nodeSelector: security.azure.com/fips-node: "true"` tanımlanmıştır. Kümedeki düğümlerde bu etiket olmadığı için DaemonSet hiçbir düğümü seçemez.
* **Çözüm:** `08-auditor-daemonset.yaml` içindeki `nodeSelector:` bloğunu silin:
  ```yaml
      tolerations:
        - operator: Exists
  ```

### Hata 2: Bellek Sınırı Aşımı (`OOMKilled` — Exit Code 137)
* **İlgili Dosya:** `helm/vaultstream/values.yaml` (`auditor.memoryLimit`)
* **Belirti:** `nodeSelector` kaldırıldıktan sonra `pci-node-auditor` podları başlar ancak hemen `OOMKilled` (`Exit Code 137`) ile çöküp `CrashLoopBackOff` olur.
* **Kök Neden:** Konteyner içindeki Python kodu `bytearray(48 * 1024 * 1024)` (`48 MB`) bellek ayırmaktadır, ancak `values.yaml` içinde `auditor.memoryLimit: 32Mi` verilmiştir.
* **Çözüm:** `helm/vaultstream/values.yaml` içinde bellek limitini `128Mi` yapın:
  ```yaml
  auditor:
    memoryLimit: 128Mi
  ```

### Hata 3: `Service/pci-auditor-svc` Etiket Seçici Kayması (`ENDPOINTS: <none>`)
* **İlgili Dosya:** `helm/vaultstream/templates/08-auditor-daemonset.yaml`
* **Belirti:** DaemonSet podları `1/1 Running` olsa bile `kubectl get ep pci-auditor-svc -n vaultstream-core` çıktısı `<none>` kalır.
* **Kök Neden:** `Service/pci-auditor-svc` seçicisinde `tier: compliance-agent` aranırken DaemonSet podlarının gerçek etiketi `tier: auditor` olarak tanımlanmıştır.
* **Çözüm:** `08-auditor-daemonset.yaml` içinde Service `selector` alanını düzeltin:
  ```yaml
  spec:
    type: ClusterIP
    selector:
      app: pci-node-auditor
      tier: auditor
  ```

---

## 🛠️ AŞAMA 2 Çözümleri: `settlement-engine` ve `ledger-db` (4 Katmanlı Hata)

### Hata 4: StatefulSet Headless Service İsim Uyuşmazlığı (`ledger-db-0.ledger-db` DNS Hatası)
* **İlgili Dosya:** `helm/vaultstream/values.yaml` (`ledger.serviceName`)
* **Belirti:** `settlement-engine` podları `Init:0/1` (`wait-for-ledger`) aşamasında takılır ve `vaultstream-e2e-audit` Job'ı `[1/4]` adımında `nc: bad address 'ledger-db-0.ledger-db'` hatası verir.
* **Kök Neden:** `02-ledger-statefulset.yaml` içindeki Headless Service'in adı `ledger-db` iken, `values.yaml` içinde `ledger.serviceName: ledger-db-internal` verilmiştir. İkisi eşleşmediği için CoreDNS `ledger-db-0.ledger-db` kaydını oluşturmaz.
* **Çözüm:** `helm/vaultstream/values.yaml` içinde `serviceName` değerini `ledger-db` yapın:
  ```yaml
  ledger:
    serviceName: ledger-db
  ```

### Hata 5: `ledger-db-isolation` NetworkPolicy Etiket Engeli
* **İlgili Dosya:** `helm/vaultstream/templates/06-network-policies.yaml`
* **Belirti:** DNS çözülse bile `nc -z -w 2 ledger-db-0.ledger-db 6379` bağlantısı zaman aşımına (`timed out`) uğrar.
* **Kök Neden:** `ledger-db-isolation` NetworkPolicy kuralı sadece `tier: settlement` etiketli podlara izin vermektedir. Oysa `settlement-engine` podunun etiketi `tier: engine`, doğrulama Job'ının etiketi ise `tier: audit-job`'dır.
* **Çözüm:** `06-network-policies.yaml` içindeki `ledger-db-isolation` politikasında `tier: engine` ve `tier: audit-job` etiketlerine izin verin:
  ```yaml
  apiVersion: networking.k8s.io/v1
  kind: NetworkPolicy
  metadata:
    name: ledger-db-isolation
    namespace: {{ .Values.global.coreNamespace }}
  spec:
    podSelector:
      matchLabels:
        tier: database
    policyTypes:
      - Ingress
    ingress:
      - from:
          - podSelector:
              matchLabels:
                tier: engine
          - podSelector:
              matchLabels:
                tier: audit-job
        ports:
          - protocol: TCP
            port: 6379
  ```

### Hata 6: Secret Anahtar İsim Uyuşmazlığı (`CreateContainerConfigError`)
* **İlgili Dosya:** `helm/vaultstream/values.yaml` (`engine.secretKeyName`)
* **Belirti:** InitContainer tamamlandıktan sonra `settlement-engine` podu `CreateContainerConfigError` durumuna düşer (`kubectl describe pod` içinde `Error: couldn't find key signing_key in Secret vaultstream-core/vaultstream-hsm-secret` yazar).
* **Kök Neden:** `01-config-and-secrets.yaml` içindeki `Secret/vaultstream-hsm-secret` verisinde anahtar adı `hsm_signing_key` iken, `values.yaml` içinde `engine.secretKeyName: signing_key` yazılmıştır.
* **Çözüm:** `helm/vaultstream/values.yaml` içinde `secretKeyName` değerini `hsm_signing_key` yapın:
  ```yaml
  engine:
    secretKeyName: hsm_signing_key
  ```

### Hata 7: Liveness & Readiness Probe Port Uyuşmazlığı (`CrashLoopBackOff`)
* **İlgili Dosya:** `helm/vaultstream/values.yaml` (`engine.probePort`)
* **Belirti:** `settlement-engine` podu `Running` olur ancak `0/1 Ready` kalır ve birkaç saniye sonra `Liveness probe failed: Get "http://...:8080/healthz": dial tcp ...:8080: connect: connection refused` ile yeniden başlar.
* **Kök Neden:** Uygulama `engine.port: 8081` üzerinde dinlerken, `engine.probePort: 8080` olarak bırakılmıştır.
* **Çözüm:** `helm/vaultstream/values.yaml` içinde `probePort: 8081` yapın:
  ```yaml
  engine:
    port: 8081
    probePort: 8081
  ```

---

## 🛠️ AŞAMA 3 Çözümleri: `pci-signer`, `edge-proxy` ve CoreDNS Egress

### Hata 8: `pci-signer-isolation` NetworkPolicy Port (`9443` vs `8443`) ve Seçici Hatası
* **İlgili Dosyalar:** `helm/vaultstream/values.yaml` (`signer.networkPolicyPort`) ve `helm/vaultstream/templates/06-network-policies.yaml`
* **Belirti:** `vaultstream-e2e-audit` Job'ı `[3/4]` adımında `http://pci-signer.vaultstream-pci.svc.cluster.local:8443/pci/verify` adresine giderken `download timed out` verir.
* **Kök Neden:** `values.yaml` içinde `signer.networkPolicyPort: 9443` olarak verilmiştir, oysa `pci-signer` `8443` portunda çalışır.
* **Çözüm:** `helm/vaultstream/values.yaml` içinde `networkPolicyPort: 8443` yapın ve `06-network-policies.yaml` içinde `vaultstream-core` namespace'inden `8443` portuna erişime izin verin:
  ```yaml
  signer:
    port: 8443
    networkPolicyPort: 8443
  ```

### Hata 9: `Service/edge-proxy` Seçici (`selectorTier`) ve `targetPortName` Uyuşmazlığı + CoreDNS Egress + Cross-Namespace FQDN
* **İlgili Dosyalar:** `helm/vaultstream/values.yaml`, `06-network-policies.yaml` ve `01-config-and-secrets.yaml`
* **Belirtiler:**
  1. `kubectl get ep edge-proxy -n vaultstream-core` çıktısı `<none>` döner.
  2. Endpoint düzeltilse bile `edge-proxy` podu içinden `settlement-engine` ve `pci-signer` adresleri çözülemez (`502/504`).
* **Kök Nedenler ve Çözümleri:**
  1. **`values.yaml` (`proxy` bölümü):** Deployment pod etiketi `tier: proxy` ve containerPort adı `proxy-http` iken, `values.yaml` içinde `selectorTier: edge-gateway` ve `targetPortName: proxy-http-port` yazılmıştır. Bunları düzeltin:
     ```yaml
     proxy:
       targetPortName: proxy-http
       selectorTier: proxy
     ```
  2. **`06-network-policies.yaml` (`edge-proxy-egress`):** CoreDNS (`UDP/TCP 53`) çıkış iznini ekleyin:
     ```yaml
       egress:
         - to:
             - namespaceSelector: {}
           ports:
             - protocol: UDP
               port: 53
             - protocol: TCP
               port: 53
         - to:
             - podSelector:
                 matchLabels:
                   tier: engine
           ports:
             - protocol: TCP
               port: 8081
         - to:
             - namespaceSelector:
                 matchLabels:
                   kubernetes.io/metadata.name: {{ .Values.global.pciNamespace }}
           ports:
             - protocol: TCP
               port: 8443
     ```
  3. **`01-config-and-secrets.yaml` (`edge-proxy-conf`):** Farklı namespace'teki `pci-signer` servisine kısa ad yerine tam FQDN ile gidin:
     ```nginx
         location /pci/verify {
             proxy_pass http://pci-signer.{{ .Values.global.pciNamespace }}.svc.cluster.local:8443/pci/verify;
             proxy_connect_timeout 3s;
             proxy_read_timeout 3s;
         }
     ```

---

## 🛠️ AŞAMA 4 Çözümü: Ingress Sınıfı ve Yolu (`07-ingress.yaml` & `values.yaml`)

### Hata 10: `ingressClassName: internal-nginx` ve Path Uyuşmazlığı
* **İlgili Dosya:** `helm/vaultstream/values.yaml` (`ingress` bölümü)
* **Kök Neden:** `className: internal-nginx` olduğu için standart `nginx` Ingress Controller tarafından işlenmez ve `path: /api/v2/settlement/status` doğrudan Nginx'e gönderildiğinde `404` alır.
* **Çözüm:** `helm/vaultstream/values.yaml` içinde:
  ```yaml
  ingress:
    enabled: true
    className: nginx
    host: vaultstream.local
    path: /settlement/status
    pathType: Prefix
  ```

---

## ✅ Tek Seferde Doğrulama Komutları

Tüm düzeltmeleri yaptıktan sonra:

```bash
helm upgrade --install vaultstream ./helm/vaultstream
kubectl rollout restart deploy/edge-proxy -n vaultstream-core
kubectl delete job vaultstream-e2e-audit -n vaultstream-core --ignore-not-found
helm upgrade --install vaultstream ./helm/vaultstream

# Doğrulama Job'ı loglarını izle:
kubectl logs -n vaultstream-core job/vaultstream-e2e-audit -f
```
