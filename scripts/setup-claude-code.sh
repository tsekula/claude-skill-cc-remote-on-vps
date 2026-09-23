#!/usr/bin/env bash
# Run ON the server as the sudo user (not root).
# Installs Claude Code (native installer), installs a TEMPLATED systemd --user unit for
# Remote Control, and sets up the FIRST server instance.
#
# Each Remote Control server serves one directory under ~/projects and appears
# as one named session in claude.ai/code and the Claude mobile Code tab. This
# script does the first one; add more later with add-rc-server.sh.
#
# It does NOT log you in — `claude` login is interactive (browser + paste a
# code). Run this, then follow the printed steps.
#
# Assumes a Debian-family image (matches the skill default).
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

# --- 1. tmux + git ------------------------------------------------------
pkgs=()
command -v tmux >/dev/null 2>&1 || pkgs+=(tmux)
command -v git  >/dev/null 2>&1 || pkgs+=(git)
if [[ ${#pkgs[@]} -gt 0 ]]; then
  sudo DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=300 update -qq
  sudo DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=300 install -y -qq "${pkgs[@]}"
fi

# --- 2. Claude Code (native installer) -----------------------------------
# Anthropic's native build: a single self-updating binary under ~/.local, no
# Node.js needed. It must run as this user, never with sudo.
CLAUDE="$HOME/.local/bin/claude"
if [[ -x "$CLAUDE" ]]; then
  echo "Claude Code already installed (native): $("$CLAUDE" --version)"
else
  echo "Installing Claude Code (native installer) ..."
  curl -fsSL https://claude.ai/install.sh | bash
fi
[[ -x "$CLAUDE" ]] || { echo "ERROR: $CLAUDE missing after install." >&2; exit 1; }
export PATH="$HOME/.local/bin:$PATH"
hash -r

# Boxes set up by older versions of this script used a global npm install at
# /usr/local/bin/claude. Remove it so there's exactly one `claude`.
MIGRATED=0
if command -v npm >/dev/null 2>&1 \
   && npm ls -g --depth=0 @anthropic-ai/claude-code >/dev/null 2>&1; then
  echo "Removing the old npm-installed Claude Code ..."
  sudo npm uninstall -g @anthropic-ai/claude-code >/dev/null 2>&1 || true
  MIGRATED=1
fi
echo "Claude Code $("$CLAUDE" --version)"

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
Environment=PATH=%h/.local/bin:/usr/local/bin:/usr/bin:/bin
Environment=TERM=dumb
Environment=NO_COLOR=1
ExecStart=%h/.local/bin/claude remote-control --name %i
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
  # After a migration from npm, running servers still point at the removed
  # binary; restart them onto the native one.
  if [[ "$MIGRATED" -eq 1 ]]; then
    systemctl --user try-restart 'claude-rc@*' || true
  fi
fi

# --- 5. next steps -----------------------------------------------------
cat <<EOF

Next steps (interactive — do these yourself in this SSH session):

  1. Log in and trust the directory:
       cd "$PROJECT_DIR" && claude
         (if "claude: command not found", log out and back in once, or use
          ~/.local/bin/claude — the installer put it there)
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
