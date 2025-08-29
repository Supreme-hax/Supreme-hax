> "$(outfile appops_recent.csv)"
echo "package,op,mode,last" >>"$(outfile appops_recent.csv)"

interesting_ops=$(cat <<'OPS'
CAMERA
RECORD_AUDIO
READ_SMS
WRITE_SMS
READ_CLIPBOARD
WRITE_CLIPBOARD
SYSTEM_ALERT_WINDOW
REQUEST_INSTALL_PACKAGES
GET_USAGE_STATS
POST_NOTIFICATION
ACCESS_NOTIFICATIONS
READ_DEVICE_IDENTIFIERS
OPS
)

appops_get() { cmd appops get "$1" 2>/dev/null || true; }

while read -r P; do
  [ -z "$P" ] && continue
  AOUT="$APPOPS_DIR/${P}.txt"
  appops_get "$P" >"$AOUT"
  while read -r OP; do
    [ -z "$OP" ] && continue
    if grep -Eiq "$OP: " "$AOUT"; then
      LINE="$(grep -Ei "$OP: " "$AOUT" | head -n1)"
      MODE="$(echo "$LINE" | sed -n 's/.*mode=\([^;]*\).*/\1/p')"
      LAST="$(echo "$LINE" | sed -n 's/.*time=\([^;]*\).*/\1/p')"
      echo "$P,$OP,${MODE:-unknown},${LAST:-unknown}" >>"$(outfile appops_recent.csv)"
    fi
  done <<< "$interesting_ops"
done < "$PKG_LIST_FILE"
ok "AppOps collected (appops_recent.csv)"

# ---------- Accessibility, overlays, listeners ----------
sep
log "Checking accessibility services and listeners..."
savecmd "accessibility_enabled.txt" settings get secure accessibility_enabled
savecmd "enabled_accessibility_services.txt" settings get secure enabled_accessibility_services
savecmd "notification_listeners.txt" settings get secure enabled_notification_listeners
savecmd "notification_assistant.txt" settings get secure enabled_notification_assistant
savecmd "overlay_warn_apps.txt" grep -E ",SYSTEM_ALERT_WINDOW$" "$(outfile perm_summary.csv)" || true

# ---------- Device admin / policy owners ----------
sep
log "Inspecting device policy and admins..."
savecmd "device_policy.txt" dumpsys device_policy
grep -E "Device Admin|Active admin|Profile owner|Device owner" "$(outfile device_policy.txt)" >"$(outfile device_admins_short.txt)" || true

# ---------- Camera / mic active sessions ----------
sep
log "Checking active/recent camera and microphone usage..."
savecmd "camera_dump.txt" dumpsys media.camera
savecmd "audio_dump.txt"  dumpsys audio
grep -iE "Client|Active|cameraId|PID|Package" "$(outfile camera_dump.txt)" >"$(outfile camera_activity.txt)" || true
grep -iE "record|input|mic|Capture" "$(outfile audio_dump.txt)" >"$(outfile mic_activity.txt)" || true

# ---------- ADB / developer mode ----------
sep
log "Checking ADB/developer settings..."
savecmd "adb_enabled.txt" settings get global adb_enabled
savecmd "adb_tcp_port.txt" getprop service.adb.tcp.port
savecmd "dev_settings.txt" settings get global development_settings_enabled

# ---------- Jobs / alarms (persistence clues) ----------
sep
log "Collecting jobs and alarms..."
savecmd "jobscheduler.txt" cmd jobscheduler get
savecmd "alarms.txt" dumpsys alarm

# ---------- Network activity ----------
sep
log "Enumerating active network connections..."
savecmd "ss_tun.txt" ss -tun
savecmd "ss_tunp.txt" ss -tunp || true
savecmd "netstat_an.txt" netstat -an || true

awk '/ESTAB|UNCONN|ESTABLISHED|CONNECTED/ {print $5}' "$(outfile ss_tun.txt)" \
  | sed 's/::ffff://g' | sed 's/:.*//' | grep -E '^[0-9]+\.[0-9]+' \
  | sort | uniq -c | sort -nr >"$(outfile top_endpoints.txt)" || true

