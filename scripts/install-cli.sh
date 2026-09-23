#!/usr/bin/env bash
# Make sure a provider CLI (hcloud or doctl) is installed, recent, and on PATH.
# Runs on the USER'S machine: macOS, Linux, or Windows (Git Bash, which Claude
# Code on Windows uses for its Bash tool). No admin/sudo needed.
#
#   install-cli.sh hcloud            # install or update if missing/outdated
#   install-cli.sh doctl --check     # report only, change nothing
#
# What it does:
#   1. Finds an existing binary (on PATH, or in this script's install dir even
#      if the current shell's PATH is stale) and reads its version.
#   2. Looks up the latest release on GitHub. "Outdated" = an older major.minor
#      than the latest (patch releases alone don't trigger an update).
#   3. If missing/outdated: updates via the package manager that owns the
#      existing copy (Homebrew, Scoop), else `brew install` on macOS when brew
#      exists, else downloads the official release from GitHub, verifies its
#      SHA-256 against the release's checksum file, and installs it to:
#        Windows:       %LOCALAPPDATA%\Programs\<tool>\<tool>.exe
#        macOS / Linux: ~/.local/bin/<tool>
#   4. Adds that folder to the user's PATH permanently (Windows user PATH via
#      the registry; ~/.bashrc / ~/.zshrc / ~/.profile elsewhere).
#
# The LAST line of output is always machine-readable:
#   CLI_PATH=<absolute path to the binary>   (or CLI_PATH= if unavailable)
# Programs that were already running (including the current Claude session)
# keep their old PATH, so call the binary by that absolute path, or prepend its
# folder to PATH, until the user opens a new terminal.
#
# Exit codes: 0 ready (or --check: up to date), 1 error,
#             3 --check: missing, 4 --check: outdated.
set -euo pipefail

TOOL="${1:-}"
CHECK_ONLY=0
[[ "${2:-}" == "--check" ]] && CHECK_ONLY=1

case "$TOOL" in
  hcloud) REPO="hetznercloud/cli" ;;
  doctl)  REPO="digitalocean/doctl" ;;
  *) echo "Usage: install-cli.sh hcloud|doctl [--check]" >&2; exit 2 ;;
esac

log()  { echo "[$TOOL] $*"; }
warn() { echo "[$TOOL] WARNING: $*" >&2; }
die()  { echo "[$TOOL] ERROR: $*" >&2; echo "CLI_PATH="; exit 1; }

# --- platform --------------------------------------------------------------
case "$(uname -s)" in
  Linux*)  OS=linux ;;
  Darwin*) OS=darwin ;;
  MINGW*|MSYS*|CYGWIN*) OS=windows ;;
  *) die "unsupported OS '$(uname -s)'. Install manually — see references/." ;;
esac

if [[ "$OS" == windows ]]; then
  # Git Bash is an x64 program, so uname -m says x86_64 even on ARM Windows.
  case "${PROCESSOR_ARCHITEW6432:-${PROCESSOR_ARCHITECTURE:-AMD64}}" in
    ARM64) ARCH=arm64 ;;
    *)     ARCH=amd64 ;;
  esac
else
  case "$(uname -m)" in
    x86_64|amd64)  ARCH=amd64 ;;
    aarch64|arm64) ARCH=arm64 ;;
    *) die "unsupported CPU '$(uname -m)'. Install manually — see references/." ;;
  esac
fi

if [[ "$OS" == windows ]]; then
  command -v cygpath >/dev/null 2>&1 || die "cygpath not found; run this from Git Bash."
  [[ -n "${LOCALAPPDATA:-}" ]] || die "LOCALAPPDATA is not set."
  INSTALL_DIR="$(cygpath -u "$LOCALAPPDATA")/Programs/$TOOL"
  BIN_NAME="$TOOL.exe"
else
  INSTALL_DIR="$HOME/.local/bin"
  BIN_NAME="$TOOL"
fi
OUR_BIN="$INSTALL_DIR/$BIN_NAME"

# --- helpers -----------------------------------------------------------------
version_of() {   # prints x.y.z, or nothing if unparseable (e.g. a "dev" build)
  "$1" version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1 || true
}

