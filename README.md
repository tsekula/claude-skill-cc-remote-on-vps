# Remote Control on VPS

*(skill name `remote-on-vps`; repo `claude-droplet`)*

A Claude Code skill that stands up a Linux VPS on **DigitalOcean** (`doctl`) or
**Hetzner Cloud** (`hcloud`) to run **Claude Code with Remote Control** — driven
from claude.ai/code or the Claude mobile app. It provisions the server, hardens
it for SSH (non-root sudo user, key-only auth, optional custom port, UFW
firewall), then **by default installs Claude Code + a Remote Control systemd
service** (Step 6, skippable for a plain box). Connection details go to Claude's
memory on creation and are cleaned up (with known-hosts + auto-imported keys) on
deletion.

Neither provider is the default — the skill asks in Step 1.

## Layout

- [`SKILL.md`](SKILL.md) — the provider-neutral flow Claude follows
- `references/digitalocean.md` — `doctl` install + auth, regions/sizes, provision, teardown
- `references/hetzner.md` — `hcloud` install + auth, locations/types, provision, teardown
- `references/ssh-keys.md` — ELI5 SSH keys + per-OS generate/store/backup steps
- `references/remote-control.md` — run Claude Code on the server (one or more Remote Control servers), driven from claude.ai/mobile; private-repo auth
- `scripts/provision-digitalocean.sh` / `scripts/provision-hetzner.sh` — create the server, wait for SSH, print the IP (writes `./.server-ip`)
- `scripts/harden.sh` — run on the server: sudo user, keys, swap, UFW, sshd lockdown
- `scripts/setup-claude-code.sh` — Step 6 (default): install Node 22 + Claude Code + the templated `claude-rc@` service, set up the first Remote Control server
- `scripts/add-rc-server.sh` — add another Remote Control server (own directory / session), optionally cloning a repo

`setup-claude-code.sh` writes the templated `claude-rc@.service` systemd unit
directly (one instance per directory: `systemctl --user enable --now
claude-rc@<name>`).

## Install as a personal skill

```bash
mkdir -p ~/.claude/skills
ln -s "$(pwd)" ~/.claude/skills/remote-on-vps
```

Then in Claude Code: "spin up a new Hetzner server called web-01 in Nuremberg",
or "make me a DigitalOcean droplet in Frankfurt".

## Prerequisites

- **One** provider CLI installed and authenticated:
  - DigitalOcean: `doctl` — see [`references/digitalocean.md`](references/digitalocean.md)
  - Hetzner: `hcloud` — see [`references/hetzner.md`](references/hetzner.md)
- An SSH keypair (`~/.ssh/id_ed25519`, or one the skill generates per server)

## Install on macOS / Windows

The symlink command above is bash. Equivalents:

- **macOS:** same as Linux —
  `ln -s "$(pwd)" ~/.claude/skills/remote-on-vps`
- **Windows (PowerShell, as admin):**
  `New-Item -ItemType SymbolicLink -Path "$HOME\.claude\skills\remote-on-vps" -Target (Get-Location)`
- Or just copy the folder into `~/.claude/skills/` instead of symlinking.
