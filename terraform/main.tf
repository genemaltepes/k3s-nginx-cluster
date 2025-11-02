provider "proxmox" {
  pm_api_url          = var.proxmox_api_url
  pm_api_token_id     = var.proxmox_api_token_id
  pm_api_token_secret = var.proxmox_api_token_secret
  pm_tls_insecure     = true
}

# Read SSH public key
locals {
  ssh_public_key = file(pathexpand(var.ssh_public_key_file))
  
  # Cloud-init user config
  cloudinit_user = <<-EOT
    #cloud-config
    users:
      - name: ${var.ansible_user}
        groups: sudo
        shell: /bin/bash
        sudo: ALL=(ALL) NOPASSWD:ALL
        ssh_authorized_keys:
          - ${local.ssh_public_key}
    package_update: true
    package_upgrade: true
    packages:
      - qemu-guest-agent
      - curl
      - wget
    runcmd:
      - systemctl start qemu-guest-agent
      - systemctl enable qemu-guest-agent
  EOT
}

# Create VMs
resource "proxmox_vm_qemu" "vms" {
  for_each = var.vms

  name        = each.key
  target_node = var.proxmox_node
  vmid        = each.value.vmid
  clone       = var.template_name
  full_clone  = true
  agent       = 1
  
  cores       = each.value.cores
  sockets     = 1
  cpu_type    = "host"
  memory      = each.value.memory

  # Most cloud-init images require a serial device for their display
  serial {
    id = 0
  }
  
  # Boot settings
  boot    = "order=scsi0"
  scsihw  = "virtio-scsi-pci"
  
  # Disk configuration
  disks {
    scsi {
      scsi0 {
        disk {
          size    = each.value.disk_size
          storage = "local-lvm"
        }
      }
    }
    ide {
      # Some images require a cloud-init disk on the IDE controller, others on the SCSI or SATA controller
      ide1 {
        cloudinit {
          storage  = "local-lvm"
        }
      }
    }
  }
  
  # Network configuration
  network {
    id = 0
    model  = "virtio"
    bridge = "vmbr0"
  }
  
  # Cloud-init settings
  ipconfig0  = "ip=${each.value.ip}/24,gw=${var.gateway}"
  nameserver = var.nameserver
  
  # Inject cloud-init config
  cicustom = "user=local:snippets/${each.key}-user.yml"
  
  # OS type
  os_type = "cloud-init"
  
  # Start VM after creation
  automatic_reboot = false
  
  # Lifecycle
  lifecycle {
    ignore_changes = [
      network,
      disk,
    ]
  }
  
  # Wait for VM to be ready
  connection {
    type        = "ssh"
    user        = var.ansible_user
    private_key = file(pathexpand("~/.ssh/id_ed25519"))
    host        = each.value.ip
    timeout     = "5m"
  }

  # CRITICAL: Ensure cloud-init files are uploaded BEFORE VM creation
  depends_on = [null_resource.cloudinit_upload]
}

# Upload cloud-init configs to Proxmox
resource "null_resource" "cloudinit_upload" {
  for_each = var.vms
  
  triggers = {
    user_config = md5(local.cloudinit_user)
  }
  
  provisioner "local-exec" {
    command = <<-EOT
      ssh -o StrictHostKeyChecking=no root@192.168.1.192 "mkdir -p /var/lib/vz/snippets && cat > /var/lib/vz/snippets/${each.key}-user.yml" <<'EOF'
${local.cloudinit_user}
EOF
    EOT
  }
  
  # No dependencies - this runs first
}

# Wait for VMs to be accessible via SSH
resource "null_resource" "wait_for_vms" {
  for_each = var.vms
  
  triggers = {
    vm_id = proxmox_vm_qemu.vms[each.key].id
  }
  
  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command = <<-EOT
      echo "Waiting for ${each.key} (${each.value.ip}) to be ready..."
      for i in {1..30}; do
        if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 ${var.ansible_user}@${each.value.ip} "echo 'VM is ready'" 2>/dev/null; then
          echo "${each.key} is ready!"
          exit 0
        fi
        echo "Attempt $i: ${each.key} not ready yet, waiting..."
        sleep 10
      done
      echo "Timeout waiting for ${each.key}"
      exit 1
    EOT
  }
  
  depends_on = [
    proxmox_vm_qemu.vms,
    null_resource.cloudinit_upload
  ]
}

# Update known_hosts - sequential execution to avoid race conditions
resource "null_resource" "update_known_hosts" {
  triggers = {
    # Trigger on any VM change
    vms_hash = md5(jsonencode([for k, v in var.vms : "${k}-${v.ip}"]))
    timestamp = timestamp()
  }
  
  # Remove old entries first (all IPs)
  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command = <<-EOT
      echo "Cleaning known_hosts for all VM IPs..."
      %{for k, v in var.vms~}
      ssh-keygen -R ${v.ip} 2>/dev/null || true
      %{endfor~}
    EOT
  }
  
  # Wait a moment to avoid race conditions
  provisioner "local-exec" {
    command = "sleep 2"
  }
  
  # Add new entries sequentially
  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command = <<-EOT
      echo "Updating known_hosts with new keys..."
      %{for k, v in var.vms~}
      echo "Adding ${k} (${v.ip}) to known_hosts..."
      for i in {1..10}; do
        if ssh-keyscan -H ${v.ip} >> ~/.ssh/known_hosts 2>/dev/null; then
          echo "Successfully added ${k}"
          break
        fi
        echo "Retry $i for ${k}..."
        sleep 2
      done
      %{endfor~}
      echo "known_hosts update complete!"
    EOT
  }
  
  depends_on = [null_resource.wait_for_vms]
}

# Generate Ansible inventory
resource "local_file" "ansible_inventory" {
  filename = "${path.module}/../ansible/inventory.yml"
  
  content = templatefile("${path.module}/inventory.tpl", {
    vms          = var.vms
    ansible_user = var.ansible_user
    vip_address  = "192.168.1.200"
  })
  
  depends_on = [null_resource.update_known_hosts]
}
