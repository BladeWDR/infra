# Per-node layout for pve01 (pve01-03 cluster).
# Layout only — the cluster token + build password come from cluster.pkrvars.hcl
# (gitignored, passed with the first -var-file). Secrets never live here.
#
# Fill in the storage / ISO values for THIS node. The disk storage pool must be
# present on every cluster node so the template can be replicated to pve02/pve03.
#   pvesm storage list   -> pool names
#   pvecm nodes          -> node names (this file is the build host for pve01)

proxmox_url  = "https://pve01.bladewdr.xyz:8006/api2/json"
proxmox_node = "pve01"

network_bridge          = "vmbr0"
disk_storage            = "local-lvm"
cloud_init_storage_pool = "local-lvm"
efi_storage_pool        = "local-lvm"
iso_file                = "local:iso/debian-13.8.0-amd64-netinst.iso"

# Only uncomment if this node's ISO differs from the default in debian13.pkr.hcl.
# iso_checksum = "sha256:<this node's iso checksum>"
