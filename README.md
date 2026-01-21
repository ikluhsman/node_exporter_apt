# node_exporter_apt

This is a Prometheus node_exporter addon that enables three metrics scraped from an apt update simulation command. The installation script should be run as root but the command will run as a normal user with non-root permissions and use the apt simulation to gather statisicts and be non-invasive to your system.

The installation assumes:

- node_exporter is installed and running
- uses APT simulation, non-root
- use systemd timer + hardened service
- safe to re-run on-the-fly
- intentionally simple and operationally boring

Install:

Run install.sh but you'll need to update the /etc/systemd/system/node_exporter.service file ExecStart adding this:

```
--collector.textfile.directory=/var/lib/node_exporter/textfile_collector
```

Optionally, run with the flag and node_exporter service file will be updated automagically:

```
sudo ENABLE_TEXTFILE_COLLECTOR=1 bash install-node-patch-exporter.sh
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
