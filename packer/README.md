# Packer → Proxmox: Debian 13 (Trixie) cloud-init template

This directory builds a **cloud-init-enabled Debian 13 (Trixie) VM template** on
Proxmox, using Packer + an unattended netinst install + an Ansible provisioner
that bakes in your developer toolset and SSH key.

The resulting template can be cloned in seconds to spin up VMs that are
configured at boot by Proxmox's **cloud-init ISO** feature.

```
packer/
├── debian13.pkr.hcl        # the Packer build (builder + ansible provisioner)
├── preseed.cfg             # Debian installer preseed (rendered with your build pw)
├── playbooks/
│   └── provision.yml       # installs packages, your SSH key, and cloud-init
├── debian13.auto.pkrvars.hcl.example  # COPY to debian13.auto.pkrvars.hcl and fill secrets
├── .gitignore              # keeps *.pkrvars.hcl and build cache out of git
└── README.md
```

---

## 0. Which Debian image to download

Use the **Debian 13 "Trixie" network installer (netinst), amd64**. This is the
small (~760 MB) installer that downloads the rest over the network — ideal for a
build VM.

- **File:** `debian-13.8.0-amd64-netinst.iso`
- **Download:** <https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-13.8.0-amd64-netinst.iso>
- **SHA256:** `3770c7a54890f7574a68a8b402e553806a81d6bccfb379554caad3a9a857931e`
  (already wired into `debian13.pkr.hcl` as `iso_checksum` for verification)

> The `current` filename moves with each point release. If a newer Trixie point
> release appears, re-check the filename + SHA256 at
> <https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/> and update the
> `iso_file` / `iso_checksum` variables (or the values in `debian13.auto.pkrvars.hcl`).
> Do **not** use the DVD, live, or `debian-edu` image — netinst is what this
> template expects.

### Upload it to pve04

