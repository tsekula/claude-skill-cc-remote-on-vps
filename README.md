# claude-droplet

A Claude Code skill that provisions a DigitalOcean droplet with `doctl` and
hardens it for SSH: non-root sudo user, key-only auth (optional custom port),
UFW firewall. It records the droplet's connection details to Claude's memory on
creation, and cleans that up (plus known-hosts, auto-imported keys) on
deletion. Optionally installs Claude Code on the droplet with a Remote Control
service so it can be driven from claude.ai/code or the Claude mobile app.

## Layout

- [`SKILL.md`](SKILL.md) — the skill Claude follows
- `references/doctl-setup.md` — install + auth `doctl` on macOS, Linux, Windows, Docker
- `references/ssh-keys.md` — ELI5 SSH keys + per-OS generate/store/backup steps
- `references/remote-control.md` — optional: run Claude Code on the droplet (one or more Remote Control servers), driven from claude.ai/mobile; private-repo auth
- `scripts/provision.sh` — create the droplet, wait for SSH, print the IP
- `scripts/harden.sh` — run on the droplet: sudo user, keys, swap, UFW, sshd lockdown
- `scripts/setup-claude-code.sh` — optional: install Node 22 + Claude Code + the templated `claude-rc@` service, set up the first server
- `scripts/add-rc-server.sh` — optional: add another Remote Control server (own directory / session), optionally cloning a repo

`setup-claude-code.sh` writes the templated `claude-rc@.service` systemd unit
directly (one instance per directory: `systemctl --user enable --now
claude-rc@<name>`).

## Install as a personal skill

```bash
mkdir -p ~/.claude/skills
ln -s "$(pwd)" ~/.claude/skills/digitalocean-droplet
```

Then in Claude Code: "spin up a new DigitalOcean droplet called web-01 in nyc3".

## Prerequisites

- `doctl` installed and authenticated — see
  [`references/doctl-setup.md`](references/doctl-setup.md) for per-platform
  install (Homebrew, snap, Scoop, tarball, Docker) and token/auth steps
- An SSH keypair (`~/.ssh/id_ed25519`)

## Install on macOS / Windows

The symlink command above is bash. Equivalents:

- **macOS:** same as Linux —
  `ln -s "$(pwd)" ~/.claude/skills/digitalocean-droplet`
- **Windows (PowerShell, as admin):**
  `New-Item -ItemType SymbolicLink -Path "$HOME\.claude\skills\digitalocean-droplet" -Target (Get-Location)`
- Or just copy the folder into `~/.claude/skills/` instead of symlinking.
