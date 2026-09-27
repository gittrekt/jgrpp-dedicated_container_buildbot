# OpenTTD JGRPP Dedicated Server Setup & Automation

This guide summarizes how to run and automate the JGRPP Dedicated Server container.

---

## 1. How the Container Works

The container image entrypoint is:
```dockerfile
ENTRYPOINT [ "/openttd/openttd", "-D", "-c", "/openttd_data/openttd.cfg", "-x", "-g" ]
```

Because the entrypoint ends with `-g`:
- Specifying the map/save in `Exec=` (Quadlet) or `command:` (Docker Compose) appends directly after `-g`.
- Example: `"save/example.sav"`
- Additional command-line flags (e.g. `-d net=1`) can also be appended after the map argument.
- Dedicated server console scripts (`on_server.scr`, `pre_dedicated.scr`, `on_server_connect.scr`) are automatically read from `/openttd_data/scripts/`.

---

## 2. Configuration Files

| File | Needed? | Purpose |
| :--- | :---: | :--- |
| `openttd.cfg` | **Required** | Core game rules, vehicles, economics, and network settings (`server_game_type`, `server_port`). |
| `private.cfg` | **Optional** | Holds server identity settings like `server_name` and `client_name`. |
| `secrets.cfg` | **Optional** | Server password, admin/rcon password, and company encryption keys. |
| `hotkeys.cfg`, `windows.cfg`, `favs.cfg`, `hs.dat` | **No** | Client GUI-only settings, ignored by the dedicated server. |

---

## 3. Running with Podman Quadlet

File: `openttd-jgrpp.container`

```ini
[Unit]
Description=OpenTTD JGRPP Dedicated Server
After=network-online.target
Wants=network-online.target

[Container]
ContainerName=openttd-jgrpp
Image=docker.io/gittrekt/jgrpp-dedicated:latest

# Maps container UID/GID 901 to host user
UserNS=keep-id:uid=901,gid=901

Volume=%h/.local/share/openttd:/openttd_data:Z
Volume=%h/.config/openttd/openttd.cfg:/openttd_data/openttd.cfg:Z
# Volume=%h/.config/openttd/private.cfg:/openttd_data/private.cfg:Z
# Volume=%h/.config/openttd/secrets.cfg:/openttd_data/secrets.cfg:Z

PublishPort=3979:3979/tcp
PublishPort=3979:3979/udp

HealthCmd=/openttd/healthcheck
HealthInterval=30s
HealthTimeout=5s
HealthStartPeriod=10s
HealthRetries=3

Exec="save/example.sav"

[Service]
Restart=on-failure
TimeoutStartSec=300

[Install]
WantedBy=default.target
```

### Installation:
```bash
mkdir -p ~/.config/containers/systemd/
cp openttd-jgrpp.container ~/.config/containers/systemd/
systemctl --user daemon-reload
systemctl --user start openttd-jgrpp
systemctl --user enable openttd-jgrpp
journalctl --user -u openttd-jgrpp -f
```

---

## 4. Running with Docker Compose

File: `docker-compose.yml`

```yaml
services:
  openttd:
    image: gittrekt/jgrpp-dedicated:latest
    container_name: openttd-jgrpp
    restart: unless-stopped
    ports:
      - "3979:3979/tcp"
      - "3979:3979/udp"
    volumes:
      - ${HOME}/.local/share/openttd:/openttd_data
      - ${HOME}/.config/openttd/openttd.cfg:/openttd_data/openttd.cfg:ro
      # - ${HOME}/.config/openttd/private.cfg:/openttd_data/private.cfg:ro
      # - ${HOME}/.config/openttd/secrets.cfg:/openttd_data/secrets.cfg:ro
    healthcheck:
      test: ["CMD", "/openttd/healthcheck"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 10s
    command: ["save/example.sav"]
```

### Usage:
```bash
docker compose up -d
docker compose logs -f
docker compose down
```

---

## 5. Extra Content & Transferring to a Remote Server

When starting a server with an existing save file, **OpenTTD does NOT automatically download missing content** (NewGRFs, AI, Game Scripts, or Base Sets). The server runs headlessly and cannot query BaNaNaS on startup; all content referenced by the save must already be present on disk with matching MD5 checksums.

### Local vs. Remote Deployment

- **Running locally on the same host:** No manual transfer is needed. The container volumes mount `${HOME}/.local/share/openttd` directly to `/openttd_data`, giving the server instant access to all content downloaded via your local client.
- **Deploying to a remote / new server:** You must transfer your local OpenTTD content directories and configuration files to the remote host before launching the container.

### What to Transfer:
1. `~/.local/share/openttd/content_download/` (NewGRFs, scenarios, and basesets downloaded in-game)
2. `~/.local/share/openttd/newgrf/` (Any manually installed `.grf` files)
3. `~/.local/share/openttd/save/` (Savegame `.sav` files)
4. `~/.config/openttd/openttd.cfg` (Server settings and `[newgrf]` list)
5. `~/.config/openttd/private.cfg` & `secrets.cfg` (Optional: server name, passwords, company auth)

### Transfer Examples

#### Using `rsync` (Recommended - fast, preserves permissions, resumes interrupted transfers):
```bash
# 1. Sync OpenTTD data directory (content, saves, newgrf)
rsync -avzP ~/.local/share/openttd/ user@remote-server:~/.local/share/openttd/

# 2. Sync OpenTTD configuration file
ssh user@remote-server "mkdir -p ~/.config/openttd"
rsync -avzP ~/.config/openttd/openttd.cfg user@remote-server:~/.config/openttd/openttd.cfg

# (Optional) Sync private.cfg and secrets.cfg if used:
# rsync -avzP ~/.config/openttd/private.cfg ~/.config/openttd/secrets.cfg user@remote-server:~/.config/openttd/
```

#### Using `scp`:
```bash
# 1. Ensure remote directories exist
ssh user@remote-server "mkdir -p ~/.local/share/openttd ~/.config/openttd"

# 2. Copy OpenTTD data directories
scp -r ~/.local/share/openttd/content_download user@remote-server:~/.local/share/openttd/
scp -r ~/.local/share/openttd/newgrf user@remote-server:~/.local/share/openttd/
scp -r ~/.local/share/openttd/save user@remote-server:~/.local/share/openttd/

# 3. Copy configuration files
scp ~/.config/openttd/openttd.cfg user@remote-server:~/.config/openttd/

# (Optional) Copy private.cfg and secrets.cfg if used:
# scp ~/.config/openttd/private.cfg ~/.config/openttd/secrets.cfg user@remote-server:~/.config/openttd/
```
