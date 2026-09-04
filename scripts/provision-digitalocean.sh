#!/usr/bin/env bash
# Create a DigitalOcean droplet with doctl and wait until SSH is reachable.
# Prints the public IPv4 as the final line and writes it to ./.server-ip.
# The Hetzner sibling is scripts/provision-hetzner.sh.
set -euo pipefail

NAME=""
REGION=""
SIZE="s-1vcpu-1gb"
IMAGE="ubuntu-24-04-x64"
SSH_KEY="${HOME}/.ssh/id_ed25519.pub"
EXTRA=""

usage() {
  cat >&2 <<'EOF'
Usage: provision-digitalocean.sh --name NAME --region SLUG [options]

  --name NAME        Droplet name (required)
  --region SLUG      Region slug, e.g. nyc3 (required)
  --size SLUG        Size slug (default: s-1vcpu-1gb)
  --image SLUG       Image slug (default: ubuntu-24-04-x64)
  --ssh-key PATH     Public key file (default: ~/.ssh/id_ed25519.pub)
  --extra "ARGS"     Extra args passed verbatim to `doctl compute droplet create`
EOF
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)    NAME="$2"; shift 2 ;;
    --region)  REGION="$2"; shift 2 ;;
    --size)    SIZE="$2"; shift 2 ;;
    --image)   IMAGE="$2"; shift 2 ;;
    --ssh-key) SSH_KEY="$2"; shift 2 ;;
    --extra)   EXTRA="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown argument: $1" >&2; usage ;;
  esac
done

[[ -n "$NAME"   ]] || { echo "ERROR: --name is required" >&2; usage; }
[[ -n "$REGION" ]] || { echo "ERROR: --region is required" >&2; usage; }

command -v doctl >/dev/null 2>&1 || {
  echo "ERROR: doctl not found. See references/digitalocean.md for install steps" >&2
  echo "       (macOS/Linux/Windows/Docker), then run 'doctl auth init'." >&2
  exit 1
}
doctl account get >/dev/null 2>&1 || {
  echo "ERROR: doctl is not authenticated. Run 'doctl auth init'" >&2
  echo "       (or set DIGITALOCEAN_ACCESS_TOKEN). See references/digitalocean.md." >&2
  exit 1
}
[[ -f "$SSH_KEY" ]] || {
  echo "ERROR: SSH public key not found at $SSH_KEY" >&2
  echo "Generate one with: ssh-keygen -t ed25519" >&2
  exit 1
}

# --- Ensure the public key is registered with DigitalOcean --------------------
# Match by fingerprint so repeated runs don't create duplicate key entries.
FP="$(ssh-keygen -lf "$SSH_KEY" | awk '{print $2}' | sed 's/^SHA256://')"
KEY_FP_MD5="$(ssh-keygen -E md5 -lf "$SSH_KEY" | awk '{print $2}' | sed 's/^MD5://')"

existing_fp="$(doctl compute ssh-key list --format FingerPrint --no-header 2>/dev/null || true)"
if grep -qx "$KEY_FP_MD5" <<<"$existing_fp"; then
  echo "SSH key already registered with DigitalOcean (fingerprint $KEY_FP_MD5)."
else
  echo "Registering SSH key with DigitalOcean..."
  doctl compute ssh-key import "${NAME}-$(date +%Y%m%d)" --public-key-file "$SSH_KEY" >/dev/null
fi
echo "Using SSH key fingerprint: $KEY_FP_MD5 (sha256: $FP)"

# --- Create the droplet ------------------------------------------------------
echo "Creating droplet '$NAME' ($SIZE, $IMAGE) in $REGION ..."
# shellcheck disable=SC2086
create_out="$(doctl compute droplet create "$NAME" \
  --region "$REGION" \
  --size "$SIZE" \
  --image "$IMAGE" \
  --ssh-keys "$KEY_FP_MD5" \
  --wait \
  --format ID,PublicIPv4 --no-header \
  $EXTRA)"

DROPLET_ID="$(awk '{print $1}' <<<"$create_out")"
IP="$(awk '{print $2}' <<<"$create_out")"

if [[ -z "$IP" || -z "$DROPLET_ID" ]]; then
  echo "ERROR: could not parse droplet ID/IP from doctl output:" >&2
  echo "$create_out" >&2
  exit 1
fi
echo "Droplet created. ID=$DROPLET_ID  IP=$IP"

# --- Wait for SSH ----------------------------------------------------------
echo -n "Waiting for SSH on $IP:22 "
for i in $(seq 1 60); do
  if (exec 3<>"/dev/tcp/$IP/22") 2>/dev/null; then
    exec 3>&- 3<&-
    echo " up."
    echo "$IP" > ./.server-ip
    echo "Wrote IP to ./.server-ip"
    echo "--- droplet ready ---"
    echo "$IP"
    exit 0
  fi
  echo -n "."
  sleep 3
done

echo >&2
echo "ERROR: SSH did not come up within ~3 minutes." >&2
echo "The droplet exists (ID=$DROPLET_ID). Investigate, or delete it with:" >&2
echo "  doctl compute droplet delete $DROPLET_ID" >&2
exit 1
