# ==============================================================================
# SUPPLYSHIELD DEVSECOPS PLATFORM - OUTPUTS & DYNAMIC ANSIBLE INVENTORY
# ==============================================================================
# Bu dosya (outputs.tf), iki kritik görevi yerine getirir:
# 1. Zero-Touch IaC -> Configuration Management Köprüsü:
#    Azure üzerinde dinamik olarak tahsis edilen Public IP adreslerini ve yerel
#    Worker topolojisini (`local.workers`) alarak `templates/hosts.ini.tftpl`
#    şablonunu işler ve doğrudan `../ansible/inventory/hosts.ini` dosyasını üretir.
#    Böylece `terraform apply` biter bitmez hiçbir IP kopyala-yapıştır işlemine
#    gerek kalmadan `ansible-playbook site.yml` çalıştırılabilir!
# 2. Platform ve DevSecOps Erişim Çıktıları (Outputs):
#    Harbor OCI Registry, Jenkins CI/CD, ArgoCD, Grafana, Rancher UI ve
#    SupplyShield Canlı Uygulama adreslerini `nip.io` wildcard DNS
#    formatında terminale yazdırır.
#
# NEDEN PROD ORTAMINDA BÖYLEDİR VS LAB ORTAMI?
# - Prod'da: Terraform çıktılarını ExternalDNS + Cloudflare / Azure DNS Zone
#   ile gerçek kurumsal alan adlarına (`harbor.sirket.com`, `jenkins.sirket.com`) bağlarız.
# - Lab'da: Ücretsiz ve anında çalışan `nip.io` wildcard DNS kullanarak gerçek
#   Host-tabanlı NGINX Ingress yönlendirmesini DNS satın almadan simüle ediyoruz.
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Dinamik Ansible Envanter Dosyası Üretimi (`../ansible/inventory/hosts.ini`)
# ------------------------------------------------------------------------------
resource "local_file" "ansible_inventory" {
  # `templatefile(path, vars)` fonksiyonu, `.tftpl` şablon dosyasını okur ve
  # ikinci argümandaki değişken haritasını şablonun içine enjekte eder.
  content = templatefile("${path.module}/templates/hosts.ini.tftpl", {
    master_public_ip     = azurerm_public_ip.pip_master.ip_address
    app_public_ip        = azurerm_public_ip.pip_app.ip_address
    app_worker_public_ip = azurerm_public_ip.pip_app.ip_address
    admin_username       = var.admin_username
    workers              = local.workers
  })

  # Terraform dizininden bir üst dizine çıkıp `ansible/inventory/hosts.ini` konumuna yazar.
  filename        = "${path.module}/../ansible/inventory/hosts.ini"
  file_permission = "0644"

  # Envanter dosyasının yalnızca tüm sanal makineler hazır olduğunda yazılmasını garanti eder.
  depends_on = [
    azurerm_linux_virtual_machine.vm_master,
    azurerm_linux_virtual_machine.vm_worker
  ]
}

# ------------------------------------------------------------------------------
# 2. Altyapı Genel IP Çıktıları (Public IP Outputs)
# ------------------------------------------------------------------------------
output "master_public_ip" {
  description = "vm-master (RKE2 Control Plane, Platform/SecOps Ingress & SSH Bastion) Genel IP adresi (Public IP #1)."
  value       = azurerm_public_ip.pip_master.ip_address
}

output "app_worker_public_ip" {
  description = "vm-worker-app (SupplyShield FastAPI x2, PostgreSQL 16 & Redis) Genel IP adresi (Public IP #2)."
  value       = azurerm_public_ip.pip_app.ip_address
}

output "nat_gateway_public_ip" {
  description = "NAT Gateway (vm-worker-secops özel SecOps düğümünün güvenli Outbound SNAT çıkış IP'si - Public IP #3)."
  value       = azurerm_public_ip.pip_natgw.ip_address
}

# ------------------------------------------------------------------------------
# 3. DevSecOps, Yönetim ve Gözlemlenebilirlik URL Çıktıları (`nip.io`)
# ------------------------------------------------------------------------------
output "harbor_url" {
  description = "Harbor Kurumsal OCI Konteyner Kayıt Defteri ve Trivy Güvenlik Tarayıcısı arayüzü."
  value       = "http://harbor.${azurerm_public_ip.pip_master.ip_address}.nip.io"
}

output "jenkins_url" {
  description = "Jenkins DevSecOps CI/CD Otomasyon Sunucusu (Dinamik K8s Pod Agent'ları ile) erişim adresi."
  value       = "http://jenkins.${azurerm_public_ip.pip_master.ip_address}.nip.io"
}

output "argocd_url" {
  description = "ArgoCD GitOps Sürekli Teslimat (Continuous Delivery) Arayüzü erişim adresi."
  value       = "http://argocd.${azurerm_public_ip.pip_master.ip_address}.nip.io"
}

output "grafana_url" {
  description = "Grafana & Prometheus DevSecOps Gözlemlenebilirlik Panosu erişim adresi."
  value       = "http://grafana.${azurerm_public_ip.pip_master.ip_address}.nip.io"
}

output "rancher_url" {
  description = "Rancher Çoklu Küme Yönetim Arayüzü (cattle-system) erişim adresi."
  value       = "https://rancher.${azurerm_public_ip.pip_master.ip_address}.nip.io"
}

output "app_url" {
  description = "SupplyShield Canlı Tedarik Zinciri Güvenliği ve Sipariş API Arayüzü."
  value       = "http://app.${azurerm_public_ip.pip_app.ip_address}.nip.io"
}
