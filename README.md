# Claude Code Remote Control on VPS

*(skill name `cc-remote-on-vps`; repository `claude-skill-cc-remote-on-vps`)*

This is a guided helper for putting **Claude Code on a secure Linux VPS** so you
can keep working from your browser, desktop, or phone. It walks you through
choosing **DigitalOcean** or **Hetzner Cloud**, creates the server, locks down
SSH, installs Claude Code, and leaves you with a named Remote Control session
you can pick up anywhere. You do not need to understand servers to follow the
questions, but you will need an account with the cloud provider you choose.

> **A paid Claude plan is required.** Claude Code and Remote Control require a
> paid **Pro, Max, Team, or Enterprise** plan. A free Claude account or an API
> key by itself cannot use this Remote Control workflow. The cloud provider will
> also charge for the VPS while it exists.

## Quick start (for non-technical users)

### 1. Download the skill

Download the [latest `cc-remote-on-vps.skill` file](https://github.com/tsekula/claude-skill-cc-remote-on-vps/raw/refs/heads/master/cc-remote-on-vps.skill) and save it somewhere easy to find, such as your Downloads folder.

The `.skill` file is a ZIP-format package containing the skill and its helper
files. If an upload window only accepts `.zip`, make a copy and rename the copy
from `.skill` to `.zip`; do not unpack it before uploading.

### 2. Add it to Claude on the web

1. Open [claude.ai](https://claude.ai) and sign in with the paid Claude account
   you want to use for Claude Code.
2. Open **Settings → Capabilities** and make sure **Code execution and file
   creation** is enabled.
3. Open **Customize → Skills**, click **+**, choose **Create skill**, then
   choose **Upload a skill**.
4. Select the downloaded `.skill` file (or the renamed `.zip` copy), wait for
   it to finish uploading, and switch the skill on.

The skill is private to your account by default. Once it is enabled, start at
[`claude.ai/code`](https://claude.ai/code) and ask Claude to use it. Be explicit
about the provider, for example:

> Use the `cc-remote-on-vps` skill to set up a new DigitalOcean server for me.

The skill will ask for the server name, location, size, SSH key, and login name
before it creates anything. It never silently chooses between DigitalOcean and
Hetzner.

#### Copy-and-paste install prompt

If you would rather have Claude fetch the package for you, paste this into a
chat:

```text
Please download and install this custom Claude skill into my account:
https://github.com/tsekula/claude-skill-cc-remote-on-vps/raw/refs/heads/master/cc-remote-on-vps.skill

After you confirm that it is installed and enabled, tell me to start a new chat.
In that new chat I will run: /cc-remote-on-vps
```

After Claude confirms the installation, start a **new chat** and enter
`/cc-remote-on-vps`. That slash command starts the skill's guided workflow.

### 3. Use it in Claude Desktop

1. Download Claude Desktop from [claude.com/download](https://claude.com/download)
   and install the version for your computer.
2. Sign in with the **same paid Claude account** used on the web.
3. Open **Customize → Skills** and confirm that `cc-remote-on-vps` is enabled.
   Skills are tied to your Claude account, so uploading it on the web makes it
   available here too. If it is not visible, upload it once from Claude on the
   web using the steps above.
4. Open the **Code** area and start or continue the named Remote Control session.
   Claude Code in Desktop requires a paid Pro, Max, Team, or Enterprise plan.

Desktop is a good place to do the first server setup because the skill may need
you to approve a browser login or copy a one-time code. After that, you can use
Desktop as another window into the same VPS session.

### 4. Use it from the Claude mobile app

1. Install Claude for [iOS or Android](https://claude.com/download).
2. Sign in with the **same paid Claude account**.
3. Open the **Code** tab. Once the VPS setup is complete and its Remote Control
   service is running, your named session will appear there.
4. Tap the session to send tasks, review results, or continue work while away
   from your computer. Turn on push notifications from a Claude Code session via
   `/config` if you want to know when Claude needs you.

The mobile app is the remote control for the Claude Code process on the VPS; it
does not replace the one-time server setup. Start that setup from Claude on the
web or Desktop, then use mobile whenever it is convenient.

### 5. What to expect after setup

The skill leaves one named session for one project directory. The same session
appears at claude.ai/code, in Claude Desktop's Code area, and in the mobile
Code tab. You can ask the skill to add another session later for another repo
or sandbox.

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
