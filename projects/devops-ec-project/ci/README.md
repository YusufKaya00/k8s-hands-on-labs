# CI Pipeline (GitHub Actions)

[build-push-update-tag.yml](./build-push-update-tag.yml) şablonunu her uygulama reposuna (`frontend`, `backend`, `admin`) `.github/workflows/` altına kopyala; yalnızca `env:` altındaki `IMAGE_NAME`, `VALUES_KEY`, `BUILD_ARG_ENV_FILE_SECRET` değerlerini değiştir.

| Repo | `IMAGE_NAME` | `VALUES_KEY` | Build-arg secret |
| :--- | :--- | :--- | :--- |
| frontend | `erasmus-connect-frontend` | `nextjs` | `FRONTEND_BUILD_ENV` |
| backend | `erasmus-connect-backend` | `express` | (boş) |
| admin | `erasmus-connect-admin` | `admin` | admin build env secret'ı |

## Gerekli GitHub Secrets (her uygulama reposunda)
- `AZURE_CREDENTIALS`: ACR push yetkili Service Principal JSON'u (`az ad sp create-for-rbac --role AcrPush --scopes <ACR_ID> --sdk-auth`)
- `ACR_NAME`: `erasmusconnectv1`
- `GITOPS_TOKEN`: GitOps reposuna `contents: write` yetkili PAT
- `FRONTEND_BUILD_ENV`: `.env.frontend-build` içeriği (secret olarak, Git'e girmez)

## Akış
`git push main` → build → `ACR:<kısa-sha>` push → `values-aks.yaml` tag commit → ArgoCD otomatik sync.
