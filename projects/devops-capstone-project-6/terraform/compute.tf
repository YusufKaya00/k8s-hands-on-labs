# ==============================================================================
# SUPPLYSHIELD DEVSECOPS PLATFORM - COMPUTE LAYER (3-NODE RKE2 CLUSTER)
# ==============================================================================
# Bu dosya (compute.tf), 3 düğümlü RKE2 Kubernetes kümemizi oluşturan sanal
# makineleri (1x Master `Standard_B2s_v2` + 2x Worker `Standard_B2s`), ağ
# kartlarını (NIC) ve genel IP (Public IP) atamalarını tanımlar.
#
# NEDEN PROD ORTAMINDA BÖYLEDİR VS LAB ORTAMI?
# 1. Düğüm Boyutlandırması ve Disk Planlaması (Right-Sizing):
#    - `vm-master` (`Standard_B2s_v2`: 2 vCPU / 8 GB RAM / 50 GB SSD - `10.40.1.4` - Public IP #1):
#      RKE2 Control Plane (etcd, kube-apiserver, NGINX Ingress) + Rancher UI + ArgoCD +
#      Prometheus/Grafana/Alertmanager bileşenlerini taşır. 8 GB RAM ve 50 GB SSD
#      sayesinde yönetim düzlemi ve metrik veritabanı (TSDB) asla darboğaza girmez.
#    - `vm-worker-secops` (`Standard_B2s`: 2 vCPU / 4 GB RAM / 40 GB SSD - `10.40.1.5` - Özel IP, NAT GW):
#      Tedarik zinciri güvenliği (Supply Chain Security) ve CI/CD katmanını (**Harbor OCI Registry** +
#      **Trivy Zafiyet Tarayıcısı** + **Jenkins Controller & Dinamik K8s Kaniko Build Pod'ları**)
#      taşır. `dedicated=secops:NoSchedule` Taint'i ile uygulama pod'larından izole edilir.
#      40 GB SSD disk sayesinde Harbor konteyner imaj katmanları ve Trivy CVE veritabanı
#      için bolca depolama alanı sağlanır.
#    - `vm-worker-app` (`Standard_B2s`: 2 vCPU / 4 GB RAM / 40 GB SSD - `10.40.1.6` - Public IP #2):
#      Canlı iş yüklerini (**SupplyShield FastAPI App x2**) ve veri katmanını
#      (**PostgreSQL 16 + Redis**) taşır.
# 2. `for_each` Kullanımı:
#    `count` yerine `for_each` kullanarak durum dosyasında (state) kaynakları
#    `vm_worker["vm-worker-secops"]` ve `vm_worker["vm-worker-app"]` anahtarlarıyla
#    saklıyoruz; böylece indeks kayması olmadan güvenli topoloji yönetimi yapılır.
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Yerel Değişkenler (Locals) - 2 Worker Düğümünün Topoloji Haritası
# ------------------------------------------------------------------------------
locals {
  workers = {
    # Düğüm 1: SecOps Katmanı (Harbor OCI Registry + Trivy Scanner + Jenkins CI/CD)
    # Public IP YOK -> NAT Gateway (Public IP #3) üzerinden güvenli çıkış yapar.
    "vm-worker-secops" = {
      private_ip = "10.40.1.5"
      role       = "secops"
    }
    # Düğüm 2: Uygulama ve Veri Katmanı (SupplyShield FastAPI x2 + PostgreSQL 16 + Redis)
    # Public IP #2 -> Canlı uygulama Ingress trafiğini (`app.<APP_IP>.nip.io`) karşılar.
    "vm-worker-app" = {
      private_ip = "10.40.1.6"
      role       = "app"
    }
  }
}

# ==============================================================================
# BÖLÜM A: KUBERNETES CONTROL PLANE (MASTER & BASTION NODE)
# ==============================================================================

# ------------------------------------------------------------------------------
# 2. Master Düğümü Genel IP Adresi (Public IP #1 of 3)
# ------------------------------------------------------------------------------
# Bu IP adresi iki kritik görev üstlenir:
#   a) SSH Bastion / Jump Host: Özel alt ağdaki `vm-worker-secops` (10.40.1.5) düğümüne
#      Ansible ile SSH ProxyCommand üzerinden güvenli tünel açmak.
#   b) Yönetim ve SecOps Ingress Kapısı: Harbor, Jenkins, Rancher, ArgoCD ve Grafana
#      arayüzlerini `*.<MASTER_IP>.nip.io` wildcard DNS üzerinden dış dünyaya sunmak.
resource "azurerm_public_ip" "pip_master" {
  name                = "pip-supplyshield-master"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = {
    project    = "supplyshield-6"
    quota_slot = "1-of-3-master"
  }
}

