#!/usr/bin/env bash
# Create a Hetzner Cloud server with hcloud and wait until SSH is reachable.
# Prints the public IPv4 as the final line and writes it to ./.server-ip.
# The DigitalOcean sibling is scripts/provision-digitalocean.sh.
set -euo pipefail

NAME=""
LOCATION=""
TYPE="cx23"
IMAGE="ubuntu-24.04"
SSH_KEY="${HOME}/.ssh/id_ed25519.pub"
EXTRA=""

usage() {
  cat >&2 <<'EOF'
Usage: provision-hetzner.sh --name NAME --location SLUG [options]

  --name NAME        Server name (required)
  --location SLUG    Location slug, e.g. nbg1 fsn1 hel1 ash hil sin (required)
  --type SLUG        Server type slug (default: cx23). `hcloud server-type list`
                     for current options — Hetzner revises the lineup.
  --image SLUG       Image name (default: ubuntu-24.04)
  --ssh-key PATH     Public key file (default: ~/.ssh/id_ed25519.pub)
  --extra "ARGS"     Extra args passed verbatim to `hcloud server create`
                     (e.g. "--user-data-from-file cloud-init.yml", "--network mynet")
EOF
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)     NAME="$2"; shift 2 ;;
    --location) LOCATION="$2"; shift 2 ;;
    --type)     TYPE="$2"; shift 2 ;;
    --image)    IMAGE="$2"; shift 2 ;;
    --ssh-key)  SSH_KEY="$2"; shift 2 ;;
    --extra)    EXTRA="$2"; shift 2 ;;
    -h|--help)  usage ;;
    *) echo "Unknown argument: $1" >&2; usage ;;
  esac
done

[[ -n "$NAME"     ]] || { echo "ERROR: --name is required" >&2; usage; }
[[ -n "$LOCATION" ]] || { echo "ERROR: --location is required" >&2; usage; }

# install-cli.sh may have just installed hcloud; the calling shell's PATH can
# predate that, so also look in the folders it installs to.
if ! command -v hcloud >/dev/null 2>&1; then
  for d in "$HOME/.local/bin" "$(cygpath -u "${LOCALAPPDATA:-}" 2>/dev/null)/Programs/hcloud"; do
    if [[ -x "$d/hcloud" || -x "$d/hcloud.exe" ]]; then PATH="$d:$PATH"; break; fi
  done
fi
command -v hcloud >/dev/null 2>&1 || {
  echo "ERROR: hcloud not found. Install it with: scripts/install-cli.sh hcloud" >&2
  echo "       then run 'hcloud context create <name>'." >&2
  exit 1
}
hcloud server list >/dev/null 2>&1 || {
  echo "ERROR: hcloud is not authenticated. Run 'hcloud context create <name>'" >&2
  echo "       (or set HCLOUD_TOKEN). See references/hetzner.md." >&2
  exit 1
}
[[ -f "$SSH_KEY" ]] || {
  echo "ERROR: SSH public key not found at $SSH_KEY" >&2
  echo "Generate one with: ssh-keygen -t ed25519" >&2
  exit 1
}

# --- Ensure the public key is registered with Hetzner -----------------------
# `hcloud server create --ssh-key` takes a NAME or ID (not a fingerprint), so
# match the local key's MD5 fingerprint against the registered keys to find its
# name; register it (named "<server>-<date>") only if it isn't there yet.
FP="$(ssh-keygen -lf "$SSH_KEY" | awk '{print $2}' | sed 's/^SHA256://')"
KEY_FP_MD5="$(ssh-keygen -E md5 -lf "$SSH_KEY" | awk '{print $2}' | sed 's/^MD5://')"

KEY_NAME="$(hcloud ssh-key list -o columns=fingerprint,name -o noheader 2>/dev/null \
  | awk -v fp="$KEY_FP_MD5" '$1==fp {$1=""; sub(/^[ \t]+/,""); print; exit}')"

if [[ -n "$KEY_NAME" ]]; then
  echo "SSH key already registered with Hetzner as '$KEY_NAME' ($KEY_FP_MD5)."
else
  KEY_NAME="${NAME}-$(date +%Y%m%d)"
  echo "Registering SSH key with Hetzner as '$KEY_NAME' ..."
  hcloud ssh-key create --name "$KEY_NAME" --public-key-from-file "$SSH_KEY" >/dev/null
fi
echo "Using SSH key '$KEY_NAME' (md5 $KEY_FP_MD5, sha256 $FP)"

# --- Create the server -----------------------------------------------------
echo "Creating server '$NAME' ($TYPE, $IMAGE) in $LOCATION ..."
# hcloud server create waits for the create + start actions before returning.
# shellcheck disable=SC2086
hcloud server create \
  --name "$NAME" \
  --location "$LOCATION" \
  --type "$TYPE" \
  --image "$IMAGE" \
  --ssh-key "$KEY_NAME" \
  $EXTRA

SERVER_ID="$(hcloud server list -o columns=id,name -o noheader | awk -v n="$NAME" '$2==n {print $1}' | head -n1)"
IP="$(hcloud server ip "$NAME" 2>/dev/null | tr -d '[:space:]')"

if [[ -z "$IP" || -z "$SERVER_ID" ]]; then
  echo "ERROR: could not determine server ID/IP after create." >&2
  echo "Check 'hcloud server list' and 'hcloud server describe $NAME'." >&2
  exit 1
fi
echo "Server created. ID=$SERVER_ID  IP=$IP"

# --- Wait for SSH --------------------------------------------------------
echo -n "Waiting for SSH on $IP:22 "
for i in $(seq 1 60); do
  if (exec 3<>"/dev/tcp/$IP/22") 2>/dev/null; then
    exec 3>&- 3<&-
    echo " up."
    echo "$IP" > ./.server-ip
    echo "Wrote IP to ./.server-ip"
    echo "--- server ready ---"
    echo "$IP"
    exit 0
  fi
  echo -n "."
  sleep 3
done

echo >&2
echo "ERROR: SSH did not come up within ~3 minutes." >&2
echo "The server exists (ID=$SERVER_ID). Investigate, or delete it with:" >&2
echo "  hcloud server delete $NAME" >&2
exit 1
