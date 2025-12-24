#### Explanation of workflow of this github
This is a learning experience for myself to learn the workflow of infrastructure as code. Just testing and applying best practices.

# Environment
## Dev-environment
~/homelab-repo is where I make all changes tot the server.

~/homelab-repo/
├── docker/              # All files for /opt/docker-services
│   ├── samba/
│   ├── pihole/
│   └── .env (template)
├── system/              # All files for /etc /bron or system-root
│   ├── etc/
│   │   ├── fstab
│   │   └── systemd/
│   └── cron/
└── scripts/             # All deployment logic

## Pre-prod-environment (git pull)
Exact copy of Dev-environment pulled from github
/opt/homelab-repo

## Prod-environment
Symlinks to the actual files or if not possble (like with fstab) just a copy 
from Pre-prod environment.


# Workflow

## 1) Development in Dev-environment
     - development in ~/homelab-repo
     - git add .
     - git commit -m "Commit message"
## 2) git push
## 3) git pull in pre-prod-environment
## 4) Link & start
    4.1. Create links & overwrite old/wrong links with -f (force)
         sudo ln -sf /opt/homelab-repo/system/samba-docker.service /etc/systemd/system/samba-docker.service

    4.2. Systemd update
         sudo systemctl daemon-reload

    4.3. Restart Services
         sudo systemctl enable --now samba-docker.service

    4.4. Check status
         systemctl status samba-docker.service


# Example workflow

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
