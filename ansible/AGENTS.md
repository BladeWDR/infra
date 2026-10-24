# Repository Guidelines for AI Agents

These guidelines are tailored for AI coding assistants working in this repository. Follow them closely when developing, modifying, or testing Ansible tasks, playbooks, roles, and Docker service configurations.

---

## 1. Core Operating Rules

- **Direct Questions First**: If the user asks a direct question, prioritize answering it completely before proceeding with any other tasks.
- **Ansible Task Naming**: All task names **must** be a complete sentence ending in a period.
  - *Example*: `name: Ensure configuration directory exists.`
- **Ansible Handler Naming**: Handlers should be simpler action phrases and **must not** be complete sentences (no trailing period).
  - *Example*: `restart traefik`
- **Idempotency**: Maintaining idempotency is essential. Avoid bare `command` or `shell` tasks unless necessary, and always specify appropriate guards (`changed_when`, `creates`, `removes`, or condition checks).
- **Commit Messages**: Follow the **Conventional Commits** standard (e.g., `feat: ...`, `fix: ...`, `chore: ...`, `chore(deps): ...`).
- **Secrets & Vault**: Never expose or commit plaintext secrets. Secret variables belong in `secrets.yml` encrypted via Ansible Vault.
- **Capture Corrections as Lessons Learned**: If the user corrects an agent on any convention, procedure, preference, or technical pattern, immediately add that correction to **Section 6: Lessons Learned & User Corrections** to preserve the knowledge for future agent sessions.

---

## 2. Repository Structure

| Path | Description |
|---|---|
| `site.yml` | Primary orchestration playbook running plays by hostgroup and tags. |
| `hosts` | Inventory file organizing nodes into groups (`docker`, `servers`, `webservers`, `dns`, etc.). |
| `ansible.cfg` | Configuration specifying inventory, vault password file (`vaultpass`), remote user, and roles paths. |
| `services/` | Docker Compose fragments grouped by target hostname. |
| `roles/` | Custom and upstream roles (e.g., `ansible-role-docker-compose-generator`). |
| `group_vars/` | Group-level variables (e.g., `all/`, `docker/`, `dns/`, `nagios/`). |
| `host_vars/` | Host-specific variable overrides. |
| `secrets.yml` | Ansible Vault encrypted file containing sensitive variables. |
| `vaultpass` | Local vault password file used by Ansible (do not edit/expose). |
| `tools/` | Standalone utility scripts (e.g. `ping_hosts.sh`, `create_cnames`). |

---

## 3. Services & Docker Compose Architecture

All files under `services/` are modular compose file fragments managed by `ansible-role-docker-compose-generator`. They are merged into a single consolidated `compose.yaml` on the target remote system.

### Directory Layout
```text
services/
└── <target-hostname>/
    └── <service-name>/
        ├── compose.yaml          # Standard compose fragment
        └── config-<app>/         # Optional: configuration files to deploy
            ├── .dest             # Remote target directory path (supports Jinja2)
            └── config-files...   # Files copied as-is to destination
```

### Authoring Compose Fragments
- Each service directory must contain a `compose.yaml` file.
- Standard compose structure:
  ```yaml
  ---
  services:
    myservice:
      image: <image>:<tag>@sha256:<digest>
      container_name: myservice
      restart: unless-stopped
      networks:
        - traefik
      environment:
        - TZ={{ host_timezone }}
      volumes:
        - /apps/myservice/data:/data
  ```
- **Jinja2 Interpolation**: Variable interpolation is fully supported within compose fragments (e.g., `{{ host_timezone }}`, `{{ appdata_path }}`, `{{ TRAEFIK_HOST_DOMAIN }}`).
- **Config Directories (`config-*`)**:
  - The `.dest` file contains the remote target path (e.g., `{{ appdata_path }}/traefik/data`).
  - Files inside `config-*` are deployed directly to the specified destination path.
- **Disabling Services**: Services can be excluded on a host by listing them in `disabled_compose_files` under `host_vars` or `group_vars`:
  ```yaml
  disabled_compose_files:
    - service-name
  ```

---

## 4. Ansible Standards & Best Practices

- **FQCN (Fully Qualified Collection Names)**: Always use FQCNs for built-in and collection modules:
  - Prefer `ansible.builtin.apt`, `ansible.builtin.copy`, `ansible.builtin.file`, `ansible.builtin.systemd` over legacy short names.
- **Tag Conventions**:
  - The `compose` play in `site.yml` is tagged with both `compose` and `never`. It will **only** execute when explicitly requested using `--tags compose`.
  - Use tags when targeting specific subsystem updates (e.g., `--tags basics`, `--tags nagios`, `--tags docker`, `--tags tailscale`).
- **Targeting Hosts**: When applying changes, limit execution with `-l <hostname>` to avoid unintended changes across unrelated hosts.

---

## 5. Common Commands & Verification

### Syntax Check
Always run syntax verification before finalizing playbook changes:
```bash
ansible-playbook site.yml --syntax-check
```

### Deploying Compose Services
To deploy/update compose services for a specific host:
```bash
ansible-playbook site.yml --tags compose -l <hostname>
```

To automatically detect modified services from recent git changes (e.g. after merging PRs and running `git pull`) and target only those hosts:
```bash
./tools/deploy_compose.sh
```
*(Supports `-d` for dry run, `-y` to skip confirmation, `-p` for git pull diff, or passing extra Ansible flags like `--check`.)*

### Running Specific Roles/Tags
```bash
ansible-playbook site.yml --tags <tag_name> -l <hostname>
```

---

## 6. Lessons Learned & User Corrections

Whenever the user corrects an agent or provides guidance on workflows, conventions, or design decisions, document it here immediately so future agents adhere to it.

- **Supply Chain Security vs. Auto-Merge**: Do not enable blind automerge for Docker dependency updates. Manual review of Renovate PRs is an intentional defense against supply chain attacks.
- **Local Service Detection**: When working with or deploying services, always account for newly added, untracked compose definitions in the working tree (not just committed or staged files).