older_minor() {  # true if $1 has an older major.minor than $2
  local a1 a2 b1 b2
  IFS=. read -r a1 a2 _ <<<"$1"
  IFS=. read -r b1 b2 _ <<<"$2"
  (( a1 < b1 || (a1 == b1 && a2 < b2) ))
}

latest_version() {  # follows github.com/<repo>/releases/latest (no API rate limit)
  curl -fsSLI -o /dev/null -w '%{url_effective}' \
    "https://github.com/$REPO/releases/latest" 2>/dev/null \
    | grep -oE '[0-9]+\.[0-9]+\.[0-9]+$' || true
}

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  else shasum -a 256 "$1" | awk '{print $1}'; fi
}

path_has() { [[ ":$PATH:" == *":$1:"* ]]; }

# --- 1. what is installed? -------------------------------------------------
CUR_BIN="$(command -v "$TOOL" 2>/dev/null || true)"
if [[ -z "$CUR_BIN" && -x "$OUR_BIN" ]]; then
  CUR_BIN="$OUR_BIN"   # installed earlier, but this shell's PATH predates it
fi
CUR_VER=""
[[ -n "$CUR_BIN" ]] && CUR_VER="$(version_of "$CUR_BIN")"

# --- 2. what is current? -----------------------------------------------------
LATEST="$(latest_version)"

if [[ -n "$CUR_BIN" ]]; then
  log "found $CUR_BIN (version ${CUR_VER:-unknown})"
  if [[ -z "$LATEST" ]]; then
    warn "couldn't reach GitHub to check for updates; using the installed copy."
    echo "CLI_PATH=$CUR_BIN"; exit 0
  fi
  if [[ -z "$CUR_VER" ]]; then
    warn "can't read its version (custom build?); leaving it alone."
    echo "CLI_PATH=$CUR_BIN"; exit 0
  fi
  if ! older_minor "$CUR_VER" "$LATEST"; then
    log "up to date (latest is $LATEST)."
    echo "CLI_PATH=$CUR_BIN"; exit 0
  fi
  log "outdated: $CUR_VER installed, $LATEST is current."
  [[ "$CHECK_ONLY" -eq 1 ]] && { echo "CLI_PATH=$CUR_BIN"; exit 4; }
else
  log "not installed."
  [[ "$CHECK_ONLY" -eq 1 ]] && { echo "CLI_PATH="; exit 3; }
  [[ -n "$LATEST" ]] || die "can't reach github.com to download $TOOL. Check the internet connection."
fi

