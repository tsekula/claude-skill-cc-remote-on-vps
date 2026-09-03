# Installing and authenticating `doctl`

`doctl` is DigitalOcean's official CLI. This skill needs it on `PATH` and
authenticated with an API token that has **read and write** scope.

Official docs: https://docs.digitalocean.com/reference/doctl/how-to/install/

---

## 1. Install

Pick the row for the user's OS. After any method, verify with:

```bash
doctl version
```

### macOS

**Homebrew (recommended):**

```bash
brew install doctl
```

Upgrade later with `brew upgrade doctl`.

**MacPorts:**

```bash
sudo port install doctl
```

**Manual (no package manager):**

```bash
cd /tmp
# Apple Silicon: use ...-darwin-arm64.tar.gz ; Intel: ...-darwin-amd64.tar.gz
ARCH=$( [ "$(uname -m)" = "arm64" ] && echo arm64 || echo amd64 )
VER=$(curl -fsSL https://api.github.com/repos/digitalocean/doctl/releases/latest | grep -o '"tag_name": *"v[^"]*"' | cut -d'"' -f4 | tr -d v)
curl -fsSL -o doctl.tar.gz "https://github.com/digitalocean/doctl/releases/download/v${VER}/doctl-${VER}-darwin-${ARCH}.tar.gz"
tar xf doctl.tar.gz
sudo mv doctl /usr/local/bin
```

If macOS Gatekeeper blocks it: `xattr -d com.apple.quarantine /usr/local/bin/doctl`.

### Linux

**Snap (Ubuntu and other snap-enabled distros):**

```bash
sudo snap install doctl
# Needed so doctl can read your SSH keys and write its config:
sudo snap connect doctl:ssh-keys :ssh-keys
```

**Homebrew on Linux:**

```bash
brew install doctl
```

**Manual (works on any distro, and gives the newest version):**

```bash
cd /tmp
ARCH=$(case "$(uname -m)" in x86_64) echo amd64;; aarch64|arm64) echo arm64;; *) echo amd64;; esac)
VER=$(curl -fsSL https://api.github.com/repos/digitalocean/doctl/releases/latest | grep -o '"tag_name": *"v[^"]*"' | cut -d'"' -f4 | tr -d v)
curl -fsSL -o doctl.tar.gz "https://github.com/digitalocean/doctl/releases/download/v${VER}/doctl-${VER}-linux-${ARCH}.tar.gz"
tar xf doctl.tar.gz
sudo mv doctl /usr/local/bin
```

Distro packages (`apt install doctl`, AUR, etc.) exist but are often several
versions behind — prefer snap, Homebrew, or the manual tarball.

### Windows

**Scoop (recommended):**

```powershell
scoop install doctl
```

**Chocolatey:**

```powershell
choco install doctl
```

**Manual:**

1. Download `doctl-<version>-windows-amd64.zip` from
   https://github.com/digitalocean/doctl/releases/latest
2. Extract `doctl.exe` to a folder, e.g. `C:\Program Files\doctl\`
3. Add that folder to your `PATH`
   (System Properties → Environment Variables), or for the current session:
   `$env:Path += ";C:\Program Files\doctl\"`

WSL users: follow the **Linux** instructions inside the WSL environment
instead.

### Docker (any platform, no install)

```bash
docker run --rm --interactive --tty \
  -e DIGITALOCEAN_ACCESS_TOKEN \
  digitalocean/doctl:latest account get
```

This skill's scripts call `doctl` directly, so a Docker-only setup means
adapting the scripts to shell out to the container. Prefer a real install.

### Build from source

Requires Go 1.22+:

```bash
git clone https://github.com/digitalocean/doctl.git
cd doctl
go build -o doctl ./cmd/doctl
sudo mv doctl /usr/local/bin   # or anywhere on PATH
```

---

## 2. Create an API token

1. Go to https://cloud.digitalocean.com/account/api/tokens
2. **Generate New Token**
3. Give it a name (e.g. `doctl-laptop`), pick an expiry, and grant **Write**
   scope (Write includes Read). For least privilege you can instead use
   **Custom Scopes** and enable at minimum: `droplet` read+create+delete,
   `ssh_key` read+create, `region` read, `image` read, `size` read.
4. Copy the token now — DigitalOcean shows it only once.

---

## 3. Authenticate

### Interactive (recommended)

```bash
doctl auth init
```

Paste the token at the prompt. It's stored in:

- Linux: `~/.config/doctl/config.yaml`
- macOS: `~/Library/Application Support/doctl/config.yaml`
- Windows: `%APPDATA%\doctl\config.yaml`
- snap: `~/snap/doctl/current/.config/doctl/config.yaml`

**Never pass the token on the command line** (`--access-token ...`) — it lands
in your shell history. `doctl auth init` prompts for it instead.

### Multiple accounts / contexts

```bash
doctl auth init --context personal
doctl auth init --context work
doctl auth list                 # show contexts
doctl auth switch --context work # change the default
```

Per-command: `doctl --context work compute droplet list`.

### Non-interactive (CI, containers, automation)

Set an environment variable instead of running `auth init`:

```bash
export DIGITALOCEAN_ACCESS_TOKEN="dop_v1_xxx"
```

`doctl` reads this automatically. Useful in CI, but for a shared workstation
`doctl auth init` is safer than an exported secret.

---

## 4. Verify

```bash
doctl account get
```

Success prints your account email, droplet limit, and status. Any error here
(401, "unable to initialize") means the token is missing, wrong, expired, or
lacks scope — fix that before running the skill.
