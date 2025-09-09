variable "proxmox_node" {
  description = "Proxmox node name"
  type        = string
  default     = "pve"
}

variable "pve03_token_secret" {
  description = "PVE token secret value"
  type        = string
  sensitive   = true
}

variable "pve03_token_id" {
  description = "Proxmox token name"
  type        = string
}

variable "cloud_user" {
  description = "Cloud-init user to configure"
  type        = string
  default     = "ubuntu"
}

variable "pub_ssh_key_path" {
  type    = string
  default = "~/.ssh/id_ed25519.pub"
}

variable "templatename" {
  type = string
}
