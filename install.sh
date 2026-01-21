#!/usr/bin/env bash
set -euo pipefail

### CONFIG ###
EXPORTER_DIR="/var/lib/node_exporter/textfile_collector"
SCRIPT_PATH="/usr/local/bin/node_patch_status.sh"
SERVICE_PATH="/etc/systemd/system/node-patch-status.service"
TIMER_PATH="/etc/systemd/system/node-patch-status.timer"
SERVICE_USER="patchcheck"
SERVICE_GROUP="node_exporter"

ENABLE_TEXTFILE_COLLECTOR="${ENABLE_TEXTFILE_COLLECTOR:-0}"

echo "==> Installing Prometheus APT patch exporter (with cache age)"

### 1. Ensure textfile collector directory exists
mkdir -p "$EXPORTER_DIR"

### 2. Create service user if missing
if ! id "$SERVICE_USER" &>/dev/null; then
  useradd -r -s /usr/sbin/nologin "$SERVICE_USER"
fi

### 3. Permissions
chown "$SERVICE_USER:$SERVICE_GROUP" "$EXPORTER_DIR"
chmod 750 "$EXPORTER_DIR"

### 4. Exporter script
cat >"$SCRIPT_PATH" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

OUTDIR="/var/lib/node_exporter/textfile_collector"
OUTFILE="${OUTDIR}/node_patch_status.prom"
TMPFILE="$(mktemp)"
NOW="$(date +%s)"

export LC_ALL=C

UPDATES=$(apt-get -s upgrade 2>/dev/null | awk '/^Inst / { c++ } END { print c+0 }')
SECURITY=$(apt-get -s upgrade 2>/dev/null | grep -ci security || true)

STAMP_FILE="/var/lib/apt/periodic/update-success-stamp"
if [[ -r "$STAMP_FILE" ]]; then
  STAMP=$(stat -c %Y "$STAMP_FILE")
  CACHE_AGE=$(( NOW - STAMP ))
else
  CACHE_AGE=-1
fi

REBOOT_REQUIRED=0
if [[ -f /var/run/reboot-required ]]; then
  REBOOT_REQUIRED=1
fi

cat >"$TMPFILE" <<METRICS
# HELP node_updates_pending Number of pending APT package updates
# TYPE node_updates_pending gauge
node_updates_pending $UPDATES

# HELP node_security_updates_pending Number of pending security updates (heuristic)
# TYPE node_security_updates_pending gauge
node_security_updates_pending $SECURITY

# HELP node_apt_cache_age_seconds Age of the local APT package cache in seconds (-1 if unknown)
# TYPE node_apt_cache_age_seconds gauge
node_apt_cache_age_seconds $CACHE_AGE

# HELP node_patch_check_timestamp Last successful patch check (unix epoch)
# TYPE node_patch_check_timestamp gauge
node_patch_check_timestamp $NOW

# HELP node_reboot_required Whether a system reboot is required (1 = yes, 0 = no)
# TYPE node_reboot_required gauge
node_reboot_required $REBOOT_REQUIRED
METRICS

install -m 0644 "$TMPFILE" "$OUTFILE"
rm -f "$TMPFILE"
EOF

chmod 755 "$SCRIPT_PATH"

### 5. Patch exporter systemd service
cat >"$SERVICE_PATH" <<EOF
[Unit]
Description=Export APT patch status for Prometheus
After=network-online.target

[Service]
Type=oneshot
User=$SERVICE_USER
Group=$SERVICE_GROUP
ExecStart=$SCRIPT_PATH
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
ReadWritePaths=$EXPORTER_DIR
EOF

### 6. Timer
cat >"$TIMER_PATH" <<'EOF'
[Unit]
Description=Run APT patch status exporter every 30 minutes

[Timer]
OnBootSec=5m
OnUnitActiveSec=30m
Persistent=true

[Install]
WantedBy=timers.target
EOF

### 7. OPTIONAL: enable textfile collector in node_exporter
if [[ "$ENABLE_TEXTFILE_COLLECTOR" == "1" ]]; then
  echo "==> Enabling textfile collector in node_exporter"

  systemctl edit node_exporter <<EOF
[Service]
ExecStart=
ExecStart=/usr/local/bin/node_exporter \
  --collector.systemd \
  --collector.processes \
  --collector.textfile.directory=$EXPORTER_DIR
EOF

  systemctl daemon-reload
  systemctl restart node_exporter
fi

### 8. Enable timer and run once
systemctl daemon-reload
systemctl enable --now node-patch-status.timer
systemctl start node-patch-status.service

echo "==> Installation complete"