# Optional LAN discovery (consent required)
if [ $RUN_NMAP -eq 1 ] && [ $QUICK -eq 0 ] && [ $WIFI_DEEP -eq 1 ] && command -v nmap >/dev/null 2>&1; then
  sep
  log "Running LAN discovery (requires permission to scan your network)..."
  IP_CIDR="$(ip -o -f inet addr show | awk '{print $4}' | grep -vE '^127\.|docker|tun|lo' | head -n1)"
  if [ -n "${IP_CIDR:-}" ]; then
    savecmd "nmap_ping_sweep.txt" nmap -sn "$IP_CIDR"
  else
    warn "Could not detect local subnet for nmap scan."
  fi
fi

# ---------- Risk scoring ----------
sep
log "Scoring risk (heuristic)..."
ALLOW_PREFIXES='^(com\.android\.|com\.google\.|com\.qualcomm\.|com\.samsung\.android\.)'
HIGH_PERMS='(CAMERA|RECORD_AUDIO|READ_SMS|RECEIVE_SMS|SEND_SMS|READ_CALL_LOG|ACCESS_FINE_LOCATION|REQUEST_INSTALL_PACKAGES|SYSTEM_ALERT_WINDOW|BIND_ACCESSIBILITY_SERVICE)'
RECENT_OPS='(CAMERA|RECORD_AUDIO|READ_SMS|SYSTEM_ALERT_WINDOW|GET_USAGE_STATS)'

declare -A PERMFLAG OPFLAG
while IFS=, read -r pkg perm; do
  [ "$pkg" = "package" ] && continue
  if echo "$perm" | grep -Eiq "$HIGH_PERMS"; then PERMFLAG["$pkg"]=1; fi
done <"$(outfile perm_summary.csv)"

while IFS=, read -r pkg op mode last; do
  [ "$pkg" = "package" ] && continue
  if echo "$op" | grep -Eiq "$RECENT_OPS" && echo "$mode" | grep -qi "allow"; then OPFLAG["$pkg"]=1; fi
done <"$(outfile appops_recent.csv)"

RISK_LIST="$(outfile risk_list.csv)"
echo "package,risk,reason" >"$RISK_LIST"
while read -r P; do
  [ -z "$P" ] && continue
  if echo "$P" | grep -Eq "$ALLOW_PREFIXES"; then continue; fi
  has_perm=${PERMFLAG["$P"]+yes}
  has_op=${OPFLAG["$P"]+yes}
  if [ "${has_perm:-no}" = "yes" ] && [ "${has_op:-no}" = "yes" ]; then
    echo "$P,HIGH,Dangerous permissions + recent sensitive AppOps" >>"$RISK_LIST"
  elif [ "${has_perm:-no}" = "yes" ]; then
    echo "$P,MEDIUM,Dangerous permissions granted" >>"$RISK_LIST"
  elif [ "${has_op:-no}" = "yes" ]; then
    echo "$P,MEDIUM,Recent sensitive AppOps activity" >>"$RISK_LIST"
  else
    echo "$P,LOW,No notable signals" >>"$RISK_LIST"
  fi
done < "$PKG_LIST_FILE"
ok "Risk scoring complete (risk_list.csv)"

# ---------- Wi-Fi checks ----------
WIFI_RISK="UNKNOWN"
WIFI_DETAILS_FILE="$(outfile wifi_details.txt)"
WIFI_PORTS_FILE="$(outfile router_ports.txt)"

