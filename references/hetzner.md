# Hetzner Cloud provider guide (`hcloud`)

Provider-specific half of the skill: how to install and authenticate `hcloud`,
pick a location and server type, run `provision-hetzner.sh`, and tear a server
down. The provider-neutral flow (hardening, verify, Remote Control) is in
`SKILL.md`. DigitalOcean's equivalent is `references/digitalocean.md`.

`hcloud` is Hetzner's official CLI. This skill needs it on `PATH` and
authenticated with a **project** API token that has **Read & Write** permission.

Official docs: https://github.com/hetznercloud/cli •
https://community.hetzner.com/tutorials/howto-hcloud-cli/

---

## 1. Install

Pick the row for the user's OS. After any method, verify with:

```bash
hcloud version
```

### macOS

```bash
brew install hcloud
```

Upgrade later with `brew upgrade hcloud`. (MacPorts: `sudo port install hcloud`.)

### Linux

**Homebrew on Linux:**

```bash
brew install hcloud
```

**Debian/Ubuntu — distro package** (often behind the latest release):

```bash
sudo apt install hcloud-cli
```

**Debian/Ubuntu — .deb from the release** (current version, ships completions):

```bash
cd /tmp
ARCH=$(dpkg --print-architecture)   # amd64 or arm64
VER=$(curl -fsSL https://api.github.com/repos/hetznercloud/cli/releases/latest | grep -o '"tag_name": *"v[^"]*"' | cut -d'"' -f4 | tr -d v)
curl -fsSLO "https://github.com/hetznercloud/cli/releases/download/v${VER}/hcloud-cli_${VER}_${ARCH}.deb"
sudo dpkg -i "hcloud-cli_${VER}_${ARCH}.deb"
```

**Any distro — tarball** (asset pattern `hcloud-<os>-<arch>.tar.gz`, os ∈
linux/darwin/windows/freebsd, arch ∈ amd64/arm64):

```bash
cd /tmp
ARCH=$(case "$(uname -m)" in x86_64) echo amd64;; aarch64|arm64) echo arm64;; *) echo amd64;; esac)
curl -fsSLO "https://github.com/hetznercloud/cli/releases/latest/download/hcloud-linux-${ARCH}.tar.gz"
sudo tar -C /usr/local/bin --no-same-owner -xzf "hcloud-linux-${ARCH}.tar.gz" hcloud
```

Fedora/RHEL: install the `hcloud-cli-<ver>-1.<arch>.rpm` from the same release
page with `sudo dnf install ./hcloud-cli-*.rpm`.

### Windows

```powershell
scoop install hcloud          # or:  winget install HetznerCloud.CLI
```

Both are community-maintained, not by Hetzner (there is no official Chocolatey
package). Manual: download `hcloud-windows-amd64.zip` from
https://github.com/hetznercloud/cli/releases/latest, extract `hcloud.exe`, add
its folder to `PATH`. WSL users: use the **Linux** instructions inside WSL.

### Docker (any platform, no install)

```bash
docker run --rm -e HCLOUD_TOKEN="<token>" hetznercloud/cli:latest server list
```

This skill's scripts call `hcloud` directly, so a Docker-only setup means
adapting the scripts. Prefer a real install.

### Build from source

Requires Go 1.22+:

```bash
go install github.com/hetznercloud/cli/cmd/hcloud@latest   # ~/go/bin/hcloud
```

(`hcloud version` will read `dev`; clone the repo and `make` for a stamped
build.)

---

## 2. Create an API token

1. Open https://console.hetzner.cloud/ and select the **Project** the server
   should live in. Tokens are **per-project** — a different project needs its
   own token (and its own `hcloud` context).
2. Left sidebar → **Security** → **API Tokens** tab → **Generate API Token**.
3. Name it (e.g. `hcloud-laptop`), choose **Read & Write**, generate.
4. Copy the token now — Hetzner shows it only once.

---

## 3. Authenticate

### Interactive (recommended)

```bash
hcloud context create my-project
```

It shows a hidden `Token:` prompt — paste the token, press Enter. Config is
stored at `~/.config/hcloud/cli.toml` (token in plaintext).

Manage contexts:

```bash
hcloud context list
hcloud context use my-project
hcloud context active
hcloud context delete my-project
```

Per-command override: `hcloud --context my-project server list`.

### Non-interactive (CI, containers, automation)

```bash
export HCLOUD_TOKEN="<token>"
```

`hcloud` uses it and ignores the active context (so `hcloud context active`
reporting "none" is normal in this mode). Fine for CI; for a shared workstation
a context is safer than an exported secret.

---

## 4. Verify

```bash
hcloud server list
```

Returns a table (empty is fine) on success; an auth error otherwise. If it
fails: the token is missing, wrong, revoked, or lacks Read & Write — or you
created it in a different project than you think.

---

## 5. Locations & server types (SKILL.md Step 2)

### Locations

```bash
hcloud location list
```

