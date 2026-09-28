#!/usr/bin/env bash
#
# setup.sh - Turn a minimal Debian install into a headless AdGuard Home DNS server.
#
# What it does:
#   1. Updates the system and installs prerequisites (sudo, curl, ca-certificates)
#   2. Optionally adds a user to the sudo group
#   3. Configures systemd-logind so closing the laptop lid does NOT suspend it
#   4. Installs AdGuard Home using the official installer
#
# Usage (must run as root; a fresh minimal Debian has no sudo yet):
#   su -
#   ./setup.sh --user yourusername
#
# Options:
#   --user NAME   Add NAME to the sudo group
#   -h, --help    Show this help
#
# The script is safe to re-run: each step checks whether it is already done.

set -euo pipefail

ADGUARD_DIR="/opt/AdGuardHome"
ADGUARD_INSTALLER_URL="https://raw.githubusercontent.com/AdguardTeam/AdGuardHome/master/scripts/install.sh"
LOGIND_DROPIN="/etc/systemd/logind.conf.d/10-headless-lid.conf"

TARGET_USER=""
TMP_INSTALLER=""

log()  { printf '\n\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mWARNING:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

cleanup() {
    [[ -n "$TMP_INSTALLER" && -f "$TMP_INSTALLER" ]] && rm -f "$TMP_INSTALLER"
}
trap cleanup EXIT

usage() {
    sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

# ---------- Argument parsing ----------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --user)
            [[ $# -ge 2 ]] || die "--user requires a username"
            TARGET_USER="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            die "Unknown option: $1 (try --help)"
            ;;
    esac
done

# ---------- Preflight checks ----------
[[ $EUID -eq 0 ]] || die "Run this script as root (use 'su -' first)."
command -v apt-get >/dev/null 2>&1 || die "apt-get not found. This script targets Debian/Ubuntu."

if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    case "${ID:-}" in
        debian|ubuntu) ;;
        *) warn "Untested distribution '${ID:-unknown}'. Continuing anyway." ;;
    esac
fi

if [[ -n "$TARGET_USER" ]] && ! id "$TARGET_USER" >/dev/null 2>&1; then
    die "User '$TARGET_USER' does not exist."
fi

# ---------- 1. System update and prerequisites ----------
log "Updating package lists and upgrading installed packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get upgrade -y

log "Installing prerequisites (sudo, curl, ca-certificates)"
apt-get install -y sudo curl ca-certificates

# ---------- 2. Sudo access for the target user ----------
if [[ -n "$TARGET_USER" ]]; then
    if id -nG "$TARGET_USER" | tr ' ' '\n' | grep -qx sudo; then
        log "User '$TARGET_USER' is already in the sudo group"
    else
        log "Adding '$TARGET_USER' to the sudo group"
        usermod -aG sudo "$TARGET_USER"
        warn "'$TARGET_USER' must log out and back in for sudo to take effect."
    fi
fi

# ---------- 3. Headless operation: ignore lid close ----------
log "Configuring systemd-logind to ignore lid-close events"
mkdir -p "$(dirname "$LOGIND_DROPIN")"
cat > "$LOGIND_DROPIN" <<'EOF'
[Login]
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
EOF

if ! systemctl restart systemd-logind; then
    warn "Could not restart systemd-logind. Reboot for the lid setting to apply."
fi

# ---------- 4. Install AdGuard Home ----------
if [[ -x "$ADGUARD_DIR/AdGuardHome" ]]; then
    log "AdGuard Home is already installed in $ADGUARD_DIR - skipping"
else
    # AdGuard Home needs port 53. Warn if something else already holds it.
    if command -v ss >/dev/null 2>&1 && ss -H -lntu 'sport = :53' 2>/dev/null | grep -q .; then
        warn "Something is already listening on port 53. AdGuard Home may fail to bind."
        warn "Check with: ss -lntup 'sport = :53'"
    fi

    log "Downloading the official AdGuard Home installer"
    TMP_INSTALLER="$(mktemp)"
    curl -fsSL "$ADGUARD_INSTALLER_URL" -o "$TMP_INSTALLER"

    log "Installing AdGuard Home"
    sh "$TMP_INSTALLER" -v
fi

# ---------- Summary ----------
SERVER_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
SERVER_IP="${SERVER_IP:-<server-ip>}"

cat <<EOF

------------------------------------------------------------
 Setup complete.

 Next steps:
   1. Open  http://${SERVER_IP}:3000  in a browser and finish the setup wizard
      (admin UI on port 80, DNS on port 53, create an admin account).
   2. In the dashboard: add blocklists and set an upstream DNS
      (for example Cloudflare or Quad9 over DNS-over-HTTPS).
   3. Give this machine a fixed address (DHCP reservation on the router)
      so ${SERVER_IP} never changes.
   4. Point your router's DHCP DNS at ${SERVER_IP}, or set it manually
      on a single device to test first.

 Manage the service:
   sudo ${ADGUARD_DIR}/AdGuardHome -s status|start|stop|restart
------------------------------------------------------------
EOF
