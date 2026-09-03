#!/usr/bin/env bash
# Run ON a fresh DigitalOcean droplet as root.
# Creates a sudo user, installs an SSH key for them, enables UFW,
# disables root login + password auth, and optionally adds a swapfile.
# Safe to re-run.
#
# Assumes a Debian-family image (Ubuntu 24.04 is the skill default): uses
# adduser and apt-get. For a non-Debian image, adjust the user-creation and
# ufw-install lines.
set -euo pipefail

USER_NAME=""
SSH_PORT="22"
PUBKEY=""
SWAP_SIZE=""

usage() {
  cat >&2 <<'EOF'
Usage: harden.sh --user NAME --pubkey "ssh-ed25519 AAAA... comment" [--port N] [--swap SIZE]

  --user NAME     Login name for the new sudo user (required)
  --pubkey STR    The full public key line to authorize (required)
  --port N        SSH port to run on (default: 22)
  --swap SIZE     Create a swapfile of this size if none exists, e.g. 2G, 512M.
                  Recommended on droplets under 4 GB RAM that run build tools
                  or Claude Code. Omit to skip swap entirely.
EOF
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user)   USER_NAME="$2"; shift 2 ;;
    --pubkey) PUBKEY="$2"; shift 2 ;;
    --port)   SSH_PORT="$2"; shift 2 ;;
    --swap)   SWAP_SIZE="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown argument: $1" >&2; usage ;;
  esac
done

[[ $EUID -eq 0 ]] || { echo "ERROR: run as root." >&2; exit 1; }
[[ -n "$USER_NAME" ]] || { echo "ERROR: --user is required" >&2; usage; }
[[ -n "$PUBKEY"    ]] || { echo "ERROR: --pubkey is required" >&2; usage; }
[[ "$SSH_PORT" =~ ^[0-9]+$ && "$SSH_PORT" -ge 1 && "$SSH_PORT" -le 65535 ]] \
  || { echo "ERROR: --port must be 1-65535" >&2; exit 1; }
[[ -z "$SWAP_SIZE" || "$SWAP_SIZE" =~ ^[0-9]+[MG]$ ]] \
  || { echo "ERROR: --swap must look like 2G or 512M" >&2; exit 1; }

export DEBIAN_FRONTEND=noninteractive

# --- 1. sudo user -----------------------------------------------------------
if id "$USER_NAME" >/dev/null 2>&1; then
  echo "User '$USER_NAME' already exists, skipping creation."
else
  echo "Creating user '$USER_NAME'..."
  adduser --disabled-password --gecos "" "$USER_NAME"
fi
usermod -aG sudo "$USER_NAME"

# The account has no password (login is key-only), so a normal `sudo` prompt
# would be unanswerable and lock the user out of root. Grant passwordless sudo
# via a validated drop-in - this is the same convention cloud-init uses for the
# default user on AWS/GCP/Azure images. With SSH password auth disabled, anyone
# with the key already has full access, so this doesn't widen the attack
# surface. If the user later sets a password (`sudo passwd <user>`) and wants
# `sudo` to ask for it, they can delete this file.
SUDOERS="/etc/sudoers.d/90-${USER_NAME}-nopasswd"
echo "${USER_NAME} ALL=(ALL) NOPASSWD:ALL" > "$SUDOERS"
chmod 440 "$SUDOERS"
if ! visudo -cf "$SUDOERS" >/dev/null; then
  echo "ERROR: generated sudoers file failed validation, removing it." >&2
  rm -f "$SUDOERS"
  exit 1
fi

# --- 2. authorized_keys -------------------------------------------------
HOME_DIR="$(getent passwd "$USER_NAME" | cut -d: -f6)"
install -d -m 700 -o "$USER_NAME" -g "$USER_NAME" "$HOME_DIR/.ssh"
AUTH="$HOME_DIR/.ssh/authorized_keys"
touch "$AUTH"
if ! grep -qxF "$PUBKEY" "$AUTH"; then
  printf '%s\n' "$PUBKEY" >> "$AUTH"
  echo "Added public key to $AUTH"
else
  echo "Public key already present in $AUTH"
fi
chmod 600 "$AUTH"
chown "$USER_NAME:$USER_NAME" "$AUTH"

# --- 2b. optional swapfile ------------------------------------------------
if [[ -n "$SWAP_SIZE" ]]; then
  if [[ -n "$(swapon --show --noheadings 2>/dev/null)" ]]; then
    echo "Swap already active, skipping swapfile creation."
  else
    echo "Creating ${SWAP_SIZE} swapfile at /swapfile ..."
    num="${SWAP_SIZE%[MG]}"
    unit="${SWAP_SIZE: -1}"
    if [[ "$unit" == "G" ]]; then mb=$(( num * 1024 )); else mb="$num"; fi
    if ! fallocate -l "${mb}M" /swapfile 2>/dev/null; then
      # fallocate can fail on some filesystems; fall back to dd
      dd if=/dev/zero of=/swapfile bs=1M count="$mb" status=none
    fi
    chmod 600 /swapfile
    mkswap /swapfile >/dev/null
    swapon /swapfile
    grep -qxF '/swapfile none swap sw 0 0' /etc/fstab \
      || echo '/swapfile none swap sw 0 0' >> /etc/fstab
    # Favour RAM but allow spillover; good default for build tooling.
    sysctl -qw vm.swappiness=10
    grep -qxF 'vm.swappiness=10' /etc/sysctl.conf \
      || echo 'vm.swappiness=10' >> /etc/sysctl.conf
    swapon --show
  fi
fi

# --- 3. UFW (before touching sshd, so the port is already open) -----------
echo "Configuring UFW..."
if ! command -v ufw >/dev/null 2>&1; then
  apt-get update -qq
  apt-get install -y -qq ufw
fi
ufw default deny incoming
ufw default allow outgoing
ufw allow "${SSH_PORT}/tcp" comment 'SSH'
ufw allow 80/tcp   comment 'HTTP'
ufw allow 443/tcp  comment 'HTTPS'
ufw --force enable
ufw status verbose

# --- 4. sshd hardening drop-in -------------------------------------------
DROPIN="/etc/ssh/sshd_config.d/99-hardening.conf"
echo "Writing $DROPIN ..."
{
  echo "# Managed by harden.sh - do not edit by hand"
  echo "PermitRootLogin no"
  echo "PasswordAuthentication no"
  echo "PubkeyAuthentication yes"
  echo "KbdInteractiveAuthentication no"
  echo "ChallengeResponseAuthentication no"
  if [[ "$SSH_PORT" != "22" ]]; then
    echo "Port $SSH_PORT"
  fi
} > "$DROPIN"
chmod 644 "$DROPIN"

# --- 5. validate before restart --------------------------------------------
if ! sshd -t; then
  echo "ERROR: sshd config test failed. Removing drop-in and leaving SSH untouched." >&2
  rm -f "$DROPIN"
  exit 1
fi

# --- 6. restart (does not drop existing sessions) ------------------------
systemctl restart ssh || systemctl restart sshd
echo
echo "=== hardening complete ==="
free -h | awk 'NR==1 || /Mem|Swap/'
echo "Test in a SEPARATE terminal, keeping this session open:"
if [[ "$SSH_PORT" == "22" ]]; then
  echo "  ssh $USER_NAME@<this-ip> 'sudo whoami && echo OK'"
else
  echo "  ssh -p $SSH_PORT $USER_NAME@<this-ip> 'sudo whoami && echo OK'"
fi
echo "Only close this session after that prints 'root' then 'OK'."
