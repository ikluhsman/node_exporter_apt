# node_exporter_apt

This is a Prometheus node_exporter addon that enables three metrics scraped from an apt update simulation command. The installation script should be run as root but the command will run as a normal user with non-root permissions and use the apt simulation to gather statisicts and be non-invasive to your system.

The installation assumes:

- node_exporter is installed via apt and running
- uses APT simulation, non-root
- uses systemd timer + hardened service
- safe to re-run on-the-fly
- intentionally simple and operationally boring

## Install

Run as root:

```
sudo bash install.sh
```

The script will:

- Create the `node_exporter` system user and group if they don't exist
- If `node_exporter.service` is present, write a systemd drop-in
  (`/etc/systemd/system/node_exporter.service.d/user.conf`) so node_exporter
  runs as the `node_exporter` user
- Create `/var/lib/node_exporter/textfile_collector` and enforce `node_exporter:node_exporter` ownership and `750` permissions on every run

To also enable the textfile collector in node_exporter automatically:

```
sudo ENABLE_TEXTFILE_COLLECTOR=1 bash install.sh
```

This adds `--collector.textfile.directory` to the node_exporter ExecStart via
`systemctl edit` and restarts the service. If you prefer to do it manually,
add the following flag to the node_exporter ExecStart:

```
--collector.textfile.directory=/var/lib/node_exporter/textfile_collector
```

Verify metrics are being published:

```
curl -s http://localhost:9100/metrics | grep node_textfile
curl -s http://localhost:9100/metrics | grep node_updates
```

Metrics

node_updates_pending Number of pending APT package updates
TYPE node_updates_pending gauge

node_security_updates_pending Number of pending security updates (heuristic)
TYPE node_security_updates_pending gauge

node_apt_cache_age_seconds Age of the local APT package cache in seconds (-1 if unknown)
TYPE node_apt_cache_age_seconds gauge

node_patch_check_timestamp Last successful patch check (unix epoch)
TYPE node_patch_check_timestamp gauge

node_reboot_required Whether a system reboot is required (1 = yes, 0 = no)
TYPE node_reboot_required gauge