if [ $RUN_WIFI -eq 1 ]; then
  sep
  log "Assessing Wi‑Fi security (passive + gateway ports)..."
  savecmd "wifi_dump.txt" dumpsys wifi
  SSID="$(grep -m1 -oE 'SSID: ".*"' "$(outfile wifi_dump.txt)" | sed 's/SSID: "\(.*\)"/\1/')"
  BSSID="$(grep -m1 -oE 'BSSID: [0-9a-fA-F:]{17}' "$(outfile wifi_dump.txt)" | awk '{print $2}')"
  STANDARD="$(grep -m1 -oE 'Standard: .*' "$(outfile wifi_dump.txt)" | sed 's/Standard: //')"
  CAPS="$(grep -m1 -oE 'Capabilities: .*' "$(outfile wifi_dump.txt)" | sed 's/Capabilities: //')"
  if [ -z "$CAPS" ]; then
    CAPS="$(grep -m1 -oE 'WPA[0-9A-Z_-]+' "$(outfile wifi_dump.txt)" || true)"
  fi

  GATEWAY="$(ip route | awk '/default/ {print $3; exit}')"
  DNS1="$(getprop net.dns1 2>/dev/null || true)"
  DNS2="$(getprop net.dns2 2>/dev/null || true)"

  {
    echo "SSID: ${SSID:-unknown}"
    echo "BSSID: ${BSSID:-unknown}"
    echo "Standard: ${STANDARD:-unknown}"
    echo "Capabilities: ${CAPS:-unknown}"
    echo "Gateway: ${GATEWAY:-unknown}"
    echo "DNS1: ${DNS1:-unknown}"
    echo "DNS2: ${DNS2:-unknown}"
  } > "$WIFI_DETAILS_FILE"

  # Security heuristic
  SEC_TAG="unknown"
  echo "$CAPS" | grep -qiE 'WEP' && SEC_TAG="WEP"
  echo "$CAPS" | grep -qiE 'SAE|WPA3' && SEC_TAG="WPA3"
  if [ "$SEC_TAG" = "unknown" ] && echo "$CAPS" | grep -qiE 'WPA2|RSN|PSK'; then SEC_TAG="WPA2"; fi
  if [ "$SEC_TAG" = "unknown" ] && echo "$CAPS" | grep -qiE 'OWE|OPEN|NONE'; then SEC_TAG="OPEN"; fi

  # Router minimal port check
  : > "$WIFI_PORTS_FILE"
  if [ -n "${GATEWAY:-}" ]; then
    OPEN_PORTS=""
    PORT_SET="22,23,53,80,443,445,7547,8080,8443"
    if command -v nmap >/dev/null 2>&1 && [ $RUN_NMAP -eq 1 ]; then
      savecmd "router_nmap.txt" nmap -sT -Pn --open -p "$PORT_SET" "$GATEWAY"
      OPEN_PORTS="$(grep -E '^[0-9]+/tcp +open' "$(outfile router_nmap.txt)" | awk '{print $1}' | cut -d/ -f1 | paste -sd, -)"
    else
      # Fallback: TCP connect test
      IFS=, read -r -a plist <<< "$PORT_SET"
      for p in "${plist[@]}"; do
        (echo >/dev/tcp/"$GATEWAY"/"$p") >/dev/null 2>&1 && echo "open $p/tcp" >> "$WIFI_PORTS_FILE" || true
      done
      OPEN_PORTS="$(awk '{print $2}' "$WIFI_PORTS_FILE" | cut -d/ -f1 | paste -sd, -)"
    fi
    [ -z "${OPEN_PORTS:-}" ] && OPEN_PORTS="none"
    echo "Open ports: $OPEN_PORTS" >> "$WIFI_DETAILS_FILE"
  else
    warn "No gateway detected; skipping router port check."
  fi

  # Wi‑Fi risk heuristic
  case "$SEC_TAG" in
    WEP|OPEN) WIFI_RISK="HIGH" ;;
    WPA2) WIFI_RISK="MEDIUM" ;;
    WPA3) WIFI_RISK="LOW" ;;
    *) WIFI_RISK="UNKNOWN" ;;
  esac

  # Escalate if risky mgmt ports
  if grep -q ' 23/tcp\|open 23/tcp' "$(outfile router_nmap.txt)" 2>/dev/null || grep -q 'open 23/tcp' "$WIFI_PORTS_FILE" 2>/dev/null; then
    WIFI_RISK="HIGH"
  fi
  if grep -q '7547' "$(outfile router_nmap.txt)" 2>/dev/null || grep -q '7547' "$WIFI_PORTS_FILE" 2>/dev/null; then
    [ "$WIFI_RISK" = "LOW" ] && WIFI_RISK="MEDIUM" || WIFI_RISK="HIGH"
  fi

  ok "Wi‑Fi assessment complete (wifi_details.txt, router_ports.txt)"
fi

