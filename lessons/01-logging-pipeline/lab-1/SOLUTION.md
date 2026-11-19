# Ders 01 / Lab 1 — Çözüm ve Kök Neden Analizi (RCA)

> **[🇹🇷 Türkçe](#-türkçe-bölüm) | [🇬🇧 English](#-english-section)**

---

<a id="-türkçe-bölüm"></a>
## 🇹🇷 Türkçe Bölüm

### Kök Neden Özeti (4 Arıza)

| # | Katman | Arıza (Broken State) | Mühendislik Etkisi | Çözüm (`values.yaml`) |
| :-: | :--- | :--- | :--- | :--- |
| **1** | **DaemonSet Scheduling** | `fluentbit.tolerations: []` | Node üzerinde `dedicated=logging-lab:NoSchedule` taint olduğu için FluentBit podu hiç planlanamadı (`0/1`). | `fluentbit.tolerations` altına eşleşen toleration ekle (taint'i silme!). |
| **2** | **Kubernetes API RBAC** | `fluentbit.rbac.resources: [configmaps]` | `[FILTER] kubernetes` pod/namespace metadata'sını çekmek için API Server'a sorduğunda `403 Forbidden` aldı; Loki label'ları (`namespace`, `pod`, `app`) oluşmadı. | `resources` listesini `["pods", "namespaces"]` yap (`verbs: [get, list, watch]`, `*` kullanma). |
| **3** | **JSON Parsing & PII Maskeleme** | `parser.mergeLog: "Off"` ve `filters.modifyRules: []` | Uygulama JSON alanları (`request_id`, `service`, `level`) ham `log` metni içinde gömülü kaldı ve `auth_token` / `card_token` sırları Loki'ye açık metin aktı. | `mergeLog: "On"` yap ve `modifyRules` ile `auth_token` ile `card_token` alanlarını `"[REDACTED]"` olarak maskele. |
| **4** | **Loki Output Yönlendirme** | `output.lokiPort: 3101` | Loki Service `3100` portunu dinlediği için FluentBit `Connection refused` hatası alıp logları teslim edemedi. | `output.lokiPort: 3100` yap. |

### Tek Komutla Çözüm Uygulama

Hazır referans değer dosyası [solution/values-solution.yaml](./solution/values-solution.yaml) ile uygulayıp doğrulamak için:

```bash
helm --kube-context logging-lab-1 upgrade --install logging-lab ./helm/logging-pipeline \
  -f ./helm/logging-pipeline/values.yaml \
  -f ./solution/values-solution.yaml

kubectl --context logging-lab-1 -n kube-logging rollout status ds/fluent-bit --timeout=90s
./check.sh
```

*(Not: `fluentbit-daemonset.yaml` içindeki `checksum/config` annotation'ı sayesinde ConfigMap değiştiğinde FluentBit podu otomatik yeniden başlar.)*

### FluentBit Metriklerini (`:2020`) ve Grafana LogQL'i İnceleme

```bash
# FluentBit sağlık ve iç metriklerini canlı gör (Day 81):
kubectl --context logging-lab-1 -n kube-logging port-forward svc/fluent-bit 2020:2020
curl -s http://localhost:2020/api/v1/health
curl -s http://localhost:2020/api/v1/metrics/prometheus | grep fluentbit_output

# Grafana arayüzü (Day 83):
kubectl --context logging-lab-1 -n kube-logging port-forward svc/grafana 3000:3000
```

Grafana'da (**`http://localhost:3000`**, `admin`/`admin`) **Explore → Loki** ekranında dene:
1. `{namespace="shop-app"} | json` — `auth_token` ve `card_token` değerlerinin `"[REDACTED]"` olduğunu gör.
2. `{namespace="shop-app"} | json | request_id="<HERHANGI_BIR_REQ_ID>"` — tek isteğin `checkout-api` ve `payment-worker` boyunca nasıl korele edildiğini gör.
3. `{namespace="shop-app"} | json | level="ERROR"` — hata loglarını anında yakala.

---

<a id="-english-section"></a>
## 🇬🇧 English Section

### Root Cause Analysis (4 Defects)

| # | Layer | Broken State | Impact | Fix (`values.yaml`) |
| :-: | :--- | :--- | :--- | :--- |
| **1** | **DaemonSet Scheduling** | `fluentbit.tolerations: []` | Node taint `dedicated=logging-lab:NoSchedule` prevented the FluentBit DaemonSet pod from scheduling (`0/1`). | Add the matching toleration under `fluentbit.tolerations` (keep the node taint intact). |
| **2** | **Kubernetes Filter RBAC** | `fluentbit.rbac.resources: [configmaps]` | `[FILTER] kubernetes` received `403 Forbidden` when enriching logs with pod/namespace metadata. | Set `resources: [pods, namespaces]` with read-only verbs `[get, list, watch]` (no wildcard `*`). |
| **3** | **JSON Merge & PII Redaction** | `parser.mergeLog: "Off"`, `filters.modifyRules: []` | Structured JSON fields remained unparsed inside the raw `log` string and plaintext `auth_token` / `card_token` leaked into Loki. | Set `mergeLog: "On"` and configure `modifyRules` to replace `auth_token` and `card_token` with `"[REDACTED]"`. |
| **4** | **Loki Output Port** | `output.lokiPort: 3101` | Loki listens on port `3100`; FluentBit failed delivery with `Connection refused`. | Set `output.lokiPort: 3100`. |

### Apply Reference Solution & Verify

```bash
helm --kube-context logging-lab-1 upgrade --install logging-lab ./helm/logging-pipeline \
  -f ./helm/logging-pipeline/values.yaml \
  -f ./solution/values-solution.yaml

kubectl --context logging-lab-1 -n kube-logging rollout status ds/fluent-bit --timeout=90s
./check.sh
```
