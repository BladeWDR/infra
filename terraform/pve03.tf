resource "proxmox_vm_qemu" "onramp-lab" {
  provider    = proxmox.pve03
  target_node = "SB-PROXMOX"
  name        = "onramp-lab"
  vmid        = "111"
  os_type     = "cloud-init"
  bios        = "ovmf"
  agent       = 1
  onboot      = true
  clone       = var.templatename
  full_clone  = true

  cpu {
    cores   = "4"
    sockets = 1
  }
  memory = "4096"

  network {
    id       = 0
    model    = "virtio"
    bridge   = "vmbr0"
    tag      = "10"
    firewall = false
  }

  efidisk {
    efitype           = "4m"
    storage           = "fast"
    pre_enrolled_keys = false
  }

  scsihw   = "virtio-scsi-single"
  boot     = "order=virtio0;net0"
  bootdisk = "virtio0"


  disks {
    virtio {
      virtio0 {
        disk {
          storage = "fast"
          size    = "32G"
        }
      }
    }
    scsi {
      scsi0 {
        cloudinit {
          storage = "fast"
        }
      }
    }

  }

  # Cloud-init options
  # Keep in mind to use the CIDR notation for the ip.
  ipconfig0 = "ip=172.16.10.2/24,gw=172.16.10.1"
  ciuser    = var.cloud_user
  sshkeys   = file(var.pub_ssh_key_path)
}

resource "proxmox_vm_qemu" "docker-test" {
  provider    = proxmox.pve03
  target_node = "SB-PROXMOX"
  name        = "docker-test"
  vmid        = "300"
  os_type     = "cloud-init"
  bios        = "ovmf"
  agent       = 1
  clone       = var.templatename
  full_clone  = true

  cpu {
    cores   = "2"
    sockets = 1
  }
  memory = "4096"

  network {
    id       = 0
    model    = "virtio"
    bridge   = "vmbr0"
    tag      = "10"
    firewall = false
  }

  scsihw   = "virtio-scsi-single"
  boot     = "order=virtio0;net0"
  bootdisk = "virtio0"

  efidisk {
    efitype           = "4m"
    storage           = "fast"
    pre_enrolled_keys = false
  }

  disks {
    virtio {
      virtio0 {
        disk {
          storage = "fast"
          size    = "32G"
        }
      }
    }
    scsi {
      scsi0 {
        cloudinit {
          storage = "fast"
        }
      }
    }

  }

  # Cloud-init options
  # Keep in mind to use the CIDR notation for the ip.
  ipconfig0 = "ip=172.16.10.3/24,gw=172.16.10.1"
  ciuser    = var.cloud_user
  sshkeys   = file(var.pub_ssh_key_path)
}
