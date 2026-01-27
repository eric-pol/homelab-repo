#### Explanation of architecture & workflow of this github
This is not a production environment and is publicly shared as a portfolio. It is a learning experience for myself to learn the workflow of infrastructure as code. I'm reskilling myself in Linux engineering by testing and applying best practices to my homelab. 

#### For more detailed information: 'Homelab 3.0 documentation' (only available to owner (on-premise storage))

# 🏗 Homelab 3.0 Architecture
This repository contains the **Infrastructure as Code (IaC)** configuration for the Homelab 3.0. It manages Docker containers, system configurations, and service dependencies using **Git**, **Docker Compose**, and **Systemd**.

## Current Situation 27-1-2026: 

## 1. Summary

The primary objective of this architecture is to decouple **Storage**, **Infrastructure**, **Production Applications**, and **Experimental Lab** workloads. This separation ensures that "Family Production" services (Plex, Nextcloud, Internet Access) remain stable and resilient, while providing a flexible, disposable environment for advanced engineering practice (Kubernetes, AI, Ansible).

The core shift is from a **"Fat VM"** model to a **Tiered Service** model, leveraging Proxmox for compute isolation and NFS/SMB for shared storage.


## 2. Physical Layer (Layer 1)

Node: epx1 (Proxmox VE)

The physical foundation remains unchanged but is now strictly utilized as a Hypervisor, stripping away any "host-level" container duties.
* **CPU:** AMD Ryzen 7 7800X3D (8 Cores, 16 Threads)  \
* **RAM:** 64 GB DDR5  \
* **Network:** vmbr0 (Bridge) acting as the virtual switch.
* **Storage (Host):** nvme1n1 (1TB) for Proxmox OS and VM Boot Disks (LVM-Thin). 
* **Backups:** VM’s daily to /mnt/tanks/backups (TrueNAS), Proxmox config to local & cloud


## 3. Logical Topology: The 4-Tier Strategy

We divide the workload into four distinct Logical Zones (VMs).


### Tier 0: Storage Layer ("The Vault") 🏛️

Hostname: ep2storage
Role: Centralized Data Handler.
OS: TrueNAS
Configuration:
* **Hardware:** Holds **all** physical disk passthroughs (3 x 12TB SAS with HBA controller in IT mode). Configured in RaidZ1 (ZFS).   *(Passthrough explanation: Proxmox is configured to ignore these disks and the HBA card. It passes control of the physical hardware through Proxmox directly to the TrueNAS VM. TrueNAS thinks it is running on a physical machine*.)
* **Services:** Samba (SMB) and NFS Server. **No Application Containers.**
* **Output:** Exports /mnt/tank/media, /mnt/tank/home, /mnt/tank/data and /mnt/backups to the network.
* **Backups:** backups of important data to external/ cloud.
* **Why:** This isolates the "Passthrough Risk"<sup>6</sup>. If this VM needs maintenance, apps in other tiers pause but do not crash or lose configuration. \



### Tier 1: Core Infrastructure ("Utility Layer") 🚏

Hostname: ep2infra-new
Role: Critical Network Services ("Always On").
OS: Ubuntu Server (Small VM: 2 vCPU, 4GB RAM).
Orchestration: Docker Compose (via Ansible).
Services:
* **Pi-hole:** DNS & Adblocking.  
* **Keycloak:** Identity Provider (PostgreSQL DB stored on local VM disk for speed). (ON HOLD)
* **Traefik/Nginx:** Reverse Proxy (Entry point for all HTTP services). (ON HOLD)
* **Why:** Separates "Internet/Login" dependency from Media apps. High Availability requirement.


### Tier 2: Production Apps ("Family SLA") 👨‍👩‍👦

Hostname: ep2apps
Role: Trusted Daily Driver Applications.
OS: Ubuntu Server (Medium VM: 4 vCPU, 16GB RAM).
Orchestration: Docker Compose (via Ansible).
Storage: Mounts /mnt/nas and /mnt/media via NFS from Tier 0.
Services:
* **Plex + Plexamp:** Media Streaming.  \
* **Nextcloud:** File Cloud. (ON HOLD)
* **Roon:** Music Core.  \
* **Why:** Ensures stability for the family. Updates are planned. Snapshots provide instant rollback.


### Tier 3: The Lab ("Chaos Zone") 🌋

Hostname(s): ep2lab-01, k8s-master, ep2ai
Role: Learning, Testing, Breaking.
OS: Various (Ubuntu, RHEL, Talos Linux, etc.). 
Orchestration: Kubernetes, Podman, Raw Binaries.
Services:
* **Kubernetes Cluster:** Control plane + Workers. (ON HOLD) \
* **AI Server:** LLM testing.  \
* **Test Distros:** RHEL/Fedora experiments.
* **Why:** Complete isolation. You can wipe these VMs daily via Ansible without affecting the home Internet or Plex.


## 4. Network & Storage Flow

### A. Storage Architecture (NFS/SMB)

Instead of internal mounts, we use network mounts.

* ep2storage (IP: .20) → Exports /tank/media (NFS), /tank/data (NFS), /tank/home/ (SMB), /tank/backups (NFS/SMB).
* ep2apps (IP: .30) → Mounts 192.168.178.20:/volume1/media to /mnt/media.
    * Docker containers in ep2apps use volumes mapping to this local mount: -v /mnt/tank/media:/data.


### B. Network Traffic

* **Ingress:** Router (Port 80/443) → ep2infra (Reverse Proxy) → Routes traffic to ep2apps (Nextcloud/Plex) or ep2infra (Keycloak). (ON HOLD)
* **Internal:** All VMs use ep2infra (Pi-hole) for DNS resolution.


## 5. Management Workflow (Ansible)

The Ansible workflow evolves from managing a single host to managing an **Inventory**.