# --- 3a. let an owning package manager do it -------------------------------
if [[ -n "$CUR_BIN" && "$OS" != windows ]] && command -v brew >/dev/null 2>&1 \
   && [[ "$CUR_BIN" == "$(brew --prefix)"/* ]]; then
  log "updating with Homebrew ..."
  brew upgrade "$TOOL" || true
  NEW="$(command -v "$TOOL")"
  log "now $(version_of "$NEW")"
  echo "CLI_PATH=$NEW"; exit 0
fi
if [[ -n "$CUR_BIN" && "$OS" == windows && "$CUR_BIN" == */scoop/* ]] \
   && command -v scoop >/dev/null 2>&1; then
  log "updating with Scoop ..."
  scoop update "$TOOL" || true
  log "now $(version_of "$CUR_BIN")"
  echo "CLI_PATH=$CUR_BIN"; exit 0
fi
if [[ -z "$CUR_BIN" && "$OS" == darwin ]] && command -v brew >/dev/null 2>&1; then
  log "installing with Homebrew ..."
  if brew install "$TOOL"; then
    NEW="$(command -v "$TOOL")"
    log "installed $(version_of "$NEW")"
    echo "CLI_PATH=$NEW"; exit 0
  fi
  warn "brew install failed; falling back to the GitHub release."
fi

# --- 3b. download the official release and verify it -------------------------
EXT="tar.gz"; [[ "$OS" == windows ]] && EXT="zip"
if [[ "$TOOL" == hcloud ]]; then
  ASSET="hcloud-${OS}-${ARCH}.${EXT}"
  SUMS="checksums.txt"
else
  ASSET="doctl-${LATEST}-${OS}-${ARCH}.${EXT}"
  SUMS="doctl-${LATEST}-checksums.sha256"
fi
BASE="https://github.com/$REPO/releases/download/v${LATEST}"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

log "downloading $ASSET (v$LATEST) from github.com/$REPO ..."
curl -fsSL -o "$TMP/$ASSET" "$BASE/$ASSET" || die "download failed: $BASE/$ASSET"
curl -fsSL -o "$TMP/sums"   "$BASE/$SUMS"  || die "download failed: $BASE/$SUMS"

WANT="$(awk -v f="$ASSET" '$2==f || $2=="*"f {print $1}' "$TMP/sums")"
GOT="$(sha256_of "$TMP/$ASSET")"
[[ -n "$WANT" ]] || die "$ASSET is not listed in $SUMS; not installing."
[[ "$WANT" == "$GOT" ]] || die "checksum mismatch for $ASSET; not installing."
log "checksum OK."

mkdir -p "$TMP/x" "$INSTALL_DIR"
if [[ "$EXT" == zip ]]; then
  if command -v unzip >/dev/null 2>&1; then
    unzip -q -o "$TMP/$ASSET" -d "$TMP/x"
  else
    powershell.exe -NoProfile -Command \
      "Expand-Archive -Force -LiteralPath '$(cygpath -w "$TMP/$ASSET")' -DestinationPath '$(cygpath -w "$TMP/x")'"
  fi
else
  tar -xzf "$TMP/$ASSET" -C "$TMP/x"
fi
FOUND="$(find "$TMP/x" -type f -name "$BIN_NAME" | head -n1)"
[[ -n "$FOUND" ]] || die "$BIN_NAME not found inside $ASSET."
cp -f "$FOUND" "$OUR_BIN"
chmod +x "$OUR_BIN"
[[ "$OS" == darwin ]] && xattr -d com.apple.quarantine "$OUR_BIN" 2>/dev/null || true

NEW_VER="$(version_of "$OUR_BIN")"
[[ -n "$NEW_VER" ]] || die "installed $OUR_BIN but it doesn't run."
log "installed $OUR_BIN (version $NEW_VER)."

# --- 4. make it stick on PATH ------------------------------------------------
if [[ "$OS" == windows ]]; then
  WIN_DIR="$(cygpath -w "$INSTALL_DIR")"
  # Prepend to the *user* PATH (no admin needed). Edit the registry directly so
  # %VAR% entries and the REG_EXPAND_SZ type survive, then set+clear a dummy
  # variable so Windows broadcasts the change and new terminals pick it up.
  WIN_DIR="$WIN_DIR" powershell.exe -NoProfile -Command '
    $d = $env:WIN_DIR
    $k = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey("Environment", $true)
    $p = $k.GetValue("Path", "", "DoNotExpandEnvironmentNames")
    $parts = @($p -split ";" | Where-Object { $_ -and ($_.TrimEnd("\") -ne $d.TrimEnd("\")) })
    $k.SetValue("Path", ((@($d) + $parts) -join ";"), "ExpandString")
    $k.Close()
    [Environment]::SetEnvironmentVariable("CC_VPS_PATH_REFRESH", "1", "User")
    [Environment]::SetEnvironmentVariable("CC_VPS_PATH_REFRESH", $null, "User")
  ' && log "added $WIN_DIR to your user PATH (new terminals will see it)."
else
  LINE="export PATH=\"$INSTALL_DIR:\$PATH\"  # added by cc-remote-on-vps install-cli.sh"
  RCS=("$HOME/.profile" "$HOME/.bashrc")
  [[ "$OS" == darwin || -f "$HOME/.zshrc" ]] && RCS+=("$HOME/.zshrc")
  for rc in "${RCS[@]}"; do
    touch "$rc"
    grep -qF "cc-remote-on-vps install-cli.sh" "$rc" || printf '\n%s\n' "$LINE" >> "$rc"
  done
  log "made sure $INSTALL_DIR is on PATH in ${RCS[*]}."
fi

# An older copy elsewhere may still win the PATH race (e.g. Windows puts the
# system PATH before the user PATH). Say so rather than silently shadowing.
if [[ -n "$CUR_BIN" && "$CUR_BIN" != "$OUR_BIN" ]]; then
  warn "an older $TOOL is also at $CUR_BIN and may come first on PATH."
  warn "Remove or update that copy (it came from another installer) to avoid confusion."
fi
path_has "$INSTALL_DIR" || log "this shell's PATH predates the install; use the full path below until you open a new terminal."

echo "CLI_PATH=$OUR_BIN"
