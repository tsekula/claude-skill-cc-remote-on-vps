#!/usr/bin/env bash
# Run ON the droplet as the sudo user (not root).
# Installs Node 22 + Claude Code, installs a TEMPLATED systemd --user unit for
# Remote Control, and sets up the FIRST server instance.
#
# Each Remote Control server serves one directory under ~/projects and appears
# as one named session in claude.ai/code and the Claude mobile Code tab. This
# script does the first one; add more later with add-rc-server.sh.
#
# It does NOT log you in — `claude` login is interactive (browser + paste a
# code). Run this, then follow the printed steps.
#
# Assumes a Debian-family image (matches the digitalocean-droplet skill default).
set -euo pipefail

SESSION_NAME="sandbox"
INSTALL_SERVICE=0

usage() {
  cat >&2 <<EOF
Usage: setup-claude-code.sh --name NAME [--service]

  --name NAME   Name of the first Remote Control server. Becomes the directory
                ~/projects/NAME and the session name shown in claude.ai/code
                and the mobile Code tab. Pick something meaningful for what
                you'll do there (e.g. "sandbox" for throwaway work, or a repo
                name). [a-z0-9-] only. Default: sandbox
  --service     Install + enable the systemd --user unit (survives reboot).
                Without it you get tmux-only instructions.
EOF
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)    SESSION_NAME="$2"; shift 2 ;;
    --service) INSTALL_SERVICE=1; shift ;;
    -h|--help) usage ;;
    *) echo "Unknown argument: $1" >&2; usage ;;
  esac
done

[[ $EUID -ne 0 ]] || { echo "ERROR: run as your normal sudo user, not root." >&2; exit 1; }
[[ "$SESSION_NAME" =~ ^[a-z0-9-]+$ ]] \
  || { echo "ERROR: --name must be [a-z0-9-] (got '$SESSION_NAME')" >&2; exit 1; }

PROJECT_DIR="$HOME/projects/$SESSION_NAME"

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

# --- 2. tmux + git + Claude Code -------------------------------------------
pkgs=()
command -v tmux >/dev/null 2>&1 || pkgs+=(tmux)
command -v git  >/dev/null 2>&1 || pkgs+=(git)
if [[ ${#pkgs[@]} -gt 0 ]]; then
  sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${pkgs[@]}"
fi
echo "Installing Claude Code ..."
sudo /usr/local/bin/npm install -g @anthropic-ai/claude-code >/dev/null
hash -r
echo "Claude Code $(claude --version)"

# --- 3. first project directory ------------------------------------------
mkdir -p "$PROJECT_DIR"
echo "First Remote Control directory: $PROJECT_DIR"

# --- 4. templated systemd --user unit ----------------------------------
if [[ "$INSTALL_SERVICE" -eq 1 ]]; then
  echo "Installing templated systemd --user unit 'claude-rc@' ..."
  mkdir -p "$HOME/.config/systemd/user"
  # Templated unit: %i is BOTH the served directory (~/projects/%i) and the
  # Remote Control session name. Enable one per directory:
  #   systemctl --user enable --now claude-rc@sandbox
  cat > "$HOME/.config/systemd/user/claude-rc@.service" <<'EOF'
[Unit]
Description=Claude Code Remote Control (%i)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=%h/projects/%i
Environment=PATH=/usr/local/bin:/usr/bin:/bin
Environment=TERM=dumb
Environment=NO_COLOR=1
ExecStart=/usr/local/bin/claude remote-control --name %i
Restart=on-failure
RestartSec=10
# The live status line redraws once a second; discard it. Recover the session
# URL from claude.ai/code, or `claude remote-control --continue` in the dir.
StandardOutput=null
StandardError=journal

[Install]
WantedBy=default.target
EOF
  # linger lets user services run with no active login (i.e. after reboot)
  sudo loginctl enable-linger "$USER"
  systemctl --user daemon-reload
fi

# --- 5. next steps -----------------------------------------------------
cat <<EOF

Next steps (interactive — do these yourself in this SSH session):

  1. Log in and trust the directory:
       cd "$PROJECT_DIR" && claude
         - choose "Claude account with subscription"
         - open the printed URL in a browser signed in to your Claude (Pro/Max)
           account, approve, paste the code back
         - accept the workspace trust dialog
         - /exit
EOF

if [[ "$INSTALL_SERVICE" -eq 1 ]]; then
  cat <<EOF
  2. Start the first server:
       systemctl --user enable --now claude-rc@$SESSION_NAME
       systemctl --user status claude-rc@$SESSION_NAME --no-pager
     It shows up as "$SESSION_NAME" at claude.ai/code and in the mobile Code tab.
     If it doesn't connect:
       journalctl --user -u claude-rc@$SESSION_NAME -n 20 --no-pager

  Manage:  systemctl --user {restart,stop,disable} claude-rc@$SESSION_NAME
  Add more: ./add-rc-server.sh --name <other> [--repo <git-url>]
EOF
else
  cat <<EOF
  2. Start the first server in tmux:
       tmux new -s $SESSION_NAME
       cd "$PROJECT_DIR" && claude remote-control --name "$SESSION_NAME"
         - Ctrl-b then d to detach; keeps running after logout
         - reattach: tmux attach -t $SESSION_NAME
     Re-run with --service to make it survive reboot and get the claude-rc@ unit.
EOF
fi