# ------------------------------------------------------------------------------
# 3. Master Düğümü Ağ Kartı (Network Interface - NIC)
# ------------------------------------------------------------------------------
# Alt ağdaki ilk kullanılabilir IP olan `10.40.1.4` adresini Statik olarak atıyoruz.
# Control Plane IP'sinin değişmemesi, etcd küme sağlığı, TLS sertifikalarının
# (SAN - Subject Alternative Name) geçerliliği ve düğüm içi `/etc/hosts` Hairpin NAT
# çözümlemesi için hayati önem taşır.
resource "azurerm_network_interface" "nic_master" {
  name                = "nic-vm-master"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.40.1.4"
    public_ip_address_id          = azurerm_public_ip.pip_master.id
  }

  tags = {
    project = "supplyshield-6"
    role    = "control-plane"
  }
}

# ------------------------------------------------------------------------------
# 4. Master Sanal Makinesi (`vm-master` - Standard_B2s_v2 / 2 vCPU / 8 GB RAM)
# ------------------------------------------------------------------------------
resource "azurerm_linux_virtual_machine" "vm_master" {
  name                = "vm-master"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  size                = var.master_vm_size
  admin_username      = var.admin_username

  # Güvenlik Sertleştirmesi: Parola ile girişi tamamen kapatıp yalnızca SSH anahtarı kabul ediyoruz.
  disable_password_authentication = true

  network_interface_ids = [
    azurerm_network_interface.nic_master.id,
  ]

  admin_ssh_key {
    username   = var.admin_username
    public_key = file(pathexpand(var.ssh_public_key_path))
  }

  # etcd veritabanının düşük gecikmeli (Low Latency fsync/wal) yazma performansı,
  # Prometheus TSDB blokları ve konteyner imajları için 50 GB StandardSSD_LRS kullanıyoruz.
  os_disk {
    name                 = "osdisk-vm-master"
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
    disk_size_gb         = 50
  }

  # Ubuntu Server 24.04 LTS (Noble Numbat) - En güncel LTS Linux çekirdeği (Kernel 6.8).
  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  tags = {
    project = "supplyshield-6"
    role    = "control-plane"
  }
}

# ==============================================================================
# BÖLÜM B: KUBERNETES WORKER NODES (2x İŞÇİ DÜĞÜMÜ - SECOPS & APP)
# ==============================================================================

# ------------------------------------------------------------------------------
# 5. Uygulama İşçi Düğümü Genel IP Adresi (Public IP #2 of 3)
# ------------------------------------------------------------------------------
# Öğrenci aboneliğimizdeki 2. Public IP hakkımızı `vm-worker-app` düğümüne
# veriyoruz. Böylece son kullanıcıların canlı uygulama trafiği (`app.<APP_IP>.nip.io`)
# doğrudan uygulama düğümüne gelebilirken, `vm-worker-secops` düğümü doğrudan
# internete açılmadan gizli (private) kalır.
resource "azurerm_public_ip" "pip_app" {
  name                = "pip-supplyshield-app"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = {
    project    = "supplyshield-6"
    quota_slot = "2-of-3-app-worker"
  }
}

# ------------------------------------------------------------------------------
# 6. Worker Düğümleri Ağ Kartları (2x NIC - `for_each` & Ternary Operatörü)
# ------------------------------------------------------------------------------
resource "azurerm_network_interface" "nic_worker" {
  for_each = local.workers

  name                = "nic-${each.key}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Static"
    private_ip_address            = each.value.private_ip

    # KOŞULLU ÜÇLÜ İFADE (Conditional Ternary Expression):
    # Eğer şu an oluşturulan ağ kartı "vm-worker-app" düğümüne aitse `pip_app.id`
    # genel IP'sini bağla; "vm-worker-secops" düğümüyse `null` ata (Public IP verme,
    # çıkışlarını NAT Gateway üzerinden yap!).
    public_ip_address_id = each.key == "vm-worker-app" ? azurerm_public_ip.pip_app.id : null
  }

  tags = {
    project = "supplyshield-6"
    role    = each.value.role
  }
}

# ------------------------------------------------------------------------------
# 7. Worker Sanal Makineleri (2x `Standard_B2s` / 2 vCPU / 4 GB RAM / 40 GB SSD)
# ------------------------------------------------------------------------------
resource "azurerm_linux_virtual_machine" "vm_worker" {
  for_each = local.workers

  name                = each.key
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  size                = var.worker_vm_size
  admin_username      = var.admin_username

  disable_password_authentication = true

  network_interface_ids = [
    azurerm_network_interface.nic_worker[each.key].id,
  ]

  admin_ssh_key {
    username   = var.admin_username
    public_key = file(pathexpand(var.ssh_public_key_path))
  }

  # Harbor OCI Registry katmanları (blobs), Trivy güvenlik açığı veritabanı (CVE DB),
  # Jenkins çalışma alanı ve PostgreSQL/Redis kalıcı hacimleri (PVC) için 40 GB
  # StandardSSD_LRS disk tahsis ediyoruz (kubelet DiskPressure / eviction riskini önler).
  os_disk {
    name                 = "osdisk-${each.key}"
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
    disk_size_gb         = 40
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  tags = {
    project = "supplyshield-6"
    role    = each.value.role
  }
}
