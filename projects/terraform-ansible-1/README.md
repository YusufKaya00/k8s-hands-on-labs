# 🏗️ Terraform + Ansible Lab 1: Automated Azure VM & K3s Kubernetes Bootstrap

[🇬🇧 English](#-english-version) | [🇹🇷 Türkçe](#-türkçe-bölüm)

---

## 🇬🇧 English Version

### 1. Overview
This project introduces **Infrastructure as Code (IaC)** and **Configuration Management** by combining **Terraform** and **Ansible** to automatically provision a Linux Virtual Machine on Microsoft Azure, dynamically generate the Ansible `hosts.ini` inventory via `local_file`, and bootstrap a production-ready **K3s Kubernetes** node with zero manual SSH intervention.

### 2. Key Engineering Concepts
- **Terraform Provisioning (`terraform-1/terraform/`):** Creates Resource Group, Virtual Network (`10.0.0.0/16`), Subnet (`10.0.1.0/24`), Network Security Group (ports `22`, `80`, `6443`), Static Public IP, NIC, and Ubuntu 24.04 LTS VM (`Standard_B2s`).
- **Automated Inventory Handoff:** Uses Terraform `local_file` resource to automatically write the provisioned VM's Public IP into `../ansible/hosts.ini`.
- **Idempotent Ansible Playbook (`terraform-1/ansible/playbook.yml`):** Disables swap, installs `containerd` and system dependencies, bootstraps K3s, and configures `/etc/rancher/k3s/k3s.yaml` permissions.

### 3. Quick Start
```bash
# 1. Provision Azure VM and generate Ansible inventory
cd /home/ysf/k8s-hands-on-labs/projects/terraform-ansible-1/terraform-1/terraform
terraform init
terraform apply -auto-approve

# 2. Bootstrap K3s via Ansible
cd ../ansible
ansible-playbook -i hosts.ini playbook.yml
```

### 4. Cleanup
```bash
cd /home/ysf/k8s-hands-on-labs/projects/terraform-ansible-1/terraform-1/terraform
terraform destroy -auto-approve
```

---

## 🇹🇷 Türkçe Bölüm

### 1. Genel Bakış
Bu proje, **Terraform (Altyapı Otomasyonu)** ve **Ansible (Konfigürasyon Yönetimi)** araçlarını birleştirerek Microsoft Azure üzerinde tek komutla sanal makine oluşturmayı, `local_file` ile dinamik Ansible envanteri (`hosts.ini`) üretmeyi ve sunucu üzerine el değmeden **K3s Kubernetes** kurmayı öğretir.

### 2. Kurulum Adımları
```bash
# 1. Terraform ile Azure altyapısını oluştur ve hosts.ini dosyasını üret:
cd /home/ysf/k8s-hands-on-labs/projects/terraform-ansible-1/terraform-1/terraform
terraform init
terraform apply -auto-approve

# 2. Ansible ile K3s kümesini kur:
cd ../ansible
ansible-playbook -i hosts.ini playbook.yml
```