# ---------- Markdown report ----------
sep
log "Generating final report..."
HIGH_LIST="$(awk -F, '$2=="HIGH"{print "- **Package:** "$1" — **Reason:** "$3}' "$(outfile risk_list.csv)")"
MED_LIST="$(awk -F, '$2=="MEDIUM"{print "- **Package:** "$1" — **Reason:** "$3}' "$(outfile risk_list.csv)")"

cat >"$MD" <<MDOC
# AndroidGuardian report

- **Generated:** $START_TS
- **Android:** $ANDROID_VER
- **Model:** $DEVICE_MODEL
- **Packages audited:** $PKG_COUNT

## High-risk apps
${HIGH_LIST:-None}

## Medium-risk apps
${MED_LIST:-None}

## Notable system signals
- **Accessibility services:** See enabled_accessibility_services.txt
- **Notification listeners:** See notification_listeners.txt
- **Device admins:** See device_admins_short.txt
- **Camera activity:** See camera_activity.txt
- **Mic activity:** See mic_activity.txt
- **ADB status:** See adb_enabled.txt and adb_tcp_port.txt
- **Top remote endpoints:** See top_endpoints.txt

## Wi‑Fi overview
- **Details:** See wifi_details.txt
- **Router ports:** See router_ports.txt
- **Risk:** ${WIFI_RISK:-N/A}

## Network artifacts
- **Connections (TCP/UDP):** ss_tun.txt, ss_tunp.txt, netstat_an.txt
- **LAN discovery (if enabled):** nmap_ping_sweep.txt

## Full artifacts
All raw outputs are in: $REPORT_DIR

> Tip: Investigate any HIGH risk first, then MEDIUM with overlays/accessibility/admin privileges.
MDOC

# ---------- JSON summary (no CSV slurp; resilient) ----------
set +e
if command -v jq >/dev/null 2>&1; then
  jq -n \
    --arg version "$VERSION" \
    --arg generated "$START_TS" \
    --arg android "$ANDROID_VER" \
    --arg model "$DEVICE_MODEL" \
    --arg wifi_risk "${WIFI_RISK:-N/A}" \
    --arg packages "packages.txt" \
    --arg permissions "perm_summary.csv" \
    --arg appops "appops_recent.csv" \
    --arg risks "risk_list.csv" \
    --arg wifi_details "wifi_details.txt" \
    --arg router_ports "router_ports.txt" \
    '{ meta:{tool:"AndroidGuardian",version:$version,generated:$generated,android:$android,model:$model},
       wifi:{risk:$wifi_risk,details:$wifi_details,router_ports:$router_ports},
       files:{packages:$packages,permissions:$permissions,appops:$appops,risks:$risks} }' > "$JSON"
else
  printf '{"meta":{"tool":"AndroidGuardian","version":"%s","generated":"%s","android":"%s","model":"%s"}}' \
    "$VERSION" "$START_TS" "$ANDROID_VER" "$DEVICE_MODEL" > "$JSON"
fi
set -e

ok "Report generated:"
echo " - $MD"
echo " - $JSON"
echo " - $LOG"
sep
ok "Done."
SH

chmod +x $HOME/AndroidGuardian/guardian.sh
$HOME/AndroidGuardian/guardian.sh --wifi
rm -f $HOME/AndroidGuardian/guardian.sh && mkdir -p $HOME/AndroidGuardian && nano $HOME/AndroidGuardian/guardian.sh
rm -f $HOME/AndroidGuardian/guardian.sh && mkdir -p $HOME/AndroidGuardian && cat > $HOME/AndroidGuardian/guardian.sh <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
# AndroidGuardian – v2.0
# Self‑healing, self‑documenting, Wi‑Fi + Device Audit Script
# Author: Ah's AI Copilot
# -----------------------------------------------------------

set -e

ROOT_DIR="$HOME/AndroidGuardian"
REPORT_DIR="$ROOT_DIR/reports/$(date '+%Y-%m-%d_%H-%M-%S')"
README="$REPORT_DIR/README.md"

# === Permission & Dependency Check ===
termux-setup-storage
pkg update -y && pkg install -y net-tools iproute2 grep util-linux procps

# === Self-Healing Folder Structure ===
mkdir -p "$REPORT_DIR"

# === Wi-Fi Audit ===
WIFI_INFO="$REPORT_DIR/wifi_info.txt"
{
    echo "=== Wi-Fi INFO ($(date)) ==="
    ip addr show wlan0 2>/dev/null || echo "No wlan0 interface found."
    echo
    netstat -rn
} > "$WIFI_INFO"

