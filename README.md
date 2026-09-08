# Claude Code Remote Control on VPS

*(skill name `cc-remote-on-vps`; repo `claude-droplet`)*

A Claude Code skill that stands up a Linux VPS on **DigitalOcean** (`doctl`) or
**Hetzner Cloud** (`hcloud`) to run **Claude Code with Remote Control** — driven
from claude.ai/code or the Claude mobile app. It provisions the server, hardens
it for SSH (non-root sudo user, key-only auth, optional custom port, UFW
firewall), then **by default installs Claude Code + a Remote Control systemd
service** (Step 6, skippable for a plain box). Connection details go to Claude's
memory on creation and are cleaned up (with known-hosts + auto-imported keys) on
deletion.

Neither provider is the default — the skill asks in Step 1.

## What the hardening does, and why it matters here

A Remote Control box isn't a throwaway server. It runs a `claude` process
**24/7**, it can **read, write, and execute** anything in your project
directories, and it's steerable from a phone. So the baseline is: nothing on it
should be reachable or usable by anyone who isn't holding your SSH private key.
`scripts/harden.sh` runs once over SSH as root and does the following, in this
order (the order matters — the firewall goes up before `sshd` is touched, and
`sshd` is validated before it's restarted, so you can't lock yourself out):

| Step | What it does | Why it's good practice for a Remote Control VPS |
|---|---|---|
| **Non-root sudo user** | Creates a normal user, adds it to `sudo`, disables the `root` account for SSH. | Claude Code, the `claude-rc@` service, `npm install`, build tools — all run as an unprivileged user. A bad command or a compromised dependency isn't automatically root. `root` is also the one username every SSH scanner tries first; taking it off the table removes that entire class of attempt. |
| **Passwordless `sudo`** (validated `/etc/sudoers.d/` drop-in) | The sudo user can escalate without a password prompt. | The account is **key-only** and has *no* password, so a normal `sudo` prompt would be unanswerable and would lock the user out of root. Since SSH password auth is already off (below), anyone with the key already has full access — this doesn't widen the attack surface, it just makes the box usable. Same convention cloud-init uses for the default user on AWS/GCP/Azure. Delete the file if you later set a password and want the prompt back. |
| **Key-only SSH** | `sshd` drop-in sets `PasswordAuthentication no`, `KbdInteractiveAuthentication no`, `PubkeyAuthentication yes`, `PermitRootLogin no`. | SSH is the most-scanned service on the internet; password and keyboard-interactive auth are what brute-force and credential-stuffing bots hammer. With them off, there is nothing to guess — an attacker needs the actual private key file. This is the single highest-value change on the box. |
| **Optional custom SSH port** (`--port`) | Moves `sshd` off 22 if asked. | Cuts log noise from drive-by scanners. It is **not** a security boundary on its own — key-only auth is what protects you — so it's opt-in, not default. |
| **`sshd -t` before restart** | Config is syntax-checked; on failure the drop-in is removed and `sshd` is left running its old config. Existing connections are never dropped. | A typo in `sshd_config` that only bites on the next connection is how people lock themselves out of a remote box. This makes that impossible. |
| **UFW default-deny firewall** | `deny incoming`, `allow outgoing`, then explicitly allow the SSH port + `80` + `443`; enable. | Only SSH is actually exposed; 80/443 are pre-opened so a future web service on the box works without re-running anything. Remote Control itself needs **no inbound port** — it's outbound HTTPS to Anthropic only — so the firewall never interferes with it, it just closes everything else (databases, dev servers, debug ports) that a process might bind by accident. |
| **Swapfile** (`--swap`, on boxes < 4 GB) | Creates `/swapfile`, persists it in `/etc/fstab`, sets `vm.swappiness=10` (RAM first, spill only under real pressure). | Node + Claude Code idle around 0.5–1 GB; `npm install`, test suites, and compilers spike well above that. Without swap the kernel's OOM killer picks a process to kill mid-task — often the long-lived `claude remote-control` itself, which silently drops your session. Swap turns an OOM kill into a slowdown. |

### Deliberately out of scope

The skill stops at "safe to leave running with key-only SSH". It does **not**
install `fail2ban`, enable unattended security upgrades, set up 2FA/FIDO2 for
SSH, or apply SELinux/AppArmor profiles. Those are reasonable next steps for a
long-lived box but they're policy choices, not universal defaults — add them
yourself, or ask the skill and it can walk you through them.

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
ln -s "$(pwd)" ~/.claude/skills/cc-remote-on-vps
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
  `ln -s "$(pwd)" ~/.claude/skills/cc-remote-on-vps`
- **Windows (PowerShell, as admin):**
  `New-Item -ItemType SymbolicLink -Path "$HOME\.claude\skills\cc-remote-on-vps" -Target (Get-Location)`
- Or just copy the folder into `~/.claude/skills/` instead of symlinking.
