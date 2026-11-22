# Ders 03 / Lab 1 — HashiCorp Vault, Dynamic Credentials & K8s Agent Injector (Uygulamalı Playground)

> **[🇹🇷 Türkçe](#-türkçe-bölüm) | [🇬🇧 English](#-english-section)**  
> **Ortam / Runtime:** %100 Yerel Minikube (`-p vault-lab-1`, `$0`) · **Mod:** Arıza labı değil — adım adım kendin uygulayıp deneyeceğin **sağlıklı çalışma ortamı (Sandbox)**

---

<a id="-türkçe-bölüm"></a>
## 🇹🇷 Türkçe Bölüm

### 🎯 Bu Ortamda Neler Var?
- **`vault` namespace:** Resmi `hashicorp/vault` Helm chart'ı (Raft storage + Web UI + **Vault Agent Injector** sidecar).
- **`demo-app` namespace:** Örnek `orders` tablosu hazır **PostgreSQL 16** veritabanı (`vaultadmin` / `vaultadminpass`, db: `shop`) ve `payments-sa` ServiceAccount'u.

### 🚀 Kurulum

```bash
cd lessons/03-secrets-management-vault/lab-1
./setup.sh
```
> **Not:** Kurulum bittiğinde `vault-0` pod'unun `0/1 Running` görünmesi **normaldir** — gerçek Vault güvenlik gereği başlangıçta **Sealed (mühürlü)** açılır. Aşağıdaki 1. adımda kendin açacaksın.

---

### Adım 1 — Vault `init`, `unseal`, `login` & Web UI (`Day 36`)

Vault'un durumunu gör ve başlat (5 anahtar üretir, açmak için 3'ü gerekir — Shamir's Secret Sharing):

```bash
# Durumu gör (Initialized: false, Sealed: true):
kubectl --context vault-lab-1 -n vault exec vault-0 -- vault status

# Vault'u initialize et (çıktıdaki Unseal Key 1-3 ve Initial Root Token'ı not et!):
kubectl --context vault-lab-1 -n vault exec vault-0 -- vault operator init -key-shares=5 -key-threshold=3
```

Çıktıdaki ilk 3 **Unseal Key** ile Vault'un mührünü aç:
```bash
kubectl --context vault-lab-1 -n vault exec vault-0 -- vault operator unseal <UNSEAL_KEY_1>
kubectl --context vault-lab-1 -n vault exec vault-0 -- vault operator unseal <UNSEAL_KEY_2>
kubectl --context vault-lab-1 -n vault exec vault-0 -- vault operator unseal <UNSEAL_KEY_3>

# Artık Sealed: false ve pod 1/1 Ready olmalı:
kubectl --context vault-lab-1 -n vault get pods
```

Vault içine girip Root Token ile oturum aç:
```bash
kubectl --context vault-lab-1 -n vault exec -it vault-0 -- sh
# Pod içinde:
vault login <INITIAL_ROOT_TOKEN>
```

*(İsteğe bağlı — Web UI)* Ayrı terminalde:
```bash
kubectl --context vault-lab-1 -n vault port-forward svc/vault-ui 8200:8200
# Tarayıcıda aç: http://localhost:8200 (Method: Token -> <INITIAL_ROOT_TOKEN>)
```

---

### Adım 2 — KV v2 Secrets Engine, Versiyonlama & `/data/` Policy Tuzağı (`Day 37`)

`vault-0` pod'unun içindeki terminalde devam et:

```bash
# 1. 'app/' path'inde KV v2 secrets engine aç:
vault secrets enable -path=app kv-v2

# 2. Secret yaz (v1):
vault kv put app/payments api_key="sk-live-v1" db_host="postgres.demo-app.svc.cluster.local"

# 3. Güncelle (v2) ve eski versiyonun hâlâ saklandığını gör:
vault kv put app/payments api_key="sk-live-v2" db_host="postgres.demo-app.svc.cluster.local"
vault kv get app/payments
vault kv get -version=1 app/payments

# 4. HCL Policy yaz — DİKKAT: CLI'da 'app/payments' ama policy/API'de 'app/data/payments' yazılır!
vault policy write payments-policy - <<'EOF'
path "app/data/payments" {
  capabilities = ["read"]
}
EOF
```

---

### Adım 3 — Dynamic PostgreSQL Credentials & Lease/TTL (`Day 38`)

Statik veritabanı şifresi yerine Vault'un **anlık, 1 dakikalık süreli PostgreSQL kullanıcısı** üretmesini kur (`vault-0` içinde):

```bash
# 1. Database secrets engine'i aç:
vault secrets enable database

# 2. Vault'u demo-app içindeki PostgreSQL 16'ya bağla:
vault write database/config/shop-db \
  plugin_name=postgresql-database-plugin \
  allowed_roles="readonly-role" \
  connection_url="postgresql://{{username}}:{{password}}@postgres.demo-app.svc.cluster.local:5432/shop?sslmode=disable" \
  username="vaultadmin" \
  password="vaultadminpass"

# 3. 1 dakikalık (default_ttl=1m) dinamik readonly rolü tanımla:
vault write database/roles/readonly-role \
  db_name=shop-db \
  creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; GRANT SELECT ON ALL TABLES IN SCHEMA public TO \"{{name}}\";" \
  default_ttl="1m" \
  max_ttl="5m"

# 4. Anlık dinamik kullanıcı ve şifre üret!
vault read database/creds/readonly-role
```

Şimdi ayrı terminalde üretilen geçici kullanıcıyla PostgreSQL'e bağlanıp sorgu at, ardından 1 dakika sonra kullanıcının otomatik silindiğini gör:
```bash
# Üretilen <DYNAMIC_USER> ve <DYNAMIC_PASS> ile bağlan:
kubectl --context vault-lab-1 -n demo-app exec -it deploy/postgres -- \
  env PGPASSWORD='<DYNAMIC_PASS>' psql -U '<DYNAMIC_USER>' -d shop -c "SELECT * FROM orders;"

# PostgreSQL'deki aktif rolleri gör (v-token-readonly-... kullanıcısını göreceksin; 1 dk sonra kaybolur!):
kubectl --context vault-lab-1 -n demo-app exec deploy/postgres -- \
  psql -U vaultadmin -d shop -c "\du"
```

---

### Adım 4 — Kubernetes Auth & Vault Agent Sidecar Injector (`Day 39`)

Uygulama koduna hiç Vault SDK eklemeden, sadece Pod annotation'larıyla `/vault/secrets/config.txt` dosyasına secret enjekte et:

```bash
# vault-0 pod'u içinde Kubernetes auth metodunu aç ve yapılandır:
vault auth enable kubernetes

vault write auth/kubernetes/config \
  kubernetes_host="https://$KUBERNETES_PORT_443_TCP_ADDR:443"

# demo-app içindeki 'payments-sa' ServiceAccount'unu 'payments-policy' ile eşle:
vault write auth/kubernetes/role/payments-role \
  bound_service_account_names=payments-sa \
  bound_service_account_namespaces=demo-app \
  policies=payments-policy \
  ttl=1h
```

Şimdi kendi terminalinden [manifests/app-pod.yaml](./manifests/app-pod.yaml) dosyasını incele ve uygula:
```bash
kubectl --context vault-lab-1 apply -f manifests/app-pod.yaml
kubectl --context vault-lab-1 -n demo-app get pods -w

# Vault Agent sidecar'ının oluşturduğu secret dosyasını oku:
kubectl --context vault-lab-1 -n demo-app exec payments-app -c app -- cat /vault/secrets/config.txt
```
> **Deney:** `vault-0` içinde `vault kv put app/payments api_key="sk-live-v3" db_host="postgres.demo-app.svc.cluster.local"` yapıp birkaç saniye bekle ve `cat /vault/secrets/config.txt` komutunu tekrar çalıştır — Vault Agent sidecar'ının dosyayı otomatik güncellediğini göreceksin!

---

### Adım 5 — K8s Native Secret Neden Tek Başına Yetersiz? (`Day 40–41`)

```bash
# Standart K8s Secret oluştur:
kubectl --context vault-lab-1 -n demo-app create secret generic plain-demo --from-literal=api_key=super-secret-123

# Sadece base64 olduğunu kendi gözünle gör (şifreleme değildir!):
kubectl --context vault-lab-1 -n demo-app get secret plain-demo -o jsonpath='{.data.api_key}' | base64 -d; echo ""
```

### 🧹 Temizlik

```bash
./cleanup.sh
```

---

<a id="-english-section"></a>
## 🇬🇧 English Section

### 🎯 What Is Included?
A clean, healthy **100% local Minikube (`-p vault-lab-1`, `$0`)** hands-on playground (not a broken troubleshooting lab) with:
- Official **HashiCorp Vault** Helm chart (Raft + Web UI + **Vault Agent Injector**) in `vault` namespace.
- Pre-seeded **PostgreSQL 16** (`shop` DB, `orders` table) and `payments-sa` `ServiceAccount` in `demo-app` namespace.

### 🚀 Quick Start

```bash
cd lessons/03-secrets-management-vault/lab-1
./setup.sh
```

Follow the 5 guided exercises above in order:
1. **Init & Unseal (`Day 36`):** `vault operator init`, `unseal`, `login`, and explore the Web UI (`port-forward svc/vault-ui 8200:8200`).
2. **KV v2 & `/data/` Policy Path (`Day 37`):** Enable `kv-v2` at `app/`, test versioning, and write an HCL policy targeting `app/data/payments`.
3. **Dynamic PostgreSQL Credentials (`Day 38`):** Configure `database` secrets engine against `postgres.demo-app.svc.cluster.local:5432`, create `readonly-role` (`default_ttl=1m`), generate temporary DB logins, and watch them auto-expire.
4. **Kubernetes Auth & Vault Agent Injector (`Day 39`):** Bind `demo-app/payments-sa` to `payments-policy`, apply [manifests/app-pod.yaml](./manifests/app-pod.yaml), and watch `/vault/secrets/config.txt` live-update when you rotate the secret in Vault.
5. **K8s Native Secrets vs Vault (`Day 40–41`):** Compare plain base64 K8s `Secret` objects with Vault's lease/audit/rotation model.

Tear down anytime with `./cleanup.sh`.
