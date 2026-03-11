#!/usr/bin/env bash
set -euo pipefail

### CONFIG ###
EXPORTER_DIR="/var/lib/node_exporter/textfile_collector"
SCRIPT_PATH="/usr/local/bin/node_patch_status.sh"
SERVICE_PATH="/etc/systemd/system/node-patch-status.service"
TIMER_PATH="/etc/systemd/system/node-patch-status.timer"

NODE_EXPORTER_USER="${NODE_EXPORTER_USER:-node_exporter}"
NODE_EXPORTER_GROUP="${NODE_EXPORTER_GROUP:-node_exporter}"

ENABLE_TEXTFILE_COLLECTOR="${ENABLE_TEXTFILE_COLLECTOR:-0}"

echo "==> Installing Prometheus APT patch exporter"

### 1. Ensure node_exporter user/group exist (create if missing)
if ! getent group "$NODE_EXPORTER_GROUP" >/dev/null; then
  echo "==> Creating group '$NODE_EXPORTER_GROUP'"
  groupadd --system "$NODE_EXPORTER_GROUP"
fi
if ! id "$NODE_EXPORTER_USER" &>/dev/null; then
  echo "==> Creating user '$NODE_EXPORTER_USER'"
  useradd --system --no-create-home --shell /usr/sbin/nologin \
    --gid "$NODE_EXPORTER_GROUP" "$NODE_EXPORTER_USER"
fi

### 1a. Patch the apt-installed node_exporter.service to run as this user
if systemctl cat node_exporter &>/dev/null; then
  echo "==> Configuring node_exporter.service to run as '$NODE_EXPORTER_USER'"
  mkdir -p /etc/systemd/system/node_exporter.service.d
  cat >/etc/systemd/system/node_exporter.service.d/user.conf <<DROPIN
[Service]
User=$NODE_EXPORTER_USER
Group=$NODE_EXPORTER_GROUP
DROPIN
  systemctl daemon-reload
fi

### 2. Ensure textfile collector directory exists (non-destructive)
if [[ ! -d "$EXPORTER_DIR" ]]; then
  mkdir -p "$EXPORTER_DIR"
  chown "$NODE_EXPORTER_USER:$NODE_EXPORTER_GROUP" "$EXPORTER_DIR"
  chmod 750 "$EXPORTER_DIR"
fi

### 3. Exporter script
cat >"$SCRIPT_PATH" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

OUTDIR="/var/lib/node_exporter/textfile_collector"
OUTFILE="${OUTDIR}/node_patch_status.prom"
NOW="$(date +%s)"

export LC_ALL=C

### Sanity check: must be writable
if [[ ! -w "$OUTDIR" ]]; then
  echo "node_patch_status: no write permission on $OUTDIR" >&2
  exit 1
fi

TMPFILE="$(mktemp "${OUTDIR}/.node_patch_status.XXXXXX")"

APT_OUTPUT=$(apt-get -s upgrade 2>/dev/null || true)
UPDATES=$(echo "$APT_OUTPUT" | awk '/^Inst / { c++ } END { print c+0 }')
SECURITY=$(echo "$APT_OUTPUT" | grep -ci security || true)

STAMP_FILE="/var/lib/apt/periodic/update-success-stamp"
if [[ -r "$STAMP_FILE" ]]; then
  STAMP=$(stat -c %Y "$STAMP_FILE")
  CACHE_AGE=$(( NOW - STAMP ))
else
  CACHE_AGE=-1
fi

REBOOT_REQUIRED=0
[[ -f /var/run/reboot-required ]] && REBOOT_REQUIRED=1

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

chmod 640 "$TMPFILE"
mv -f "$TMPFILE" "$OUTFILE"
EOF

chmod 755 "$SCRIPT_PATH"

### 4. systemd service
cat >"$SERVICE_PATH" <<EOF
[Unit]
Description=Export APT patch status for Prometheus
After=network-online.target

[Service]
Type=oneshot
User=$NODE_EXPORTER_USER
Group=$NODE_EXPORTER_GROUP
ExecStart=$SCRIPT_PATH
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
ReadWritePaths=$EXPORTER_DIR
EOF

### 5. Timer
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

### 6. OPTIONAL: enable textfile collector
if [[ "$ENABLE_TEXTFILE_COLLECTOR" == "1" ]]; then
  systemctl edit node_exporter <<EOF
[Service]
ExecStart=
ExecStart=/opt/node_exporter/node_exporter \
  --collector.systemd \
  --collector.processes \
  --collector.textfile.directory=$EXPORTER_DIR
EOF

  systemctl daemon-reload
  systemctl restart node_exporter
fi

### 7. Enable + run
systemctl daemon-reload
systemctl enable --now node-patch-status.timer
systemctl start node-patch-status.service

echo "==> Installation complete"