The template references the ISO at `local:iso/debian-13.8.0-amd64-netinst.iso`
(the PVE `local` storage's ISO folder). Upload it one of two ways:

- **Web UI:** Datacenter → Storage → `local` → *ISOs* → **Upload** → choose the
  ISO. (Works from any node; the ISO is cluster-visible on `local`.)
- **CLI on pve04:** the `local` storage's ISO directory is
  `/var/lib/vz/template/iso/`:
  ```bash
  scp debian-13.8.0-amd64-netinst.iso root@pve04:/var/lib/vz/template/iso/
  ```

If pve04 uses a different ISO storage, update `iso_file` in `debian13.auto.pkrvars.hcl`.

---

## 1. Create a least-privilege Proxmox API token

Packer authenticates with **one API user + one API token** (Proxmox uses API
tokens, not API "keys"). The token is the secret you paste into `debian13.auto.pkrvars.hcl`.

Do this on **pve04** (as root, or a user with admin rights).

### 1a. Recommended: a dedicated `PackerUser` role

```bash
# 1. Create a least-privilege role
pveum role add PackerUser --privs \
  "Datastore.AllocateSpace Datastore.AllocateTemplate Datastore.Audit \
   SDN.Use Sys.Audit Sys.Modify VM.Allocate VM.Audit VM.Clone \
   VM.Config.CDROM VM.Config.Cloudinit VM.Config.CPU VM.Config.Disk \
   VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options \
   VM.Console VM.Monitor VM.PowerMgmt"

# 2. Create a group for the build user
pveum group add packer-users

# 3. Grant the role on the datacenter (recurse unchecked)
pveum acl modify / -group packer-users -role PackerUser

# 4. Create the build user and add it to the group
pveum user add packer@pve -groups packer-users -comment "Packer build user"

# 5. Generate an API token (shown ONCE)
pveum user token add packer@pve token --priv-sep 0
#   -> prints a secret like:  packer@pve!token=9F3aBc...  (shown ONCE)
```

The token **id** is `packer@pve!token`; the **secret** is the
`packer@pve!token=...` string printed (copy the part after `=`). Paste the
**id** as `proxmox_username` and the **secret** as `proxmox_token` in
`debian13.auto.pkrvars.hcl`.

> **Web UI equivalent:** Datacenter → *Permissions* → *Roles* → add role
> `PackerUser` with the privileges above; then *Groups* → add group
> `packer-users` → *Assign* → role `PackerUser`, path `/`, **Recurse
> unchecked**; then *Users* → add `packer` (realm `pve`) in group
> `packer-users` → select the user → *Add Token* → name `token` and copy the
> secret shown.

---

## 2. Fill in `debian13.auto.pkrvars.hcl`

```bash
cp debian13.auto.pkrvars.hcl.example debian13.auto.pkrvars.hcl
$EDITOR debian13.auto.pkrvars.hcl
```

This file holds the token + build password, so it is **gitignored**
(`*.pkrvars.hcl`). The `.auto.pkrvars.hcl` name means Packer **auto-loads it on
directory invocation** (`packer validate .` / `packer build .`) — so no
`-var-file` is needed, and the secret still never lands in git. (Pointing Packer
at the template *file* does not auto-load; use the directory form in step 4.)

Set at minimum:

| Variable | Value |
|---|---|
| `proxmox_url` | `https://pve04:8006/api2/json` (or `https://pve04.example.com:8006/api2/json`) |
| `proxmox_username` | `packer@pve!token` |
| `proxmox_token` | the secret from step 1 (`=…` part) |
| `build_password` | a strong temporary password (locked after the build) |

Also **verify the storage/network defaults against pve04** (uncomment and adjust
in `debian13.auto.pkrvars.hcl` if different): `network_bridge` (default `vmbr0`),
`disk_storage` (default `local-lvm`), `cloud_init_storage_pool` / `efi_storage_pool`
(default `local`), and `iso_file`.

> You can also export `PROXMOX_URL`, `PROXMOX_USERNAME`, `PROXMOX_TOKEN`,
> `PACKER_BUILD_PASSWORD` as environment variables instead of a var file.

---

## 3. Install the Packer plugin (one time)

```bash
packer init
# or: packer plugins install github.com/hashicorp/proxmox
```

(`packer` v1.16.2 is already installed on this host; it just needs the proxmox
plugin. `ansible-playbook` must also be on PATH — e.g. activate the repo's
`.venv`, or set `command` in the ansible provisioner block of `debian13.pkr.hcl`
to its path.)

---

## 4. Run the build (only after the above)

```bash
cd packer
packer validate .      # auto-loads debian13.auto.pkrvars.hcl; syntax + plugin check, no PVE contact
packer build    .      # full build → template 'debian13-cloudinit' (also auto-loads the var file)
```

> The **directory form** (`packer validate .`) auto-loads
> `debian13.auto.pkrvars.hcl` — no `-var-file` needed. Pointing Packer at the
> template *file* instead requires `-var-file=debian13.auto.pkrvars.hcl`.
> (Or set the `PROXMOX_*` / `PACKER_BUILD_PASSWORD` env vars instead.)

The build will:

1. Create a throwaway VM on **pve04**, boot the netinst, and run the unattended
   install from the preseed (served by Packer's built-in HTTP server).
2. Log in over SSH and run `playbooks/provision.yml` to install:
   `zsh`, `git`, `tmux`, `htop`, `ncdu`, `curl`, `wget`,
   plus the cloud-init stack (`cloud-init`, `cloud-guest-utils`,
   `cloud-initramfs-growroot`, `qemu-guest-agent`), the
   **netplan** + `systemd-resolved` stack so clones configure IP/DNS via
   Proxmox cloud-init, and the **Tailscale** client (installed + enabled,
   but *not* authenticated).
3. Add **your** SSH key (baked in from `debian13.auto.pkrvars.hcl`) to the `ansible` user.
4. Lock the temporary build password, reset cloud-init state, and clear
   Tailscale state (so cloned VMs start unauthenticated).
5. Stop the VM and convert it to the template **`debian13-cloudinit`**.

---

## 5. Use the template (cloud-init at boot)

1. Clone `debian13-cloudinit` to a new VM (or *Create VM from template*).
2. In the VM's **Options → Cloud-Init** tab, enable it.
3. Set the network so cloud-init can reach the VM:
   `ipconfig0=ip=dhcp` (dynamic) or `ip=dhcp4,name=eth0,...` — Proxmox will
   inject the cloud-init ISO on first boot.
4. Create the VM and start it. On first boot, cloud-init configures networking,
   and (if you pass `ssh_authorized_keys`/`users` in the cloud-init ISO or
   user-data) sets up access. Your key is already baked into the `ansible` user.

---

## Notes / things to confirm before building

- **This template targets Packer 1.x** Packer 2.x is
  not on the stable download page, so don't expect to find it. Two 1.x quirks
  baked into `debian13.pkr.hcl`:
  - The `provisioner` block lives **inside** `build {}` (top-level provisioner
    blocks are a 2.x feature).
  - It uses Packer 1.x's **built-in** `ansible` provisioner, which is minimal:
    only `playbook_file` (+ an optional `command` to point at
    `ansible-playbook`). The SSH connection is inherited from the builder's
    `ssh_username`/`ssh_password`, and `become`/`become_method` are set in
    `playbooks/provision.yml`. If you ever move to Packer 2.x, the richer
    `user` / `ansible_env` / `groups` options come from the separate
    `hashicorp/ansible` **plugin**, not the built-in.
- **HTTP reachability:** Packer serves the preseed from its own host. The
  building VM must reach that host on `network_bridge` — so run Packer from a
  host on pve04's management network (or from pve04 itself). If the bridge has
  no DHCP, give the VM a static IP and set it in `preseed.cfg`.
- **Tailscale in the image ≠ build reachability.** Baking the client into the
  template helps VMs *cloned later* join the mesh — it does **not** fix the
  build's own preseed fetch or Packer's first SSH, both of which happen *before*
  Tailscale exists on the VM.
- **Storage names** (`local`, `local-lvm`, `vmbr0`) assume a stock Proxmox.
  Confirm them on your host and adjust `debian13.auto.pkrvars.hcl` if needed.
- **Re-running:** the build is reproducible. Each run uses a fresh VM; delete the
  old `debian13-cloudinit` template first if you rebuild it.
- **Idempotency:** package/key/service tasks are idempotent; the
  `update-initramfs` and `cloud-init clean` steps are one-shot build steps and
  are intentionally marked `changed_when: true`.
