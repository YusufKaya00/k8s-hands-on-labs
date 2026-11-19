# CI Pipeline (GitHub Actions — İzole AKS Akışı)

Canlı uygulama reposunun (`YusufKaya00/Erasmus-Connect`) mevcut CI akışına hiç dokunmamak için pipeline doğrudan bu repoda tanımlıdır:
**[`.github/workflows/erasmus-aks-ci.yml`](../../../.github/workflows/erasmus-aks-ci.yml)**

## Nasıl Çalışır?

1. GitHub'da **`k8s-hands-on-labs` → Actions → Erasmus Connect AKS CI → Run workflow** butonuna tıkla.
2. Açılan menüden iki seçim yap:
   - **`service`:** `all`, `backend`, `frontend` veya `admin`
   - **`app_ref`:**
     - `develop` *(varsayılan)* → monorepo ortak paketi (`packages/types`) sebebiyle 3 servis de **repo kökü (`.`)** context'i ile build edilir.
     - `main` → her servis kendi klasör context'i (`./backend`, `./frontend`, `./admin-frontend`) ile build edilir.
3. Workflow şunları sırayla yapar:
   - `YusufKaya00/Erasmus-Connect` reposunu `APP_REPO_TOKEN` ile read-only çeker ve 7 karakterlik commit SHA'sını alır.
   - Seçilen servisleri paralel build edip `erasmusconnectv1.azurecr.io/<imaj>:<app_sha>` olarak ACR'ye pushlar.
   - `projects/devops-ec-project/helm/erasmus-connect/values-aks.yaml` içindeki ilgili `image.tag` alanlarını yerleşik `GITHUB_TOKEN` ile günceller ve `main` branch'ine commit'ler.
   - ArgoCD değişikliği algılayıp AKS kümesine otomatik deploy eder.

| Servis | Klasör / Dockerfile | ACR İmaj Adı | `values-aks.yaml` Anahtarı | Build-arg Secret |
| :--- | :--- | :--- | :--- | :--- |
| `backend` | `backend/Dockerfile` | `erasmus-connect-backend` | `express` | *(gerekmez)* |
| `frontend` | `frontend/Dockerfile` | `erasmus-connect-frontend` | `nextjs` | `FRONTEND_BUILD_ENV` |
| `admin` | `admin-frontend/Dockerfile` | `erasmus-connect-admin` | `admin` | `ADMIN_BUILD_ENV` |

## Gerekli GitHub Secrets (`YusufKaya00/k8s-hands-on-labs` reposunda)

**Settings → Secrets and variables → Actions → New repository secret:**

1. **`APP_REPO_TOKEN`**: `YusufKaya00/Erasmus-Connect` (private) reposu için **Fine-grained PAT** (`Repository access: Only select repositories → Erasmus-Connect`, yetki: **`Contents: Read-only`**).
2. **`AZURE_CREDENTIALS`**: ACR üzerinde yalnızca `AcrPush` yetkili Service Principal JSON çıktısı:
   ```bash
   ACR_ID=$(az acr show --name erasmusconnectv1 --query id -o tsv)
   az ad sp create-for-rbac --name "sp-erasmus-acr-push" --role AcrPush --scopes "$ACR_ID" --sdk-auth
   ```
3. **`ACR_NAME`**: `erasmusconnectv1`
4. **`FRONTEND_BUILD_ENV`**: `.env.frontend-build` içeriği (`NEXT_PUBLIC_*` satırları; API/WS URL'leri Bilet 24'teki sabit IP'ye işaret etmeli).
5. **`ADMIN_BUILD_ENV`**: Admin Vite build değişkeni (`VITE_BACKEND_URL=http://<SABIT_IP>.nip.io` vb.).

> **Not:** Workflow bu repoda çalıştığı ve `permissions: contents: write` kullandığı için ekstra bir `GITOPS_TOKEN` oluşturmana gerek yoktur.
