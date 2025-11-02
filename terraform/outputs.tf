output "vm_ips" {
  description = "IP addresses of all VMs"
  value = {
    for k, v in proxmox_vm_qemu.vms : k => v.default_ipv4_address
  }
}

output "vm_ids" {
  description = "VM IDs"
  value = {
    for k, v in proxmox_vm_qemu.vms : k => v.vmid
  }
}

output "ansible_inventory_path" {
  description = "Path to generated Ansible inventory"
  value       = local_file.ansible_inventory.filename
}

output "deployment_summary" {
  description = "Deployment summary"
  value = <<-EOT
    ╔═══════════════════════════════════════════════════════╗
    ║           K3S HA Cluster Infrastructure               ║
    ╠═══════════════════════════════════════════════════════╣
    ║ Load Balancer VIP: 192.168.1.200                      ║
    ║                                                       ║
    ║ Masters:                                              ║
    ║   - master1: 192.168.1.211                           ║
    ║   - master2: 192.168.1.212                           ║
    ║   - master3: 192.168.1.213                           ║
    ║                                                       ║
    ║ Workers:                                              ║
    ║   - worker1: 192.168.1.221                           ║
    ║   - worker2: 192.168.1.222                           ║
    ║   - worker3: 192.168.1.223                           ║
    ║                                                       ║
    ║ Infrastructure:                                       ║
    ║   - lb1: 192.168.1.210 (Nginx + Keepalived)         ║
    ║                                                       ║
    ║ Datastore: Embedded etcd (HA)                        ║
    ║ Storage: K3S Local Path Provisioner                  ║
    ║                                                       ║
    ║ Next Steps:                                           ║
    ║   cd ../ansible                                       ║
    ║   ansible-playbook -i inventory.yml site.yml         ║
    ╚═══════════════════════════════════════════════════════╝
  EOT
}
