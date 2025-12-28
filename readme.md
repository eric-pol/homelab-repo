#### Explanation of architecture & workflow of this github
This is not a production environment and is publicly shared as a portfolio. It is a learning experience for myself to learn the workflow of infrastructure as code. I'm reskilling myself in Linux engineering by testing and applying best practices to my homelab. 

# EP2Infra - Home Server Infrastructure
This repository contains the **Infrastructure as Code (IaC)** configuration for the EP2Infra server. It manages Docker containers, system configurations, and service dependencies using **Git**, **Docker Compose**, and **Systemd**.

## 🏗 Architecture

The infrastructure follows a strictly separated **Development** vs. **Production** workflow to ensure stability.

| Role | Location | Description |
| :--- | :--- | :--- |
| **Source of Truth** | `GitHub` | Central repository for all configurations. |
| **Development** | `~/homelab-repo` | Sandbox environment for editing, testing, and committing changes. |
| **Production** | `/opt/homelab-repo` | Live environment. **Read-only**. Only updated via `git pull`. |
| **Runtime** | `/opt/docker-services` | Symlink pointing to `/opt/homelab-repo/docker`. Used by Systemd. |

## 📂 Directory Structure

```text
/opt/homelab-repo/
├── docker/                 # Container definitions
│   ├── pihole/             # DNS & Adblocking
│   ├── portainer/          # Container Management
│   ├── roon/               # Music Server (Data is excluded via .gitignore)
│   └── samba/              # File Sharing
├── system/                 # Host configurations
│   ├── *.service           # Systemd unit files
│   └── etc/                # Host specific configs (fstab, etc.)
└── scripts/                # Maintenance & Deployment scripts

```
## 🚀 Workflow

### 1. Making Changes (Development)

All edits happen in the home directory (`~/homelab-repo`).

```bash
cd ~/homelab-repo
git pull
# Now you can edit files (e.g. nano docker/pihole/docker-compose.yml)

git add .

# If not automated by hook use 'gitleaks protect --staged' to check for secrets before committing
# On my main system I added .git/hooks/pre-commit to automatically do a 'gitleaks protect --staged' when trying to commit 
# (See pre-commit script at end of this documentation)

git commit -m "Description of change"
# In case gitleaks gives a warning but your 100% sure there is no secret you can force the commit without a gitleaks check using this command:
# git commit -m "Description of change" --no-verify

git push

```

### 2. Deploying Changes (Production)

Log in to the server and pull the latest changes.

```bash
cd /opt/homelab-repo
git pull

# Apply changes (Restart specific service)
sudo systemctl restart <service-name>

```

## 🛠 Service Management

Services are managed via `systemd` to ensure they start in the correct order (after mounts/network).

* **Check Status:** `systemctl status <service-name>`
* **Start/Stop:** `sudo systemctl start <service-name>` / `sudo systemctl stop <service-name>`
* **View Logs:** `journalctl -fu <service-name>`

### Service Overview

| Service | Systemd Unit | Port(s) | URL / Access | Notes |
| --- | --- | --- | --- | --- |
| **Samba** | `samba-docker.service` | 445 | `\\<IP>\` | Requires `/mnt` mounts to start. |
| **Pi-hole** | `pihole-docker.service` | 53, 8080 | `http://<IP>:8080/admin` | Uses host network 53. DNS Server. |
| **Portainer** | `portainer-docker.service` | 9443 | `https://<IP>:9443` | Container management UI. |
| **Roon** | `roon-docker.service` | Host | Roon Remote App | Requires `/mnt/roon` & `/mnt/backup`. |

## 🆘 Disaster Recovery

If the server needs to be rebuilt from scratch, follow these steps:

### 1. Clone Repository
```bash
sudo mkdir -p /opt/homelab-repo
sudo chown user:user /opt/homelab-repo
git clone [https://github.com/eric-pol/homelab-repo.git](https://github.com/eric-pol/homelab-repo.git) /opt/homelab-repo

```

### 2. Restore Symlinks

Create the runtime link for Docker services:

```bash
sudo ln -s /opt/homelab-repo/docker /opt/docker-services

```

### 3. Restore System Configuration (Fstab)

This step is critical to mount the drives before services start.

