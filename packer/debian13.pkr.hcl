# ---------------------------------------------------------------------------
# Packer template: Debian 13 (Trixie) cloud-init enabled VM for Proxmox.
#
# Pipeline:
#   1. Boot the Debian netinst ISO and run an UNATTENDED install from a
#      preseed served by Packer's built-in HTTP server.
#   2. Log in over SSH and run Ansible to install the developer toolset,
#      your SSH key, and the cloud-init stack.
#   3. Lock the temporary build password and reset cloud-init state.
#   4. Packer stops the VM and converts it into a reusable template.
#
# Secrets live in .pkrvars.hcl (copy from .pkrvars.hcl.example) or as env vars:
#   PROXMOX_URL / PROXMOX_USERNAME / PROXMOX_TOKEN / PACKER_BUILD_PASSWORD
#
# See README.md for the full walkthrough (which ISO to download, how to create
# the least-privilege API token, and how to run the build).
# ---------------------------------------------------------------------------

packer {
  required_plugins {
    proxmox = {
      version = ">= 1.0.0"
      source  = "github.com/hashicorp/proxmox"
    }
  }
}

# ---- Proxmox connection (secrets via .pkrvars.hcl / env) ----
variable "proxmox_url" {
  type        = string
  description = "Proxmox API base URL, e.g. https://pve.example.com:8006/api2/json"
  default     = "https://pve.example.com:8006/api2/json"
}

variable "proxmox_username" {
  type        = string
  description = "API user with realm and token id, e.g. packer@pve!token"
  default     = ""
  sensitive   = true
}

variable "proxmox_token" {
  type        = string
  description = "API token secret (shown once when created)."
  default     = ""
  sensitive   = true
}

# ---- Build host / placement ----
# Per-node layout (proxmox_url, proxmox_node, bridge, storage, iso) is supplied
# per target via vars/pveXX.pkrvars.hcl (passed with -var-file). No sensible
# default exists (every node differs), so the default is left empty and is always
# overridden by a var file.
variable "proxmox_node" {
  type        = string
  description = "Node to build on. Supplied per target via vars/pveXX.pkrvars.hcl."
  default     = ""
}

# Optional: uncomment and set if a node uses a resource pool.
# variable "resource_pool" {
#   type    = string
#   default = ""
# }

# ---- Network ----
variable "network_bridge" {
  type        = string
  description = "Proxmox bridge for the build NIC. Must have DHCP and reach Packer's HTTP server."
  default     = "vmbr0"
}

# ---- Storage ----
variable "disk_storage" {
  type        = string
  description = "Storage pool for the VM system disk (default PVE LVM)."
  default     = "local-lvm"
}

variable "cloud_init_storage_pool" {
  type        = string
  description = "Storage for the cloud-init CDROM (must support the cloud-init feature)."
  default     = "local"
}

variable "efi_storage_pool" {
  type        = string
  description = "Storage for the OVMF EFI disk (must support the efidisk feature, e.g. local)."
  default     = "local"
}

# ---- ISO (must already be uploaded to the host's ISO storage) ----
variable "iso_file" {
  type        = string
  description = "Datastore path to the Debian 13 netinst ISO."
  default     = "local:iso/debian-13.8.0-amd64-netinst.iso"
}

variable "iso_checksum" {
  type        = string
  description = "Checksum of the netinst ISO. Set to 'none' to skip verification."
  default     = "sha256:3770c7a54890f7574a68a8b402e553806a81d6bccfb379554caad3a9a857931e"
}

# ---- VM sizing / identity ----
variable "vm_memory" {
  type    = string
  default = "2048"
}

variable "vm_cores" {
  type    = string
  default = "2"
}

variable "vm_disk" {
  type    = string
  default = "20G"
}

variable "vm_id" {
  type        = string
  description = "Fixed VM ID for the build. Packer refuses to reuse an existing one without -force."
  default     = "9001"
}

variable "cpu_type" {
  type    = string
  default = "x86-64-v2-AES"
}

variable "template_name" {
  type    = string
  default = "debian13-cloudinit"
}

variable "template_description" {
  type    = string
  default = "Debian 13 (Trixie) cloud-init template built by Packer"
}

variable "vm_tags" {
  type    = string
  # Proxmox tags are a semicolon-separated list; each tag may only use
  # [a-z0-9_] (no hyphens/spaces).
  description = "Semicolon-separated Proxmox tags (each [a-z0-9_])."
  default = "packer;debian13;cloudinit"
}