**Inventory File (hosts.ini):**
Ini, TOML

[storage] \
ep2storage ansible_host=192.168.178.20 \
 \
[infra] \
ep2infra_new ansible_host=192.168.178.11 \
 \
[apps] \
ep2apps ansible_host=192.168.178.30 \
 \
[lab] \
ep2k8s-01 ansible_host=192.168.178.40 \


**Playbook Structure:**
* site.yml: The master playbook.
* roles/common: Applied to ALL (Users, SSH keys, Dotfiles).
* roles/docker: Installs Docker engine (Applied to Infra & Apps).
* roles/nas: Configures NFS/Samba exports (Applied to Storage).


## 📂 Directory Structure Automation
```text
/homelab-repo/
├── ansible
│   ├── ansible.cfg
│   ├── inventory
│   │   └── hosts.ini
│   ├── requirements.yml
│   ├── roles
│   │   ├── common
│   │   │   ├── handlers
│   │   │   │   └── main.yml
│   │   │   └── tasks
│   │   │       └── main.yml
│   │   ├── docker_service
│   │   │   └── tasks
│   │   │       └── main.yml
│   │   └── storage_nfs
│   │       └── tasks
│   └── site.yml
├── docker
│   ├── apps
│   │   ├── nextcloud
│   │   │   └── docker-compose.yml
│   │   ├── plex
│   │   │   └── docker-compose.yml
│   │   └── roon
│   │       └── docker-compose.yml
│   └── infra
│       └── pihole
│           ├── docker-compose.yml
│           └── etc-pihole
│               ├── setupVars.conf
│               └── tls.pem
├── readme.md

```

## 🛠 Service Management

Services are managed via `systemd` to ensure they start in the correct order (after mounts/network).

* **Check Status:** `systemctl status <service-name>`
* **Start/Stop:** `sudo systemctl start <service-name>` / `sudo systemctl stop <service-name>`
* **View Logs:** `journalctl -fu <service-name>`
# -------------------------------------------------------------


## 🤖 Infrastructure Automation (Ansible)

28-12-2025 the deployment workflow has shifted from manual `git pull` operations to **Ansible**. This ensures idempotency, automates secret management via Vault, and handles system configuration (users, permissions, systemd) without manual intervention.


### 🚀 Git & Ansible Workflow

#### 1. Git workflow
```
#### 1. Making Changes (Control Node)

All edits happen locally on the Bluefin desktop (Control Node).

1. 'git pull' to control host
2. 'git branch <feature/branchname>' to create safe workspace.
3. **Edit Files:** Modify Docker configurations or Ansible playbooks.
4. **Commit & Push:** Ensure changes are on GitHub (Ansible pulls from the remote repo).
5. On Github merge pull request (could be done locally in case of only 1 editor)

```bash
cd ~/homelab-repo
git add .
git commit -m "Update Keycloak configuration"
git push

```

#### 2. Deploying Changes (Ansible)

Run the playbook from the Control Node. This connects to the server, pulls the latest code, renders templates with secrets, and restarts services if necessary.

```bash
cd ~/homelab-repo/ansible

# Deploy configuration with user password
ansible-playbook -i inventory/hosts.ini site.yml -l apps -K

# In case of use Ansible password vault:
ansible-playbook -i inventory/hosts.ini site.yml --ask-vault-pass

```

* **Prompts:** You will be asked for the **Vault Password** to decrypt secrets in memory.
* **No Sudo Required:** The `ansible` user has `NOPASSWD` sudo rights on the server.


### 🔐 Secret Management (Ansible Vault)

Sensitive data (passwords, API keys) are never stored in plain text. They are encrypted in `group_vars/all/vault.yml`.

* **View/Edit Secrets:**
```bash
ansible-vault edit group_vars/all/vault.yml

```


* **Create New Vault:**
```bash
ansible-vault create group_vars/all/vault.yml

```

# -------------------------------------------------------------

### 🆘 Bootstrapping (New Server Setup)

If the `ep2infra` VM is rebuilt, the `ansible` service user must be recreated before the main playbook can run.

1. **Ensure SSH Access:** Make sure your personal SSH key is copied to the server (`ssh-copy-id eric@<IP>`).
2. **Run Bootstrap:** This script logs in as `eric`, creates the `ansible` user, installs the SSH key, and configures sudoers.

```bash
# Requires -K to ask for the BECOME (sudo) password of user 'eric'
ansible-playbook -i inventory/hosts.ini bootstrap.yml --ask-vault-pass -K

```
# -------------------------------------------------------------

## 🆘 Disaster Recovery (ATTENTION -- Needs some changes after moving to Ansible workflow)

If the server needs to be rebuilt from scratch, follow these steps:

1. Install Proxmox
2. Setup TrueNAS VM ep2storage
3. Restore TrueNAS config file
4. Restore backup files for ep2infra, ep2apps, and others


# -------------------------------------------------------------

## 🔒 Secret leaks prevention for Github
.git/hooks/pre-commit (script automatically checks for leaking secrets before commit)
```bash
#!/bin/bash

# Add Homebrew path (needed for Bluefin/Linuxbrew)
export PATH="$PATH:/home/linuxbrew/.linuxbrew/bin:/usr/local/bin"

echo "🔒 Gitleaks: Scanning staged files..."

# Check if gitleaks can be found
if ! command -v gitleaks &> /dev/null; then
    echo "⚠️  Gitleaks not found! Is it installed?"
    echo "   Stop scan and proceed commit..."
    exit 0
fi

# Run gitleaks scan
gitleaks protect --verbose --staged

exitCode=$?

if [ $exitCode -eq 1 ]; then
    echo "❌ WARNING: Secrets found! Commit blocked."
    exit 1
fi
```
