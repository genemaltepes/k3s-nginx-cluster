variable "proxmox_api_url" {
  description = "Proxmox API URL"
  type        = string
}

variable "proxmox_api_token_id" {
  description = "Proxmox API Token ID"
  type        = string
}

variable "proxmox_api_token_secret" {
  description = "Proxmox API Token Secret"
  type        = string
  sensitive   = true
}

variable "proxmox_node" {
  description = "Proxmox node name"
  type        = string
  default     = "pve"
}

variable "template_name" {
  description = "Cloud-init template name"
  type        = string
  default     = "debian12-cloudinit"
}

variable "ssh_public_key_file" {
  description = "Path to SSH public key"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "ansible_user" {
  description = "Ansible user to create on VMs"
  type        = string
  default     = "ansible"
}

variable "gateway" {
  description = "Network gateway"
  type        = string
  default     = "192.168.1.1"
}

variable "nameserver" {
  description = "DNS nameserver"
  type        = string
  default     = "8.8.8.8"
}

variable "vms" {
  description = "VM configurations"
  type = map(object({
    vmid        = number
    ip          = string
    cores       = number
    memory      = number
    disk_size   = string
  }))
  
  default = {
    "lb1" = {
      vmid      = 210
      ip        = "192.168.1.210"
      cores     = 1
      memory    = 4096
      disk_size = "20G"
    }
    "master1" = {
      vmid      = 211
      ip        = "192.168.1.211"
      cores     = 1
      memory    = 8192
      disk_size = "50G"
    }
    "master2" = {
      vmid      = 212
      ip        = "192.168.1.212"
      cores     = 1
      memory    = 8192
      disk_size = "50G"
    }
    "master3" = {
      vmid      = 213
      ip        = "192.168.1.213"
      cores     = 1
      memory    = 8192
      disk_size = "50G"
    }
    "worker1" = {
      vmid      = 221
      ip        = "192.168.1.221"
      cores     = 2
      memory    = 8192
      disk_size = "100G"
    }
    "worker2" = {
      vmid      = 222
      ip        = "192.168.1.222"
      cores     = 2
      memory    = 8192
      disk_size = "100G"
    }
    "worker3" = {
      vmid      = 223
      ip        = "192.168.1.223"
      cores     = 2
      memory    = 8192
      disk_size = "100G"
    }    
  }
}
