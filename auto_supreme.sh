#!/data/data/com.termux/files/usr/bin/bash
set -e

# === Load Binance keys if present ===
[ -f "$BINANCE_ENV" ] && source "$BINANCE_ENV" || true

log() { echo -e "[$(date '+%F %T')] $*"; }
ok() { log "✅ $*"; }
warn() { log "⚠️ $*"; }

# === GitHub SSH key check ===
if [ ! -f "$HOME/.ssh/id_ed25519" ]; then
  log "Generating SSH key..."
  ssh-keygen -t ed25519 -C "your_email@example.com" -f "$HOME/.ssh/id_ed25519" -N ""
  eval "$(ssh-agent -s)"
  ssh-add "$HOME/.ssh/id_ed25519"
  ok "SSH key generated — add this to GitHub:"
  cat "$HOME/.ssh/id_ed25519.pub"
else
  eval "$(ssh-agent -s)"
  ssh-add "$HOME/.ssh/id_ed25519"
  ok "SSH key loaded"
fi

# === Clone or update repo ===
REPO_DIR="$HOME/Supreme-hax"
if [ ! -d "$REPO_DIR/.git" ]; then
  git clone git@github.com:YourUser/Supreme-hax.git "$REPO_DIR"
else
  cd "$REPO_DIR"
  git reset --hard
  git pull --rebase
fi
ok "GitHub repo synced"

# === Binance connectivity check ===
if curl -s -H "X-MBX-APIKEY: ${BINANCE_API_KEY:-}" "https://api.binance.com/api/v3/ping" | grep -q "{}"; then
  ok "Binance API connectivity OK"
else
  warn "Binance API ping failed"
fi

# === Backup & restore logic ===
BACKUP_DIR="$HOME/.supreme_backups"
mkdir -p "$BACKUP_DIR"
tar -czf "$BACKUP_DIR/backup_$(date +%F).tar.gz" -C "$REPO_DIR" .
ok "Backup created"

# === Auto-heal example ===
if [ ! -f "$REPO_DIR/config/main.conf" ]; then
  warn "Main config missing — restoring from latest backup"
  LATEST_BACKUP=$(ls -t "$BACKUP_DIR"/*.tar.gz | head -n 1)
  tar -xzf "$LATEST_BACKUP" -C "$REPO_DIR"
  ok "Restore complete"
fi

ok "ALL DONE — GitHub + Binance configured, Supreme-hax healed, backups done."
