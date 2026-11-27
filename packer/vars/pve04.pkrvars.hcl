# Per-node layout for pve04 (OVH datacenter — NOT part of the pve01-03 cluster).
# Layout only — pve04's token + build password come from pve04.pkrvars.hcl
# (gitignored, passed with the first -var-file). Secrets never live here.
#
# Fill in the storage / ISO values for THIS node.
#   pvesm storage list   -> pool names

proxmox_url  = "https://pve04.bladewdr.xyz:8006/api2/json"
proxmox_node = "pve04"

network_bridge          = "vmbr0"
disk_storage            = "data"
cloud_init_storage_pool = "data"
efi_storage_pool        = "data"
iso_file                = "local:iso/debian-13.8.0-amd64-netinst.iso"

# Only uncomment if this node's ISO differs from the default in debian13.pkr.hcl.
# iso_checksum = "sha256:<this node's iso checksum>"
