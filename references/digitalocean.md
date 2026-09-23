# DigitalOcean provider guide (`doctl`)

Provider-specific half of the skill: how to install and authenticate `doctl`,
pick a region and size, run `provision-digitalocean.sh`, and tear a droplet
down. The provider-neutral flow (hardening, verify, Remote Control) is in
`SKILL.md`. Hetzner's equivalent is `references/hetzner.md`.

`doctl` is DigitalOcean's official CLI. This skill needs it on `PATH` and
authenticated with an API token that has **read and write** scope.

Official docs: https://docs.digitalocean.com/reference/doctl/how-to/install/

---

## 1. Install

**Default: let the skill do it.** `bash scripts/install-cli.sh doctl` installs
or updates `doctl` on macOS, Linux, or Windows (Git Bash) without admin rights,
verifies the download's SHA-256 against the release's checksum file, and puts
it on PATH (SKILL.md Step 1). The manual options below are the fallback if
that script fails.

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

---

## 5. Troubleshooting auth

### `doctl auth init` keeps failing and never asks for a new token

Symptom:

```
Validating token... ✘
Error: Unable to use supplied token to access API: ... 401 ... Unable to authenticate you
```

...and re-running `doctl auth init` goes straight back to that error **without
prompting you to paste a token**. That's the key clue: `doctl` is re-validating
a token it *already has stored* (or one in the environment) instead of asking
for a new one. Regenerating the token in the DigitalOcean dashboard doesn't
help, because `doctl` never asks you for the new value.

There are two places a stale token hides. Check both.

**a) A saved auth context** (most common). `doctl` stores tokens in named
contexts in its config file; the first one is called `default`. If that
context holds a dead token, clear it and `auth init` will prompt fresh:

```bash
doctl auth list                      # lists contexts; "default" is the built-in one
doctl auth remove --context default  # -> "Context deleted successfully"
doctl auth init                       # now actually prompts for a token
doctl account get                     # confirm
```

(If you had extra contexts like `work`, remove whichever one is broken by
name.)

**b) An environment variable.** If `DIGITALOCEAN_ACCESS_TOKEN` or
`DIGITALOCEAN_API_TOKEN` is set, `doctl` uses it and **skips the prompt
entirely** — and it wins over the config file, so fixing the context won't help
until it's gone:

```bash
env | grep -i digitalocean
grep -rn DIGITALOCEAN ~/.bashrc ~/.zshrc ~/.profile ~/.bash_profile ~/.zprofile 2>/dev/null
unset DIGITALOCEAN_ACCESS_TOKEN DIGITALOCEAN_API_TOKEN
```

Also delete the `export` line from whichever shell rc file `grep` found, or it
returns in every new terminal. To force a one-off prompt without touching your
shell:

```bash
env -u DIGITALOCEAN_ACCESS_TOKEN -u DIGITALOCEAN_API_TOKEN doctl auth init
```

### The token really is bad

If it *does* prompt and still 401s, the token itself is the problem. Confirm
with a direct call (hidden prompt, so it stays out of shell history):

```bash
read -rsp 'token: ' TOK && echo && \
  curl -sS -o /dev/null -w '%{http_code}\n' \
  -H "Authorization: Bearer $TOK" https://api.digitalocean.com/v2/account && \
  unset TOK
```

- `200` — token is fine; the problem is a stored context or env var (above).
- `401` — regenerate the token. Make sure it's a **Personal Access Token**
  (`dop_v1_` + 64 hex chars), not a Spaces key, and that the paste wasn't
  truncated or padded with a trailing space.

---

## 6. Regions & sizes (SKILL.md Step 2)

### Regions

```bash
doctl compute region list --format Name,Slug,Available --no-header | grep -i '\btrue$'
```

Present regions by **full name** with the slug in parentheses —
`Frankfurt 1 (fra1)`. Group by continent (North America: New York, San
Francisco, Toronto, Atlanta, …; Europe: Amsterdam, London, Frankfurt;
Asia-Pacific: Singapore, Bangalore, Sydney). Recommend the one closest to where
traffic originates. **On DigitalOcean, price does not vary by region** — latency
is the only differentiator.

### Sizes — live prices, cheapest first

```bash
doctl compute size list \
  --format Slug,Memory,VCPUs,Disk,PriceMonthly,PriceHourly --no-header \
  | grep '^s-' | sort -k5 -n | head -n 8
```

Memory is MB, disk GB, price USD. The `-amd` / `-intel` suffixes are
dedicated-CPU variants (~$1–2 more) — recommend the plain `s-Nvcpu-Ngb` slug.

Map SKILL.md Step 2's RAM target to a slug:

| Step 2 RAM target | DigitalOcean slug | ~USD/mo |
|---|---|---|
| ~512 MB (bastion / tiny static site) | `s-1vcpu-512mb-10gb` | $4 |
| ~1 GB (small web app / API) | `s-1vcpu-1gb` | $6 |
| ~2 GB (Claude Code floor, + `--swap 2G`) | `s-1vcpu-2gb` | $12 |
| ~4 GB (Claude Code comfortable / Docker / CI) | `s-2vcpu-4gb` | $24 |

Prices drift — always show the live `size list` output, don't quote these.

### DigitalOcean facts

- Billing is hourly with the monthly figure as a cap; a short test costs a cent
  or two. Powering a droplet **off does not stop billing** — only destroying it
  does (Step 8).
- Resizing up later is possible but needs a brief reboot; disk can only grow,
  never shrink.
- Size availability varies slightly by region/account. If
  `provision-digitalocean.sh` fails with a size/region error, re-list for that
  region and pick another.
- DigitalOcean allows **duplicate droplet names** — re-running
  `provision-digitalocean.sh` with the same name makes a *second* droplet.
  `doctl compute droplet list` first if a re-run is possible.
- A DigitalOcean Cloud Firewall is optional and separate; the skill's host-level
  UFW is sufficient on its own.

---

## 7. Provision (SKILL.md Step 3)

```bash
scripts/provision-digitalocean.sh \
  --name web-01 \
  --region fra1 \
  --size s-2vcpu-4gb \
  --image ubuntu-24-04-x64 \
  --ssh-key ~/.ssh/id_ed25519_web-01.pub   # the .pub chosen in Step 1
```

- `--size` default is `s-2vcpu-4gb` (Step 2's ~4 GB Claude Code default), `--image` default `ubuntu-24-04-x64`.
- `--extra "…"` is passed verbatim to `doctl compute droplet create` — e.g.
  `--extra "--enable-ipv6 --enable-monitoring"` or `--extra "--vpc-uuid <id>"`.
- It registers the key with DigitalOcean if absent (matched by fingerprint, so
  re-runs don't duplicate), creates the droplet with `--wait`, polls TCP 22,
  writes the IPv4 to `./.server-ip`, and on failure prints the droplet ID plus
  `doctl compute droplet delete <id>`.

---

## 8. Teardown (SKILL.md Step 8)

```bash
doctl compute droplet delete <id> --force
doctl compute droplet list                       # confirm it's gone
```

Then the cleanup common to both providers (see SKILL.md Step 8), plus the
DigitalOcean-specific one:

- **One-off SSH key.** If `provision-digitalocean.sh` registered a key named
  `<name>-<YYYYMMDD>` on the account, remove it:
  ```bash
  doctl compute ssh-key list
  doctl compute ssh-key delete <id> --force
  ```
  Never delete the user's pre-existing personal keys.
