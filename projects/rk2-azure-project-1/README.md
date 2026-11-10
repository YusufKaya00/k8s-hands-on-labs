# ☸️ RKE2 5-Node High-Isolation Architecture on Azure (Project 1)

[🇬🇧 English](#-english-version) | [🇹🇷 Türkçe](#-türkçe-bölüm)

---

## 🇬🇧 English Version

### 1. Overview
This project demonstrates a **5-Node High-Isolation RKE2 Kubernetes Cluster** on Microsoft Azure, enforcing strict workload separation across dedicated infrastructure, relational database, NoSQL database, and stateless application nodes using **Node Labels**, **Taints & Tolerations**, **Local-Path Persistent Storage**, **CoreDNS Service Discovery**, and **NGINX Ingress Routing**.

### 2. 5-Node Cluster Topology

| Node Name | Role Label | Taint | Hosted Workloads |
| :--- | :--- | :--- | :--- |
| **`vm-master`** | `control-plane` | `CriticalAddonsOnly=true:NoSchedule` | RKE2 Server, etcd, CoreDNS, NGINX Ingress Controller |
| **`vm-worker-infra`** | `role=infra` | `dedicated=infra:NoSchedule` | **Redis** (`helm-values/redis-values.yaml`) |
| **`vm-worker-pg`** | `role=db-sql` | `dedicated=db-sql:NoSchedule` | **PostgreSQL** (`helm-values/postgres-values.yaml`) |
| **`vm-worker-mongo`** | `role=db-nosql` | `dedicated=db-nosql:NoSchedule` | **MongoDB** (`helm-values/mongo-values.yaml`) |
| **`vm-worker-app`** | `role=app` | None (Untainted) | **Multi-DB FastAPI Web App** (`app/` & `my-app/`) |

### 3. Repository Structure
```text
rk2-azure-project-1/
├── helm-values/                # Node-pinned Bitnami Helm values (Redis, PostgreSQL, MongoDB)
├── app/                        # Kubernetes Deployment, Service & Ingress manifests
├── my-app/                     # Python FastAPI multi-database connector & Helm chart
└── rk2-lab.pdf                 # Detailed architectural lab guide
```

### 4. Quick Start (On RKE2 Master Node)
```bash
# 1. Create namespaces
kubectl create ns data
kubectl create ns app

# 2. Deploy isolated databases onto their dedicated tainted nodes
helm repo add bitnami https://charts.bitnami.com/bitnami
helm upgrade --install redis bitnami/redis -n data -f helm-values/redis-values.yaml
helm upgrade --install postgres bitnami/postgresql -n data -f helm-values/postgres-values.yaml
helm upgrade --install mongodb bitnami/mongodb -n data -f helm-values/mongo-values.yaml

# 3. Deploy the multi-database web application
helm upgrade --install my-app ./my-app -n app
```

---

## 🇹🇷 Türkçe Bölüm

### 1. Genel Bakış
Bu proje, Microsoft Azure üzerinde **5 Düğümlü Yüksek İzolasyonlu RKE2 Kubernetes Kümesi** kurulumunu ve iş yüklerinin **NodeSelector**, **Taint & Toleration**, **Local-Path CSI Depolama**, **CoreDNS Servis Keşfi** ve **NGINX Ingress** kullanılarak donanım seviyesinde birbirinden nasıl ayrıldığını gösterir.

### 2. 5 Sunuculu İzolasyon Topolojisi
- **`vm-master`:** RKE2 Control Plane (`CriticalAddonsOnly=true:NoSchedule`)
- **`vm-worker-infra`:** Redis önbellek katmanı (`dedicated=infra:NoSchedule`, `role=infra`)
- **`vm-worker-pg`:** PostgreSQL ilişkisel veritabanı (`dedicated=db-sql:NoSchedule`, `role=db-sql`)
- **`vm-worker-mongo`:** MongoDB NoSQL veritabanı (`dedicated=db-nosql:NoSchedule`, `role=db-nosql`)
- **`vm-worker-app`:** FastAPI uygulaması (`role=app`, Taint yok)
