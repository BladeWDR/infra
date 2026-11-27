# Packer → Proxmox: Debian 13 (Trixie) cloud-init template

This directory builds a **cloud-init-enabled Debian 13 (Trixie) VM template** on
Proxmox, using Packer + an unattended netinst install + an Ansible provisioner
that bakes in your developer toolset and SSH key.

The resulting template can be cloned in seconds to spin up VMs that are
configured at boot by Proxmox's **cloud-init ISO** feature.

```
packer/
├── debian13.pkr.hcl              # the Packer build (builder + ansible provisioner)
├── preseed.cfg                  # Debian installer preseed (rendered with your build pw)
├── playbooks/
│   └── provision.yml            # installs packages, your SSH key, and cloud-init
├── vars/                        # COMMITTED, non-secret per-node LAYOUT only
│   ├── pve01.pkrvars.hcl        #   pve01-03 cluster node (fill storage/iso)
│   └── pve04.pkrvars.hcl        #   pve04 (OVH, not clustered — fill storage/iso)
├── debian13.pkrvars.hcl.example # template to COPY to a gitignored secret file
├── cluster.pkrvars.hcl    (gitignored)  # pve01-03 cluster token + build password
├── pve04.pkrvars.hcl      (gitignored)  # pve04 token + build password
├── .gitignore                 # keeps *.pkrvars.hcl and build cache out of git
└── README.md
```

### How a build resolves its values

Each `packer build` gets its values from two `-var-file`s, both passed
explicitly on the command line (later wins if a key repeats):

1. **`<scope>.pkrvars.hcl`** (root, gitignored) — holds the **secrets**
   (API token + build password). One per credential scope:
   - `cluster.pkrvars.hcl` → the pve01-03 **cluster** token + build password
   - `pve04.pkrvars.hcl`   → pve04's token + build password
2. **`vars/pveXX.pkrvars.hcl`** (committed) — holds the **per-node layout**
   (`proxmox_url`, `proxmox_node`, bridge, storage pools, ISO).

So a build is one command with two `-var-file`s: the first supplies the
secrets, the second supplies that node's layout. No environment variables
required, and — because the secret file is passed explicitly rather than
auto-loaded — a build can never accidentally pull another target's token.

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
> `iso_file` / `iso_checksum` variables (or the values in `vars/pveXX.pkrvars.hcl`).
> Do **not** use the DVD, live, or `debian-edu` image — netinst is what this
> template expects.

### Upload it to your build node(s)

The template references the ISO at `local:iso/debian-13.8.0-amd64-netinst.iso`
(the PVE `local` storage's ISO folder — the storage name is per-node, set in
`vars/pveXX.pkrvars.hcl`). Upload it to **every node you will build on** one of
two ways:

- **Web UI:** Datacenter → Storage → `local` → *ISOs* → **Upload** → choose the
  ISO. On the pve01-03 cluster the ISO is shared via `local`, so one upload
  covers the cluster.
- **CLI on the build node:** the `local` storage's ISO directory is
  `/var/lib/vz/template/iso/`:
  ```bash
  scp debian-13.8.0-amd64-netinst.iso root@pveXX:/var/lib/vz/template/iso/
  ```

If a node uses a different ISO storage, update `iso_file` in that node's
`vars/pveXX.pkrvars.hcl`.

---

## 1. Create the least-privilege Proxmox API tokens

Packer authenticates with **one API user + one API token** (Proxmox uses API
tokens, not API "keys"). Each token is the secret you paste into a gitignored
`*.pkrvars.hcl` secret file (step 2).

There are **two credential scopes**, because your fleet is not one cluster:

- **The pve01-03 cluster** — **one** cluster token authenticates to *any* node in
  the cluster (create it in the cluster's shared user directory / on one node with
  cluster-wide ACL). Build on **one** cluster node (pve01), then replicate the
  template to the others — so only `vars/pve01.pkrvars.hcl` exists for the
  cluster; pve02/pve03 are never built on, just receive the replicated template.
- **pve04 (OVH, not in the cluster)** — its **own** token, created on pve04.

Do each scope on its target node (as root, or a user with admin rights).

### 1a. Recommended: a dedicated `PackerUser` role

```bash
# 1. Create a least-privilege role (Proxmox VE 9+: VM.GuestAgent.Audit replaces removed VM.Monitor)
pveum role add PackerUser --privs \
  "Datastore.AllocateSpace Datastore.AllocateTemplate Datastore.Audit \
   SDN.Use Sys.Audit Sys.Modify VM.Allocate VM.Audit VM.Clone \
   VM.Config.CDROM VM.Config.Cloudinit VM.Config.CPU VM.Config.Disk \
   VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options \
   VM.Console VM.GuestAgent.Audit VM.PowerMgmt"

# 2. Create a group for the build user
pveum group add packer-users

# 3. Grant the role on the datacenter (recurse unchecked)
pveum acl modify / -group packer-users -role PackerUser

# 4. Create the build user and add it to the group
pveum user add packer@pve -groups packer-users -comment "Packer build user"

# 5. Generate an API token (shown ONCE)
pveum user token add packer@pve token --privsep 0
#   -> prints a secret like:  packer@pve!token=9F3aBc...  (shown ONCE)
```