# ---- Build-time credentials ----
variable "build_user" {
  type        = string
  description = "User created during install so Packer/Ansible can log in. Locked after the build."
  default     = "ansible"
}

variable "build_password" {
  type        = string
  description = "Temporary password for the build user. Injected into the preseed and locked after. REQUIRED — set it in .pkrvars.hcl."
  default     = ""
  sensitive   = true
}

variable "timezone" {
  type    = string
  default = "America/New_York"
}

# ---- SSH ----
variable "ssh_timeout" {
  type    = string
  default = "15m"
}

# ---------------------------------------------------------------------------
# Boot command: reach the Debian installer GRUB prompt and start an unattended
# install from the preseed served by Packer's built-in HTTP server.
# ---------------------------------------------------------------------------
source "proxmox-iso" "debian13" {
  proxmox_url            = var.proxmox_url
  username               = var.proxmox_username
  token                  = var.proxmox_token
  node                   = var.proxmox_node
  insecure_skip_tls_verify = true

  # Pin the build VM to a fixed ID (Packer refuses to reuse an existing one).
  vm_id = var.vm_id

  # Uncomment if pve04 uses a resource pool:
  # pool = var.resource_pool

  # --- Install ---
  # OVMF (UEFI) boots into GRUB2. Press 'e' to edit the default menu entry,
  # move to the end of the 'linux' line, append the unattended preseed args,
  # and press F10 to boot.
  boot_wait = "5s"
  boot_command = [
    "e<wait>",
    "<down><down><down><end>",
    " auto=true priority=critical",
    " preseed/url=http://{{ .HTTPIP }}:{{ .HTTPPort }}/preseed.cfg",
    " debian-installer/locale=en_US.UTF-8",
    " keyboard-configuration/xkb-keymap=us",
    " netcfg/choose_interface=auto",
    " hostname=packer-build domain=localdomain",
    "<wait><f10>"
  ]

  # Serve the password-templated preseed to the installing VM on a fixed port.
  http_port_min = 8735
  http_port_max = 8735
  http_content = {
    "/preseed.cfg" = templatefile("${path.root}/preseed.cfg", {
      build_password = var.build_password
      build_user     = var.build_user
      timezone       = var.timezone
    })
  }

  boot_iso {
    type         = "scsi"
    iso_file     = var.iso_file
    iso_checksum = var.iso_checksum
    unmount      = true
  }

  disks {
    type         = "scsi"
    disk_size    = var.vm_disk
    storage_pool = var.disk_storage
    discard      = true
    # zfspool storage accepts raw (or zvol); qcow2 is not valid there.
    format       = "raw"
  }

  network_adapters {
    model    = "virtio"
    bridge   = var.network_bridge
    firewall = false
  }

  # --- Hardware / boot ---
  memory          = var.vm_memory
  cores           = var.vm_cores
  cpu_type        = var.cpu_type
  os              = "l26"
  bios            = "ovmf"
  machine         = "q35"
  scsi_controller = "virtio-scsi-single"
  qemu_agent      = true
  onboot          = false

  efi_config {
    efi_storage_pool  = var.efi_storage_pool
    efi_type          = "4m"
    pre_enrolled_keys = true
  }

  # --- Cloud-init: add the empty cloud-init CDROM to the template ---
  cloud_init                = true
  cloud_init_storage_pool   = var.cloud_init_storage_pool
  cloud_init_disk_type      = "scsi"

  # --- SSH for the communicator / ansible provisioner ---
  ssh_username = var.build_user
  ssh_password = var.build_password
  ssh_timeout  = var.ssh_timeout

  # --- Output template ---
  template_name        = var.template_name
  template_description = var.template_description
  tags                 = var.vm_tags
}

# ---------------------------------------------------------------------------
# Provision: install the developer toolset, your SSH key, and cloud-init.
# Runs over SSH as build_user/build_password; become is passwordless (set up by
# the preseed). The build password is locked at the end of the playbook.
# ---------------------------------------------------------------------------
build {
  sources = ["source.proxmox-iso.debian13"]

  # In Packer 1.x the provisioner block lives INSIDE the build block.
  provisioner "ansible" {
    playbook_file = "playbooks/provision.yml"

    # Packer 1.x's built-in ansible provisioner is minimal: the SSH connection
    # (user + password) is inherited from the builder's ssh_username/ssh_password,
    # and become/become_method are set in the playbook itself.
    # Override if ansible-playbook is not on PATH (e.g. the repo's venv):
    # command = "/home/scott/git/infra/.venv/bin/ansible-playbook"
  }
}