# === Device Info Audit ===
DEVICE_INFO="$REPORT_DIR/device_info.txt"
{
    echo "=== DEVICE INFO ($(date)) ==="
    uname -a
    echo "Uptime: $(uptime -p)"
    echo "Storage:"
    df -h
} > "$DEVICE_INFO"

# === Auto-generate README.md ===
cat > "$README" <<EOM
# AndroidGuardian Audit Report
Generated: $(date)

## Files:
- **wifi_info.txt** — Wi-Fi interface, IP, and routing info.
- **device_info.txt** — Kernel, uptime, storage usage.

## How to read:
\`\`\`bash
cat wifi_info.txt
cat device_info.txt
\`\`\`
EOM

echo "✅ Audit complete. Reports saved in: $REPORT_DIR"
echo "📄 README.md generated with usage guide."
EOF

chmod +x $HOME/AndroidGuardian/guardian.sh && $HOME/AndroidGuardian/guardian.sh --wifi
ip route show 2>/dev/null
rm -f $HOME/AndroidGuardian/guardian.sh && mkdir -p $HOME/AndroidGuardian && cat > $HOME/AndroidGuardian/guardian.sh <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
# AndroidGuardian – v2.0
# Self‑healing, self‑documenting, Wi‑Fi + Device Audit Script
# Author: Ah's AI Copilot
# -----------------------------------------------------------

set -e

ROOT_DIR="$HOME/AndroidGuardian"
REPORT_DIR="$ROOT_DIR/reports/$(date '+%Y-%m-%d_%H-%M-%S')"
README="$REPORT_DIR/README.md"

# === Permission & Dependency Check ===
termux-setup-storage
pkg update -y && pkg install -y net-tools iproute2 grep util-linux procps

# === Self-Healing Folder Structure ===
mkdir -p "$REPORT_DIR"

# === Wi-Fi Audit ===
WIFI_INFO="$REPORT_DIR/wifi_info.txt"
{
    echo "=== Wi-Fi INFO ($(date)) ==="
    ip addr show wlan0 2>/dev/null || echo "No wlan0 interface found."
    echo
    netstat -rn
} > "$WIFI_INFO"

# === Device Info Audit ===
DEVICE_INFO="$REPORT_DIR/device_info.txt"
{
    echo "=== DEVICE INFO ($(date)) ==="
    uname -a
    echo "Uptime: $(uptime -p)"
    echo "Storage:"
    df -h
} > "$DEVICE_INFO"

# === Auto-generate README.md ===
cat > "$README" <<EOM
# AndroidGuardian Audit Report
Generated: $(date)

## Files:
- **wifi_info.txt** — Wi-Fi interface, IP, and routing info.
- **device_info.txt** — Kernel, uptime, storage usage.

## How to read:
\`\`\`bash
cat wifi_info.txt
cat device_info.txt
\`\`\`
EOM

echo "✅ Audit complete. Reports saved in: $REPORT_DIR"
echo "📄 README.md generated with usage guide."
EOF

chmod +x $HOME/AndroidGuardian/guardian.sh && $HOME/AndroidGuardian/guardian.sh --wifi
bash -lc "$(curl -fsSL https://raw.githubusercontent.com/ah-sandbox/bootstraps/main/crypto-localengine-autodetect.sh)"
#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
green(){ printf "\033[32m%s\033[0m\n" "$*"; }
yellow(){ printf "\033[33m%s\033[0m\n" "$*"; }
red(){ printf "\033[31m%s\033[0m\n" "$*"; }
log(){ green "▶ $*"; }
warn(){ yellow "▲ $*"; }
die(){ red "✖ $*"; exit 1; }
[ -d "/data/data/com.termux/files/usr" ] || die "Termux environment not detected."
log "Updating Termux packages…"
yes | pkg update -y >/dev/null 2>&1 || true
yes | pkg upgrade -y >/dev/null 2>&1 || true
yes | pkg install -y python openssl-tool git curl tar coreutils clang libxml2 libxslt >/dev/null 2>&1
bash -lc "$(curl -fsSL https://raw.githubusercontent.com/ah-sandbox/bootstraps/main/crypto-localengine-bootstrap.sh || echo '__INLINE__')"
chmod +x install.sh
./install.sh
#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
green(){ printf "\033[32m%s\033[0m\n" "$*"; }
yellow(){ printf "\033[33m%s\033[0m\n" "$*"; }
red(){ printf "\033[31m%s\033[0m\n" "$*"; }
log(){ green "▶ $*"; }
warn(){ yellow "▲ $*"; }
die(){ red "✖ $*"; exit 1; }
[ -d "/data/data/com.termux/files/usr" ] || die "Termux environment not detected."
log "Updating Termux packages…"
yes | pkg update -y >/dev/null 2>&1 || true
yes | pkg upgrade -y >/dev/null 2>&1 || true
yes | pkg install -y python openssl-tool git curl tar coreutils clang libxml2 libxslt >/dev/null 2>&1
#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# venv check
if [ ! -d ".venv" ]; then   echo "[heal] virtualenv missing — creating...";   python -m venv .venv; fi
source .venv/bin/activate
# deps check
missing=0
python -c "import fastapi,uvicorn,requests,yaml,jinja2,feedparser,bs4" 2>/dev/null || missing=1
if [ $missing -eq 1 ]; then   echo "[heal] reinstalling Python deps...";   pip install -r requirements.txt; fi
#!/data/data/com.termux/files/usr/bin/bash
set -e
# --- Settings ---
PROJECT_DIR="$HOME/crypto-localengine"
BACKUP_DIR="$PROJECT_DIR/backup"
VENV_DIR="$PROJECT_DIR/.venv"
SITE_PATH="$PROJECT_DIR/site"
MAIN_FILE="$PROJECT_DIR/main.py"
echo "[INFO] 🚀 Self‑Heal Restore & Run starting..."
# 1️⃣ প্রজেক্ট ডিরেক্টরি চেক
if [ ! -d "$PROJECT_DIR" ]; then     echo "[ERROR] ❌ Project folder not found at $PROJECT_DIR";     exit 1; fi
cd "$PROJECT_DIR"
# 2️⃣ venv চেক + অ্যাক্টিভেট
if [ -d "$VENV_DIR" ]; then     source "$VENV_DIR/bin/activate"; else     echo "[WARN] ⚠️ venv missing — creating fresh environment...";     python3 -m venv "$VENV_DIR";     source "$VENV_DIR/bin/activate";     pip install --upgrade pip;     [ -f requirements.txt ] && pip install -r requirements.txt; fi
# 3️⃣ PYTHONPATH ঠিক করা
export PYTHONPATH=$PYTHONPATH:"$PROJECT_DIR"
# 4️⃣ site/dashboard চেক + রিস্টোর
if [ ! -d "$SITE_PATH" ] || ! ls "$SITE_PATH"/dashboard* &>/dev/null; then     echo "[WARN] ⚠️ site/dashboard missing — attempting restore...";     if [ -d "$BACKUP_DIR/site" ]; then         cp -r "$BACKUP_DIR/site" "$PROJECT_DIR/";         echo "[OK] ✅ site restored from backup.";     else         echo "[ERROR] ❌ No backup found for site/. Cannot continue.";         exit 1;     fi; else     echo "[OK] 🗂 site/dashboard found."; fi
Successfully built pydantic-core
Successfully installed pydantic-core-2.33.2
cd ~/crypto-localengine
source .venv/bin/activate
./scripts/run_dashboard.sh
cd ~/crypto-localengine
./scripts/selfhealinstall.sh
cd ~/crypto-localengine
ls scripts
git pull origin main
git remote -v
https://github.com/yourusername/crypto-localengine.git
git init
git remote add origin https://github.com/yourusername/crypto-localengine.git
git pull origin main
cd ~/crypto-localengine
ls site
cd ~/crypto-localengine
nano restore_and_run.sh
chmod +x restore_and_run.sh
./restore_and_run.sh
cd ~/crypto-localengine
./scripts/self_heal_install.sh
`bash
cd ~/crypto-localengine
./scripts/selfhealinstall.sh
`
./scripts/run_dashboard.sh
pip install python-telegram-bot==13.15 python-binance