| Slug | City | Region |
|---|---|---|
| `nbg1` | Nuremberg | Germany |
| `fsn1` | Falkenstein | Germany |
| `hel1` | Helsinki | Finland |
| `ash` | Ashburn, VA | USA |
| `hil` | Hillsboro, OR | USA |
| `sin` | Singapore | Singapore |

Recommend the one closest to where traffic originates. **Unlike DigitalOcean,
Hetzner prices vary by location** (US locations cost more than EU) — confirm the
price for the chosen location in the next step.

### Server types — no price column in `list`

```bash
hcloud server-type list          # id, name, cores, cpu_type, arch, memory, disk
hcloud server-type describe cx22 -o json | grep -A3 price_monthly   # EUR, per location
```

`server-type list` has **no price**. Get price per location from
`server-type describe <type> -o json` (`.prices[].price_monthly.gross`, EUR incl.
VAT) or from https://www.hetzner.com/cloud.

Map SKILL.md Step 2's RAM target to a type (prices approximate, EUR/mo, ex-VAT,
**plus ~€0.50/mo for the IPv4** — verify live):

| Step 2 RAM target | Hetzner type | vCPU / RAM / disk | ~EUR/mo |
|---|---|---|---|
| ~1 GB (smallest AMD) | `cpx11` | 2 / 2 GB / 40 GB | ~5.49 |
| ~2 GB (Claude Code floor, + `--swap 2G`) | `cx22` | 2 / 4 GB / 40 GB | ~4.49 |
| ~4 GB (Claude Code comfortable / Docker) | `cx22` already has 4 GB; step up to `cpx21` / `cx32` for more cores | 3 / 4 GB / 80 GB | ~8–10 |
| Arm (cheapest cores-per-euro) | `cax11` | 2 / 4 GB / 40 GB (Ampere Arm) | ~5.99 |

Note Hetzner's entry x86 type `cx22` already gives 2 vCPU + 4 GB, so the
"Claude Code floor" and "comfortable" targets often land on the **same** type —
`cx22` is a good default. `cx11` (the old ~€3.79 model) has been retired.

### Images

```bash
hcloud image list --type system
```

Common names: **`ubuntu-24.04`** (skill default), `ubuntu-22.04`, `debian-12`,
`debian-13`, `rocky-9`, `alma-9`, `fedora-42`.

### Hetzner facts

- Billing is **hourly, rounded up to the next full hour**, capped at the monthly
  price. Traffic over the included quota bills in 100 MB blocks.
- **A Primary IPv4 costs ~€0.50/mo** and is billed while the IP resource exists,
  even detached. `provision-hetzner.sh` keeps IPv4 (SSH needs it); passing
  `--extra "--without-ipv4"` would break the skill's SSH flow.
- Powering a server **off does not stop billing** — *"you pay for a server …
  for as long as it exists, regardless of whether it is turned on or not."* Only
  `hcloud server delete` stops charges. For long pauses: snapshot, delete,
  recreate from the snapshot later (snapshots bill per GB/mo of compressed
  size).
- Resizing: `hcloud server change-type` — needs the server powered off; disk
  can grow, not shrink.

---

## 6. Provision (SKILL.md Step 3)

```bash
scripts/provision-hetzner.sh \
  --name web-01 \
  --location nbg1 \
  --type cx22 \
  --image ubuntu-24.04 \
  --ssh-key ~/.ssh/id_ed25519_web-01.pub   # the .pub chosen in Step 1
```

- `--type` default is `cx22`, `--image` default `ubuntu-24.04`.
- `--extra "…"` is passed verbatim to `hcloud server create` — e.g.
  `--extra "--user-data-from-file cloud-init.yml"`,
  `--extra "--network my-net"`, `--extra "--placement-group my-pg"`,
  `--extra "--firewall my-fw"`.
- It registers the key with Hetzner if absent (matched by MD5 fingerprint, so
  re-runs don't duplicate), creates the server (`hcloud server create` waits for
  the create+start actions), polls TCP 22, writes the IPv4 to `./.server-ip`,
  and on failure prints `hcloud server delete <name>`.
- Hetzner **allows duplicate server names** too — check `hcloud server list`
  before a possible re-run.

---

## 7. Teardown (SKILL.md Step 7)

```bash
hcloud server delete <name>          # accepts name or ID
hcloud server list                   # confirm it's gone
```

Then the cleanup common to both providers (see SKILL.md Step 7), plus the
Hetzner-specific one:

- **One-off SSH key.** If `provision-hetzner.sh` registered a key named
  `<name>-<YYYYMMDD>` on the project, remove it:
  ```bash
  hcloud ssh-key list
  hcloud ssh-key delete <name-or-id>
  ```
  Never delete the user's pre-existing personal keys.
- **Primary IP.** Deleting the server releases its auto-created Primary IPv4. If
  one was created standalone (`hcloud primary-ip list`), delete it too or it
  keeps billing ~€0.50/mo.
