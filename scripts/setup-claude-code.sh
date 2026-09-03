#!/usr/bin/env bash
# Run ON the droplet as the sudo user (not root).
# Installs Node 22 + Claude Code, prepares a project directory, and optionally
# installs a systemd --user service that keeps `claude remote-control` running
# across logouts and reboots.
#
# It does NOT log you in — `claude` login is interactive (browser + paste a
# code). Run this, then follow the printed steps.
#
# Assumes a Debian-family image (matches the digitalocean-droplet skill default).
set -euo pipefail

PROJECT_DIR="$HOME/projects/scratch"
SESSION_NAME="$(hostname)"
INSTALL_SERVICE=0

usage() {
  cat >&2 <<EOF
Usage: setup-claude-code.sh [options]

  --project-dir PATH   Directory Remote Control serves (default: ~/projects/scratch)
  --name NAME          Remote Control session name (default: hostname, "$SESSION_NAME")
  --service            Also install + enable the systemd --user service and linger
EOF
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-dir) PROJECT_DIR="$2"; shift 2 ;;
    --name)        SESSION_NAME="$2"; shift 2 ;;
    --service)     INSTALL_SERVICE=1; shift ;;
    -h|--help)     usage ;;
    *) echo "Unknown argument: $1" >&2; usage ;;
  esac
done

[[ $EUID -ne 0 ]] || { echo "ERROR: run as your normal sudo user, not root." >&2; exit 1; }

# --- 1. Node 22 (Claude Code needs >=22; Ubuntu 24.04 apt only has 18) --------
need_node=1
if command -v node >/dev/null 2>&1; then
  major="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)"
  [[ "$major" -ge 22 ]] && need_node=0
fi

if [[ "$need_node" -eq 1 ]]; then
  echo "Installing Node 22 from nodejs.org ..."
  case "$(uname -m)" in
    x86_64)  narch=x64 ;;
    aarch64|arm64) narch=arm64 ;;
    *) echo "ERROR: unsupported arch $(uname -m)" >&2; exit 1 ;;
  esac
  tarball="$(curl -fsSL https://nodejs.org/dist/latest-v22.x/ \
    | grep -o "node-v22[0-9.]*-linux-${narch}.tar.xz" | head -1)"
  [[ -n "$tarball" ]] || { echo "ERROR: could not find a Node 22 tarball" >&2; exit 1; }
  curl -fsSL -o "/tmp/$tarball" "https://nodejs.org/dist/latest-v22.x/$tarball"
  sudo tar -xJf "/tmp/$tarball" -C /usr/local --strip-components=1
  rm -f "/tmp/$tarball"
  hash -r
fi
echo "node $(node --version), npm $(npm --version)"

# --- 2. tmux (handy for attaching) + Claude Code -----------------------------
if ! command -v tmux >/dev/null 2>&1; then
  sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq tmux
fi
echo "Installing Claude Code ..."
sudo /usr/local/bin/npm install -g @anthropic-ai/claude-code >/dev/null
hash -r
echo "Claude Code $(claude --version)"

# --- 3. project directory ---------------------------------------------------
mkdir -p "$PROJECT_DIR"
echo "Project directory: $PROJECT_DIR"

# --- 4. optional systemd --user service -----------------------------------
if [[ "$INSTALL_SERVICE" -eq 1 ]]; then
  echo "Installing systemd --user service 'claude-rc' ..."
  mkdir -p "$HOME/.config/systemd/user"
  unit="$HOME/.config/systemd/user/claude-rc.service"
  # Template lives next to this script when run from the skill; fall back to inline.
  tpl="$(dirname "$0")/../assets/claude-rc.service"
  if [[ -f "$tpl" ]]; then
    sed -e "s#__PROJECT_DIR__#${PROJECT_DIR}#g" \
        -e "s#__SESSION_NAME__#${SESSION_NAME}#g" "$tpl" > "$unit"
  else
    cat > "$unit" <<EOF
[Unit]
Description=Claude Code Remote Control (${SESSION_NAME})
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=${PROJECT_DIR}
Environment=PATH=/usr/local/bin:/usr/bin:/bin
Environment=TERM=dumb
Environment=NO_COLOR=1
ExecStart=/usr/local/bin/claude remote-control --name ${SESSION_NAME}
Restart=on-failure
RestartSec=10
StandardOutput=null
StandardError=journal

[Install]
WantedBy=default.target
EOF
  fi
  # linger lets the user service run with no active login (i.e. after reboot)
  sudo loginctl enable-linger "$USER"
  systemctl --user daemon-reload
  echo
  echo "Service installed but NOT started — you must log in first:"
else
  echo
fi

# --- 5. next steps --------------------------------------------------------
cat <<EOF

Next steps (interactive, do these yourself in this SSH session):

  1. cd "$PROJECT_DIR" && claude
       - pick "Claude account with subscription"
       - open the printed URL in a browser signed in to your Claude (Pro/Max)
         account, approve, paste the code back
       - accept the workspace trust dialog
       - /exit
EOF

if [[ "$INSTALL_SERVICE" -eq 1 ]]; then
  cat <<EOF
  2. systemctl --user enable --now claude-rc
     systemctl --user status claude-rc --no-pager
       - the session shows up as "$SESSION_NAME" at claude.ai/code and in the
         Claude mobile app's Code tab
  3. journalctl --user -u claude-rc -n 20 --no-pager   # if it doesn't connect

  Manage it: systemctl --user {restart,stop,disable} claude-rc
EOF
else
  cat <<EOF
  2. tmux new -s cc
     cd "$PROJECT_DIR" && claude remote-control --name "$SESSION_NAME"
       - Ctrl-b then d to detach; it keeps running after you log out
       - reattach later with: tmux attach -t cc
       - (re-run scripts/setup-claude-code.sh --service to make this survive reboot)
EOF
fi
