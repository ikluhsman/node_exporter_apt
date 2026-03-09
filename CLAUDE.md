# node_exporter_apt

Installs a systemd timer + bash script that writes APT update metrics to the Prometheus node_exporter textfile collector.

## Key paths
- `install.sh` — installer script (run as root)
- `/usr/local/bin/node_patch_status.sh` — installed exporter script
- `/var/lib/node_exporter/textfile_collector/node_patch_status.prom` — output metrics file
- `/etc/systemd/system/node-patch-status.service` — oneshot service
- `/etc/systemd/system/node-patch-status.timer` — 30min timer (OnBootSec=5m)
- `/opt/node_exporter/node_exporter` — node_exporter binary

## Design
- Timer service runs as `node_exporter` user/group — no separate user needed
- `NODE_EXPORTER_USER` / `NODE_EXPORTER_GROUP` env vars override defaults (both default to `node_exporter`)
- Install script hard-fails if the user/group don't exist
- Textfile directory block is non-destructive (skipped if already exists)

## Prerequisites
```bash
groupadd --system node_exporter
useradd --system --no-create-home --shell /usr/sbin/nologin --gid node_exporter node_exporter
```

## Running the installer
```bash
bash /opt/node_exporter_apt/install.sh
```

If the textfile directory already exists with wrong ownership, fix it first:
```bash
chown node_exporter:node_exporter /var/lib/node_exporter/textfile_collector
chmod 750 /var/lib/node_exporter/textfile_collector
```

## Metrics exported
- `node_updates_pending` — pending APT package updates
- `node_security_updates_pending` — pending security updates (heuristic, grep for "security")
- `node_apt_cache_age_seconds` — age of local APT cache (-1 if unknown)
- `node_patch_check_timestamp` — unix epoch of last successful check
- `node_reboot_required` — 1 if /var/run/reboot-required exists, else 0

## Verifying
```bash
systemctl status node-patch-status.timer
systemctl status node-patch-status.service
cat /var/lib/node_exporter/textfile_collector/node_patch_status.prom
curl -s http://localhost:9100/metrics | grep node_updates
```
