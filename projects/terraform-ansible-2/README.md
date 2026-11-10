# 🏗️ Terraform + Ansible Lab 2: Multi-Node K3s Cluster & Helm Application Deployment on Azure

[🇬🇧 English](#-english-version) | [🇹🇷 Türkçe](#-türkçe-bölüm)

---

## 🇬🇧 English Version

### 1. Overview
Building on Lab 1, this project provisions a **Multi-Node Kubernetes Topology (1 Master + 1 Worker)** on Microsoft Azure using **Terraform**, automates cross-node token extraction and cluster join via **Ansible**, and deploys a containerized web application using **Helm 3**.

### 2. Architecture & Workflow
1. **Terraform (`terraform/`):** Provisions `vm-master` and `vm-worker` inside an Azure VNet (`10.0.0.0/16`) and populates `../ansible/hosts.ini` with `[master]` and `[worker]` host groups.
2. **Ansible Multi-Play Orchestration (`ansible/`):**
   - Disables swap and prepares kernel networking on all nodes.
   - Installs K3s Server on `vm-master` and extracts `/var/lib/rancher/k3s/server/node-token` using `slurp` + `b64decode`.
   - Joins `vm-worker` to the cluster as a K3s Agent using the extracted token and master's private IP.
3. **Helm Application Chart (`helm/`):** Packages and deploys the multi-replica web workload with Service and Ingress/LoadBalancer exposure.

### 3. Quick Start
```bash
# 1. Provision 1 Master + 1 Worker VM on Azure
cd /home/ysf/k8s-hands-on-labs/projects/terraform-ansible-2/terraform
terraform init
terraform apply -auto-approve

# 2. Bootstrap Multi-Node K3s Cluster via Ansible
cd ../ansible
ansible-playbook -i hosts.ini playbook.yml
```

### 4. Cleanup
```bash
cd /home/ysf/k8s-hands-on-labs/projects/terraform-ansible-2/terraform
terraform destroy -auto-approve
```

---

## 🇹🇷 Türkçe Bölüm

### 1. Genel Bakış
Bu proje, **Terraform** ile Azure üzerinde **Çok Düğümlü (1 Master + 1 Worker)** sanal makine altyapısı kurmayı, **Ansible** ile Master düğümden `node-token` bilgisini (`slurp` + `b64decode`) çekip Worker düğümü kümeye otomatik dahil etmeyi (Cluster Join) ve **Helm** ile uygulama dağıtmayı gösterir.

### 2. Kurulum Adımları
```bash
# 1. Terraform ile Master ve Worker sunucularını oluştur:
cd /home/ysf/k8s-hands-on-labs/projects/terraform-ansible-2/terraform
terraform init
terraform apply -auto-approve

# 2. Ansible ile K3s Master + Worker kurulumunu gerçekleştir:
cd ../ansible
ansible-playbook -i hosts.ini playbook.yml
```