The token **id** is `packer@pve!token`; the **secret** is the
`packer@pve!token=...` string printed (copy the part after `=`). Paste the
**id** as `proxmox_username` and the **secret** as `proxmox_token` into the
gitignored secret file for that scope (step 2).

> **Web UI equivalent:** Datacenter → *Permissions* → *Roles* → add role
> `PackerUser` with the privileges above; then *Groups* → add group
> `packer-users` → *Assign* → role `PackerUser`, path `/`, **Recurse
> unchecked**; then *Users* → add `packer` (realm `pve`) in group
> `packer-users` → select the user → *Add Token* → name `token` and copy the
> secret shown.
>
> For the **cluster** token, create the user in the cluster's shared directory
> (or on one node) and grant `PackerUser` at `/` so one token works on pve01-03.
> For **pve04**, repeat the whole block on pve04 itself.

---

## 2. Fill in the two gitignored secret files

Copy the template and create **one gitignored secret file per credential scope**
(the `*.pkrvars.hcl` name at the root is **gitignored** — `*.pkrvars.hcl` in
`.gitignore` — so the secret never lands in git. It is **not** auto-loaded; it is
passed explicitly with `-var-file`, so a build pulls exactly its own secret):

```bash
cp debian13.pkrvars.hcl.example cluster.pkrvars.hcl
$EDITOR cluster.pkrvars.hcl              # pve01-03 cluster token + build password

# pve04 uses its own token, so it gets its own secret file:
cp debian13.pkrvars.hcl.example pve04.pkrvars.hcl
$EDITOR pve04.pkrvars.hcl               # pve04 token + build password
```

Both files are **gitignored** (`*.pkrvars.hcl`). Each holds the **secrets** only:
`proxmox_username`, `proxmox_token`, and `build_password`. The **per-node layout**
(`proxmox_url`, `proxmox_node`, bridge, storage, ISO) lives in the committed
`vars/pveXX.pkrvars.hcl` and is layered on with a second `-var-file` at build
time.

Set at minimum, in each secret file:

| Variable | Value |
|---|---|
| `proxmox_username` | `packer@pve!token` |
| `proxmox_token` | the secret from step 1 for that scope (`=…` part) |
| `build_password` | a strong temporary password (locked after the build) |

> Pass only the secret file that matches the target you are building — it is the
> first `-var-file` (see step 4). Because secret files are passed explicitly
> rather than auto-loaded, a build can never accidentally use another target's
> token.
>
> You can also export `PROXMOX_USERNAME`, `PROXMOX_TOKEN`, `PACKER_BUILD_PASSWORD`
> as environment variables instead of a secret file.

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

One command per target: the **first** `-var-file` supplies the **secrets**
(`cluster` or `pve04`), the **second** supplies that node's **layout**.

```bash
cd packer

# --- pve01-03 cluster: build on one node, replicate the template to the rest ---
packer validate -var-file=cluster.pkrvars.hcl -var-file=vars/pve01.pkrvars.hcl .   # syntax + plugin check
packer build    -var-file=cluster.pkrvars.hcl -var-file=vars/pve01.pkrvars.hcl .   # → template 'debian13-cloudinit' on pve01

# Then replicate the template to the other two cluster nodes (Proxmox GUI:
# right-click the template → Replicate → target node pve02, pve03 — or the
# qm/vzdump template replication CLI). No need to build on pve02/pve03.

# --- pve04 (separate, not in the cluster): build independently ---
packer build -var-file=pve04.pkrvars.hcl -var-file=vars/pve04.pkrvars.hcl .
```

> Each target's secret file is the **first** `-var-file`, so the token used is
> always the one for that target — a cluster build can never inherit pve04's
> token, or vice versa.

The build will:

1. Create a throwaway VM on the **build node** (from `vars/pveXX.pkrvars.hcl`),
   boot the netinst, and run the unattended install from the preseed (served by
   Packer's built-in HTTP server).
2. Log in over SSH and run `playbooks/provision.yml` to install:
   `zsh`, `git`, `tmux`, `htop`, `ncdu`, `curl`, `wget`,
   plus the cloud-init stack (`cloud-init`, `cloud-guest-utils`,
   `cloud-initramfs-growroot`, `qemu-guest-agent`), the
   **netplan** + `systemd-resolved` stack so clones configure IP/DNS via
   Proxmox cloud-init, and the **Tailscale** client (installed + enabled,
   but *not* authenticated).
3. Add **your** SSH key (baked in from the secret file) to the `ansible` user.
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
  Confirm them per node and fill them in in `vars/pveXX.pkrvars.hcl` (the
  `<FILL-IN>` placeholders). The disk pool must match across pve01-03 for the
  template to replicate.
- **Re-running:** the build is reproducible. Each run uses a fresh VM; delete the
  old `debian13-cloudinit` template first if you rebuild it.
- **Idempotency:** package/key/service tasks are idempotent; the
  `update-initramfs` and `cloud-init clean` steps are one-shot build steps and
  are intentionally marked `changed_when: true`.