```bash
# Backup existing default fstab
sudo cp /etc/fstab /etc/fstab.bak

# Restore fstab from repo
sudo cp /opt/homelab-repo/system/etc/fstab /etc/fstab

# Reload systemd and mount all drives
sudo systemctl daemon-reload
sudo mount -a

```

### 4. Restore Secrets & Data

* **Secrets:** Copy `.env` files manually to `docker/<service>/.env` (These are not in Git).
* **Pi-hole Data:** Restore `etc-pihole` and `etc-dnsmasq.d` to prevent starting with an empty blocklist.
* **Roon Data:** Restore Roon Database to `/opt/homelab-repo/docker/roon/data`.
* **Portainer Data:** Ensure the named volume `portainer_portainer_data` exists.

### 5. Link & Start Services

```bash
# Link all service files
sudo ln -sf /opt/homelab-repo/system/*.service /etc/systemd/system/

# Reload Systemd
sudo systemctl daemon-reload

# Enable and Start services
sudo systemctl enable --now samba-docker.service
sudo systemctl enable --now pihole-docker.service
sudo systemctl enable --now portainer-docker.service
sudo systemctl enable --now roon-docker.service

```

```

```




# Example workflow 🚀

### Step 1: Adjust Docker Compose (Hard-linking volume)

We will update the `docker-compose.yml` file to mark the volume as `external` using the specific name we just found.

**Bash**

```bash
nano ~/homelab-repo/docker/portainer/docker-compose.yml

```

Replace the content with this version (pay attention to the volumes section at the bottom):

**YAML**

```yaml
services:
  portainer:
    image: portainer/portainer-ce:latest
    container_name: portainer
    # Systemd handles restarting, but 'unless-stopped' doesn't hurt as a fallback
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    volumes:
      - /etc/localtime:/etc/localtime:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - portainer_data:/data
    ports:
      - 9443:9443

volumes:
  portainer_data:
    external: true
    name: portainer_portainer_data

```

### Step 2: Create Systemd Service

Create the service file in your repository.

**Bash**

```bash
nano ~/homelab-repo/system/portainer-docker.service

```

Content (no fstab mounts needed here):

**Ini / TOML**

```ini
[Unit]
Description=Portainer Docker Service
Requires=docker.service
After=docker.service network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
User=eric
Group=eric
WorkingDirectory=/opt/docker-services/portainer
ExecStart=/usr/bin/docker compose up -d --remove-orphans
ExecStop=/usr/bin/docker compose down

[Install]
WantedBy=multi-user.target

```

### Step 3: Commit & Push (Dev)

Save everything to GitHub.

**Bash**

```bash
cd ~/homelab-repo
git add .
git commit -m "Migrate Portainer: Link existing volume and add systemd service"
git push

```

### Step 4: Deploy to Production

Now we move to the server side (`/opt`).

**Bash**

```bash
# 1. Pull the changes
cd /opt/homelab-repo
git pull

# 2. Link the new service file
sudo ln -sf /opt/homelab-repo/system/portainer-docker.service /etc/systemd/system/portainer-docker.service

# 3. Reload systemd
sudo systemctl daemon-reload

# 4. Start Portainer
sudo systemctl enable --now portainer-docker.service

# 5. Check the status
systemctl status portainer-docker.service

```

**The litmus test:**
If the status is green:
Go to `https://<YOUR-SERVER-IP>:9443` in your browser.


# -------------------------------------------------------------

## .git/hooks/pre-commit (script automatically checks for leaking secrets before commit)
```bash
cat > .git/hooks/pre-commit << 'EOF'
#!/usr/bin/env bash

# Homebrew pad toevoegen (voor Bluefin/Linux)
export PATH="$PATH:/home/linuxbrew/.linuxbrew/bin:/usr/local/bin"

echo "🔒 Gitleaks: Scanning staged files..."

if ! command -v gitleaks &> /dev/null; then
    echo "⚠️  Gitleaks niet gevonden via hook!"
    exit 0
fi

# Draai de scan
gitleaks protect --verbose --staged
exitCode=$?

if [ $exitCode -eq 1 ]; then
    echo "❌ GEVAAR: Secrets gevonden! Commit geblokkeerd."
    exit 1
fi
EOF
```
