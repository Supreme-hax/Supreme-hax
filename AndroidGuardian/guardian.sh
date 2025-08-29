#!/data/data/com.termux/files/usr/bin/bash
# AndroidGuardian – v2.1
# Self‑healing, self‑documenting, Wi‑Fi + Device Audit Script (Root‑Aware)
# Author: Ah's AI Copilot
# -----------------------------------------------------------

set -e
ROOT_DIR="$HOME/AndroidGuardian"
REPORT_DIR="$ROOT_DIR/reports/$(date '+%Y-%m-%d_%H-%M-%S')"
README="$REPORT_DIR/README.md"

# === Permission & Dependency Check ===
termux-setup-storage
pkg update -y && pkg install -y net-tools iproute2 grep util-linux procps tsu

mkdir -p "$REPORT_DIR"

# === Wi-Fi Audit (Root‑Aware) ===
WIFI_INFO="$REPORT_DIR/wifi_info.txt"
{
    echo "=== Wi-Fi INFO ($(date)) ==="
    ip addr show wlan0 2>/dev/null || echo "No wlan0 interface found."
    echo
    if command -v tsu >/dev/null 2>&1 && tsu -c true 2>/dev/null; then
        # Root mode
        tsu -c "netstat -rn" || echo "[!] Could not run netstat as root."
    else
        # Non-root fallback
        ip route show 2>/dev/null || echo "[!] Route info not available."
    fi
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
- **wifi_info.txt** — Wi-Fi interface, IP, and routing info (root/non‑root compatible)
- **device_info.txt** — Kernel, uptime, storage usage

## How to read:
\`\`\`bash
cat wifi_info.txt
cat device_info.txt
\`\`\`
EOM

echo "✅ Audit complete. Reports saved in: $REPORT_DIR"
echo "📄 README.md generated with usage guide."
