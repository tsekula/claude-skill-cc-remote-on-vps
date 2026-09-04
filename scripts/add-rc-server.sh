#!/usr/bin/env bash
# Run ON the droplet as the sudo user, AFTER setup-claude-code.sh.
# Adds another Remote Control server: its own directory under ~/projects, its
# own named session in claude.ai/code, its own systemd instance. Optionally
# clones a git repo into it first.
set -euo pipefail

NAME=""
REPO=""

usage() {
  cat >&2 <<EOF
Usage: add-rc-server.sh --name NAME [--repo GIT_URL]

  --name NAME     Directory ~/projects/NAME and session name. [a-z0-9-] only.
  --repo GIT_URL  Clone this repo into ~/projects/NAME first. For a PRIVATE
                  repo, set up auth on the droplet first — see
                  references/remote-control.md, "Private GitHub repositories".
EOF
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name) NAME="$2"; shift 2 ;;
    --repo) REPO="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown argument: $1" >&2; usage ;;
  esac
done

[[ $EUID -ne 0 ]] || { echo "ERROR: run as your normal sudo user, not root." >&2; exit 1; }
[[ -n "$NAME" ]] || { echo "ERROR: --name is required" >&2; usage; }
[[ "$NAME" =~ ^[a-z0-9-]+$ ]] \
  || { echo "ERROR: --name must be [a-z0-9-] (got '$NAME')" >&2; exit 1; }

UNIT="$HOME/.config/systemd/user/claude-rc@.service"
[[ -f "$UNIT" ]] || {
  echo "ERROR: $UNIT not found. Run setup-claude-code.sh --service first." >&2
  exit 1
}
command -v claude >/dev/null 2>&1 || {
  echo "ERROR: claude not on PATH. Run setup-claude-code.sh first." >&2
  exit 1
}

DIR="$HOME/projects/$NAME"
mkdir -p "$HOME/projects"

if [[ -n "$REPO" ]]; then
  if [[ -e "$DIR" ]]; then
    echo "$DIR already exists — skipping clone."
  else
    echo "Cloning $REPO -> $DIR"
    if ! git clone "$REPO" "$DIR"; then
      cat >&2 <<EOF

Clone failed. If this is a private repo you need auth on the droplet first.
See references/remote-control.md, "Private GitHub repositories" — the quickest
is: gh auth login (device flow), or add a deploy key, or use a PAT in the URL.
Then re-run this script.
EOF
      exit 1
    fi
  fi
else
  mkdir -p "$DIR"
fi

cat <<EOF

'$NAME' directory ready: $DIR

Finish interactively:

  1. cd "$DIR" && claude
       - accept the workspace trust dialog, then /exit
       (Remote Control refuses to start in an untrusted directory.)

  2. systemctl --user enable --now claude-rc@$NAME
     systemctl --user status claude-rc@$NAME --no-pager

It then appears as "$NAME" at claude.ai/code and in the mobile Code tab,
alongside your other Remote Control sessions.
EOF
