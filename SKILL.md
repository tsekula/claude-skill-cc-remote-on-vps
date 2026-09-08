---
name: cc-remote-on-vps
description: >-
  Stand up a Linux VPS on DigitalOcean (doctl) or Hetzner Cloud (hcloud) that
  runs Claude Code with Remote Control, so it can be driven from claude.ai/code
  or the Claude mobile app. Provisions the server, hardens it for SSH (non-root
  sudo user, key-only auth, optional custom port, UFW firewall), then installs
  Claude Code + a Remote Control systemd service by default (skippable for a
  plain box). Use this whenever the user wants to spin up, create, set up, or
  bootstrap a VPS, cloud server, droplet, or "a box on DO / Hetzner" — to run
  Claude Code on, to control Claude from their phone, or just as a hardened
  server — even if they only say "I need a new server" and name a provider or
  its CLI, and even without spelling out the steps. Also use it when the user
  has an existing fresh server IP to secure for SSH, when they want to add
  another Remote Control session to a box, or to delete a server this skill
  created and clean up after it (see Step 8).
---

# Claude Code Remote Control on VPS

This skill takes a user from "I want a new server" to "I can `ssh` in as a
non-root user, with passwords disabled and a firewall up, and drive Claude Code
on it from my phone." It supports two providers — **DigitalOcean** (`doctl`) and
**Hetzner Cloud** (`hcloud`) — and neither is the default: pick one in Step 1.
It creates the server with that provider's CLI, runs a hardening pass over SSH,
then sets up Claude Code + Remote Control (Step 6, skippable).

Provider-specific details (CLI install/auth, regions, sizes, prices, teardown
commands) live in `references/digitalocean.md` and `references/hetzner.md`. The
steps below are the provider-neutral flow.

Scripts:

- `scripts/provision-digitalocean.sh` / `scripts/provision-hetzner.sh` — create
  the server and wait until SSH answers.
- `scripts/harden.sh` — runs **on the server** to create the sudo user,
  configure `sshd`, and enable UFW.
- `scripts/setup-claude-code.sh` — runs **on the server** to install Claude
  Code + the first Remote Control server (Step 6, done by default).
  `scripts/add-rc-server.sh` adds more.

## When to run which part

- **Fresh start** (no server yet): Steps 1–7 — preflight (incl. picking the
  provider), choose location/size, provision, harden, verify, set up Claude Code
  + Remote Control (Step 6, unless the user opts out), summarise + record to
  memory.
- **User already made a server** in the web console and gives you an IP: skip to
  Step 4 (hardening), then verify, Step 6, summarise. No provider CLI needed.
- **Just set up Remote Control** on a box that's already hardened: do Step 6 on
  its own (`references/remote-control.md`).
- **Add another Remote Control server** to a box that's already a Claude Code
  box (a repo in its own session, another sandbox): jump to the "Add another
  Remote Control server" subsection after Step 7.
- **Tearing a server down:** jump to Step 8 — delete it and clean up, including
  the memory entry.

## Step 1 — Preflight

Confirm the tools and inputs before touching anything, because a half-created
server still costs money and a botched `sshd` config can lock everyone out.

1. **Pick the provider.** This skill has **no default provider.** Infer it
   *only* from an explicit signal in the user's message — the words
   "DigitalOcean" / "Hetzner", a CLI name (`doctl` / `hcloud`), or a
   region/type slug (`nyc3`, `fra1` → DigitalOcean; `nbg1`, `cx23` → Hetzner).
   A bare "let's go", "set one up", or the slash command alone is **not** a
   signal — if there is no signal, **stop and ask "DigitalOcean or Hetzner?"**
   before running anything. Do not assume one, and do not invent a reason
   (e.g. the command you were invoked with) for choosing.
   Everything provider-specific from here (CLI, auth, regions, sizes, teardown)
   is in **`references/digitalocean.md`** or **`references/hetzner.md`** — use
   the one for the chosen provider; call it `<provider ref>` below.
2. **CLI installed?** DigitalOcean: `doctl version`. Hetzner: `hcloud version`.
   If missing, open `<provider ref>` §1 and give the user the install steps
   **for their OS** (Homebrew, a Linux package/tarball, Windows Scoop/WinGet,
   Docker, or build from source) — don't assume Ubuntu. Ask which platform they
   are on if it isn't obvious.
3. **CLI authenticated?** DigitalOcean: `doctl account get`. Hetzner:
   `hcloud server list`. If it errors, walk the user through `<provider ref>`
   §2–§4: create an API token in the provider's console and run
   `doctl auth init` / `hcloud context create <name>`. **Do not ask the user to
   paste the token to you**; the CLI prompts for it directly. Env-var
   alternatives for CI: `DIGITALOCEAN_ACCESS_TOKEN` / `HCLOUD_TOKEN`.
   - DigitalOcean only: if `doctl auth init` **fails with a 401 and never
     prompts for a new token**, it's re-validating a stale one — see
     `references/digitalocean.md` §5 (clear the `default` context; check for a
     `DIGITALOCEAN_ACCESS_TOKEN` / `DIGITALOCEAN_API_TOKEN` env var).
4. **SSH key.** See the dedicated section below — this is where a first-time
   user most often gets stuck, so handle it patiently and offer to generate a
   key for them.
5. **SSH port and username.** Ask for the login name of the new sudo user
   (e.g. `tom`). SSH port defaults to `22` — only change it if the user asks; a
   non-standard port cuts log noise but is not real security.
6. **Image.** Default `ubuntu-24-04-x64` (DigitalOcean) / `ubuntu-24.04`
   (Hetzner). Only deviate if the user asks; the hardening script assumes a
   Debian-family image.

Server name, location, and size are chosen interactively in Step 2.

### SSH keys, for a first-time user

Assume the user may have never heard of an SSH key, and may be on **macOS,
Windows, or Linux** — the commands differ. `references/ssh-keys.md` has the
ELI5 explanation and the exact commands per OS; give the user only the rows for
their platform. Don't lecture, and move on once they have a key.

The flow:

1. **Check for an existing key** (`references/ssh-keys.md` §1). If one exists,
   offer to reuse it *or* make a fresh one just for this server — a per-server
   key is tidier to revoke later, but reusing a personal key is fine. Let them
   choose.
2. **If none, offer to generate one** (§2) — `ssh-keygen -t ed25519 -f
   <path>/id_ed25519_<server-name> -N ""`, adjusting path syntax for the OS.
   Explain the flags in plain terms from the reference. If the user wants a
   passphrase, they must run it themselves so they can type it — note that and
   move on.
3. **Tell them which file is which** (§3): the private key never leaves the
   `.ssh` folder and should be backed up once to a password manager; the
   `.pub` is the harmless half that goes on the server. If the private key is
   lost, key access is recovered only via the provider's web console / rescue
   mode.

Record the chosen key path. You'll pass `--ssh-key <path>.pub` to the
provisioning script, and use the matching private key with `-i <path>` for
`ssh`/`scp` in Steps 4–5. Offer the `~/.ssh/config` host alias from §4 at the
end so the user never retypes any of this.

## Step 2 — Choose location & size (cost-first)

Do this as a short back-and-forth with the user. Don't silently pick a location
or size — the size is what they pay for, so put the cheap options in front of
them. The exact discovery commands, slugs, and live-price commands are
provider-specific: follow **`<provider ref>` → "Regions & sizes"** (DigitalOcean)
or **"Locations & server types"** (Hetzner). What stays the same:

### 2a. Location

List the provider's locations and present them by **full name** with the slug
in parentheses (`Frankfurt 1 (fra1)`, `Nuremberg (nbg1)`). Recommend the one
physically closest to where traffic originates. Note the pricing rule from the
reference: DigitalOcean is flat across regions; **Hetzner varies by location**
(US costs more). If the user already named a location, confirm and move on.

### 2b. Size — show live prices, then recommend for the workload

Pull the live price list per the reference (never quote prices from memory).
Show the cheapest options as a small table, then **recommend based on what the
server is for.** Ask what they'll run on it if it isn't already clear.

**Default to ~4 GB (or ~2 GB + `--swap 2G`)** — Step 6 sets up Claude Code +
Remote Control by default, and that needs the headroom. Only drop below that if
the user has already said they want a plain bastion / no Remote Control. Target
RAM by workload; the reference maps each target to that provider's slug:

| Intended use | Target | Notes |
|---|---|---|
| **Default — Claude Code + Remote Control (Step 6)** | **~4 GB, or ~2 GB + `--swap 2G` as a floor** | Node + Claude Code idles ~0.5–1 GB; add MCP/language servers, `npm install`, test suites and 1 GB OOMs mid-task. A 2nd vCPU keeps the agent responsive during builds. |
| Docker / databases / CI runner | ~4 GB+ | Containers and DB caches are memory-hungry |
| Small web app or API, single service, no Remote Control | ~1 GB | The common baseline for a plain service |
| Bastion / jump host, tiny static site — no Remote Control | ~512 MB (DO) / smallest offered | Idle footprint is tiny; any build step will OOM. Hetzner has no cheap sub-4 GB EU tier. |

If the user wants Remote Control (the default) but picks ~1 GB or smaller, flag
the risk once (installs and builds get OOM-killed), suggest sizing up or adding
swap, but respect their choice.

From the reference, mention: billing is hourly with the monthly figure as a
cap; **powering off does not stop billing** (Step 8 to actually stop it);
resizing up later needs a brief reboot and disk can only grow. Confirm the
final **name + location (full name) + size** before moving on.

## Step 3 — Provision

Run the provisioning script for the chosen provider with the confirmed values.
The exact invocation (flags, defaults, `--extra` passthrough) is in
**`<provider ref>` → "Provision"**:

```bash
# DigitalOcean
scripts/provision-digitalocean.sh --name web-01 --region fra1 \
  --size s-1vcpu-1gb --image ubuntu-24-04-x64 --ssh-key ~/.ssh/id_ed25519_web-01.pub

# Hetzner
scripts/provision-hetzner.sh --name web-01 --location nbg1 \
  --type cx23 --image ubuntu-24.04 --ssh-key ~/.ssh/id_ed25519_web-01.pub
```

Either script:

- Registers the public key with the provider if it isn't already (matches by
  key fingerprint, so re-runs don't duplicate).
- Creates the server and waits until it's active.
- Polls TCP 22 on the public IP until `sshd` responds (usually 15–40s).
- Prints the public IPv4 as the last line and writes it to `./.server-ip` for
  the next step.

If the script fails after the server was created, it prints the ID/name and the
`… delete` command so you don't leak a paid resource.

## Step 4 — Harden

Copy the hardening script to the server and run it as root. At this point root
key login still works because the provider installed the registered key for
root.

```bash
IP=$(cat ./.server-ip)
KEY=~/.ssh/id_ed25519_web-01          # the private key chosen in Step 1
scp -i "$KEY" scripts/harden.sh root@"$IP":/root/harden.sh
ssh -i "$KEY" root@"$IP" "bash /root/harden.sh --user tom --port 22 --swap 2G --pubkey \"$(cat "$KEY".pub)\""
```

`-i "$KEY"` tells `ssh`/`scp` which private key to use; skip it only if the key
has the default name (`~/.ssh/id_ed25519`). Pass `--swap` on servers under
4 GB RAM that will run build tooling or Claude Code (see Step 2b) — rule of
thumb is swap = RAM, so `--swap 1G` on a 1 GB box, `--swap 2G` on a 2 GB box.
Omit it on 4 GB+ or a pure bastion.

### Explain it to the user (ELI5)

Before or right after running the script, give the user this plain-language
version — a first-timer should understand what just changed and why:

> This server is about to be online 24/7 with Claude Code able to read, change,
> and run things on it, and you'll be able to steer it from your phone. So we
> lock it down first:
>
> - **You log in with a key, never a password.** A password can be guessed by
>   bots that scan the whole internet all day; a key can't. Password logins are
>   turned off completely.
> - **You don't log in as the "root" superuser.** You get a normal account that
>   can *become* root when needed. So a mistake — yours or Claude's — or a bad
>   dependency doesn't automatically have run-of-the-house.
> - **A firewall closes every door except the ones we use.** Only SSH (and the
>   two standard web ports, left open for later) can be reached from outside.
>   Remote Control doesn't need an open door at all — it dials out.
> - **A small safety valve (swap)** on smaller servers stops the system from
>   killing Claude mid-task when memory gets tight.
> - The SSH config is **checked before it's applied**, and your current
>   connection is never dropped, so there's no way to lock yourself out.
>
> Not done (ask if you want it later): brute-force jailing (`fail2ban`),
> automatic security updates, 2FA for SSH.

`harden.sh` does, in this order (order matters so you don't lock yourself out):

1. Creates the user with `adduser --disabled-password`, adds them to `sudo`,
   and drops a validated `/etc/sudoers.d/90-<user>-nopasswd` granting
   passwordless `sudo`. The account has no password (login is key-only), so a
   normal `sudo` prompt would be unanswerable — this is the same convention
   cloud-init uses for the default user on AWS/GCP/Azure. Since SSH password
   auth is off, anyone with the key already has full access, so it doesn't
   widen the attack surface. A user who later runs `sudo passwd <user>` and
   wants `sudo` to prompt can just delete that file.
2. Installs the public key into `~/newuser/.ssh/authorized_keys` with correct
   `700`/`600` permissions and ownership.
3. If `--swap` was given and no swap is active: creates `/swapfile`, enables
   it, persists it in `/etc/fstab`, and sets `vm.swappiness=10` so it's only
   used under real memory pressure.
4. Configures UFW **first**: default deny incoming, allow outgoing, allow the
   chosen SSH port, allow `80`/`443`, then `ufw --force enable`. Doing this
   before the `sshd` change means the firewall is already permitting the port
   you're about to move to.
5. Writes `/etc/ssh/sshd_config.d/99-hardening.conf` with
   `PermitRootLogin no`, `PasswordAuthentication no`,
   `PubkeyAuthentication yes`, `KbdInteractiveAuthentication no`, and `Port`
   only if it isn't 22.
6. Runs `sshd -t` to validate the config. If it fails, the script aborts
   **without** restarting `sshd`, so the working config stays live.
7. Restarts `ssh`. Existing connections (including yours) are not dropped.

## Step 5 — Verify before you trust it

This is the step people skip and regret. Keep the current root SSH session
**open**, and in a **separate terminal** confirm the new user works:

```bash
ssh -i "$KEY" -p <port> <user>@<ip> "sudo whoami && echo OK"
```

Expected output ends with `root` then `OK` (the `sudo whoami` returns `root`).

Only once that succeeds:

- Root login is already disabled by the config, so nothing more to do — but
  verify: `ssh -i "$KEY" root@<ip>` should now be refused.
- If SSH was moved off 22, remind the user their future commands need
  `-p <port>`, and any provider cloud firewall (if they added one) or local
  `ssh_config` needs updating too.

### Optional: save a shortcut so they never retype this

For a first-time user, offer to add the `~/.ssh/config` host alias from
`references/ssh-keys.md` §4 so future logins are just `ssh <server-name>`
(the reference notes the Windows path caveat).

## Step 6 — Set up Claude Code + Remote Control

By default the skill leaves the server ready to drive Claude Code from
`claude.ai/code` and the Claude mobile app. **Do this step** unless the user
opts out.

**Offer to skip only when** the user says they just want a plain hardened
server / bastion, **or** they have no Claude **Pro or Max** subscription (Remote
Control requires one — API keys don't work), **or** the server is under ~2 GB
RAM and they don't want swap. If they skip, note that in the summary and go to
Step 7. Otherwise:

Full walkthrough in `references/remote-control.md`; the short version
(provider-independent — Remote Control is outbound HTTPS only, no firewall
change):

1. **Sizing check.** Claude Code needs Node 22 and each Remote Control server
   idles ~150–300 MB on top. Step 2 already steers to a ~4 GB type (or a ~2 GB
   type + `--swap 2G` floor). If the server ended up smaller, say so and either
   resize or proceed with reduced headroom.
2. **Name the first RC server.** A Remote Control server serves **one
   directory** and appears as **one named session** in `claude.ai/code` and the
   mobile Code tab. Ask the user what to call this first one — it becomes
   `~/projects/<name>` and the session label, so it should mean something
   (`sandbox` for throwaway work, or a project/repo name). `[a-z0-9-]` only.
   They can add more later.
3. **Install.** Copy `scripts/setup-claude-code.sh` to the box, run it as the
   sudo user: `bash setup-claude-code.sh --name <first-rc-name> --service`. It
   installs Node 22 (from nodejs.org — apt only has 18), Claude Code, `tmux`,
   `git`; makes `~/projects/<name>`; and installs the templated
   `claude-rc@.service` unit + linger so RC servers survive reboot.
4. **Log in** (interactive — you can't do it for them, but you can relay). In
   an SSH session: `cd ~/projects/<name> && claude`, choose the subscription
   option. Claude Code prints an OAuth URL and waits for a pasted code. Give
   the URL to the user; they approve in a browser signed into their Claude
   (Pro/Max) account and paste back the `<code>#<state>` string; you feed it in
   (via `tmux send-keys` if driving a tmux session). Then accept the workspace
   trust dialog and `/exit`. Login is once per box; **trust is per directory**.
5. **Start it.** `systemctl --user enable --now claude-rc@<name>`, then
   `systemctl --user status claude-rc@<name>`. Without a TTY,
   `claude remote-control` skips its y/n gate and just connects.
6. **Hand off.** Print this block verbatim (filled in), and repeat it in the
   Step 7 summary:

   ```
   === REMOTE CONTROL READY ===
   Session name:  <name>       — appears under this name at claude.ai/code and in the Claude app's Code tab
   Launch URL:    https://claude.ai/code?environment=<env id>
   Add another:   ask this skill any time — "add a Remote Control server called <x>" — for a second, parallel session on the same box
   ```

   Also mention `/config` → push notifications. If more than one RC server was
   set up, list every name + Launch URL.

Record the RC server name(s) + Launch URL(s) in the memory entry in Step 7.

## Step 7 — Summary

First, print the **connection details block** below verbatim (filled in) as the
last thing in your reply. It exists so that this Claude session — or any tool —
can SSH into the server straight away without hunting through prose. Keep the
exact field names; they're what a caller greps for.

```
=== SSH CONNECTION DETAILS ===
SSH host:  <user>@<public-ipv4>
SSH port:  <port>                # 22 unless changed
SSH key:   <absolute path to the PRIVATE key, e.g. /home/<you>/.ssh/id_ed25519_<name>>
Connect:   ssh -i <private-key path> -p <port> <user>@<public-ipv4>
```

Use an **absolute** path for the key (expand `~`), and the private key file
(no `.pub`). If SSH is on 22 you may drop `-p 22` from the `Connect` line, but
still fill in the `SSH port:` field.

If a Remote Control server was set up in Step 6, also print its
`=== REMOTE CONTROL READY ===` block (from Step 6) — one per RC server —
including the **session name**, the **Launch URL**, and the "ask this skill for
another parallel session" line.

Then the human-readable recap:

- server name, **provider**, location (full name), size/type, image, server ID
- what was hardened: root SSH disabled, password auth disabled, passwordless
  `sudo` for `<user>`, UFW active with ports `<ssh>`, 80, 443 open; swapfile if
  `--swap` was used (give the Step 4 ELI5 version if the user is new to this)
- **Remote Control:** each RC server's name + Launch URL, and that the user can
  ask for more parallel sessions later — or "skipped" with the reason
- which key file is the private one to guard, and the reminder to back it up
- if the `~/.ssh/config` alias was added, note that `ssh <server-name>` now
  works too

### Record it to memory

If you have a persistent memory or notes facility, save the server's details
there now so a future session can connect without re-deriving anything. This is
"project"-type context: an ongoing resource, not a one-off fact.

Use a stable, predictable key — `server-<name>` (e.g. `server-cc-dev`) — so
the deprovision step (Step 8) can find and remove it. Store, at minimum:

- server name, **provider** (digitalocean / hetzner), provider **ID**, location,
  size/type, image
- public IPv4
- **SSH host** (`<user>@<ip>`), **SSH port**, absolute **path to the private
  key**
- the ready-to-run `ssh -i <key> -p <port> <user>@<ip>` command
- Remote Control: the RC server name(s) and `systemctl --user …
  claude-rc@<name>` commands, or a note that it was skipped
- creation date, and a one-line note that it was hardened by this skill

Keep it accurate: if the server is later resized, rebuilt, or its key changes,
update the same entry rather than adding a second one.

### Add another Remote Control server

Use this when the box is already a Claude Code box (Node + Claude Code + the
`claude-rc@` unit installed via `setup-claude-code.sh --service`) and the user
wants a **second** session — a repo in its own directory, or another sandbox.
Each RC server is one directory under `~/projects` and one named entry in
`claude.ai/code` and the mobile Code tab.

1. **Get onto the box.** Recover its SSH host / port / key from the
   `server-<name>` memory entry (Step 7). If there's no entry, ask the user
   for the connection details.
2. **Pick a name** with the user — becomes `~/projects/<name>` and the session
   label. `[a-z0-9-]` only. Default it to the repo name when cloning.
3. **Ensure the tooling is on the box.** `add-rc-server.sh` needs
   `~/.config/systemd/user/claude-rc@.service`, which `setup-claude-code.sh
   --service` writes. If the box was set up before the templated unit existed
   (its only unit is `claude-rc.service`), `scp` the current
   `scripts/setup-claude-code.sh` and `scripts/add-rc-server.sh` up and re-run
   `bash setup-claude-code.sh --name <first> --service` once — it's idempotent
   (skips already-installed Node/Claude Code) and just adds the template.
4. **Run it:**
   ```bash
   ./add-rc-server.sh --name <name> [--repo <git-url>]
   ```
   Omit `--repo` for an empty directory. For a **private** repo, the box needs
   GitHub auth first (`gh auth login` device flow, a deploy key, or a PAT) —
   walk the user through `references/remote-control.md` → "Private GitHub
   repositories"; it is not automated.
5. **Trust + enable** (the script prints these):
   ```bash
   cd ~/projects/<name> && claude      # accept trust, then /exit
   systemctl --user enable --now claude-rc@<name>
   ```
   Trust is per directory even though login is once per box. Driving the trust
   step over chat: run `claude` in a tmux session and `tmux send-keys` the
   Down+Enter to select "Yes, I trust this folder".
6. **Hand off.** Confirm it's `active` (`systemctl --user status
   claude-rc@<name>`), give the user the session URL, and note the new RC
   server in the box's memory entry.

Watch memory pressure: each RC server idles ~150–300 MB. Two or three on a 2 GB
box, more on 4 GB+. `systemctl --user stop claude-rc@<name>` frees one without
losing its state.

## Step 8 — Deleting the server later

When the user asks to tear a server down:

1. **Confirm** which server by name **and** ID/provider, and that they accept
   it's immediate and irreversible — the disk and everything on it is gone, no
   snapshot unless they made one. Note: **powering off does not stop billing** on
   either provider; deleting is the only way to stop charges.
2. **Delete it** with the provider's command (details + verify command in
   `<provider ref>` → "Teardown"):
   ```bash
   doctl compute droplet delete <id> --force      # DigitalOcean
   hcloud server delete <name>                     # Hetzner
   ```
   Then verify with `doctl compute droplet list` / `hcloud server list`.
3. **Clean up the traces** so nothing stale is left behind:
   - **Memory.** Remove the `server-<name>` entry you saved in Step 7 (or mark
     it destroyed with the date). A deleted server's connection details must not
     linger as if still live.
   - **Auto-imported SSH key.** If the provisioning script registered a one-off
     key named `<name>-<YYYYMMDD>`, remove it (`doctl compute ssh-key delete` /
     `hcloud ssh-key delete`; see `<provider ref>` → "Teardown"). **Never**
     delete the user's pre-existing personal keys.
   - **Known-hosts.** `ssh-keygen -R <ip>` (also
     `ssh-keygen -R "[<ip>]:<port>"` if a non-standard port was used).
   - **Local key pair.** If a per-server key was generated in Step 1 and isn't
     used anywhere else, offer to delete
     `~/.ssh/id_ed25519_<name>{,.pub}` — but ask first, don't assume.
   - Remove a leftover `./.server-ip` file if present.
   - **Hetzner only:** check `hcloud primary-ip list` for an orphaned Primary IP
     (bills ~€0.50/mo).
4. Confirm to the user what was deleted and what was cleaned up.

## Notes and edge cases

- **`harden.sh` re-runs** are safe: it skips user creation if the user exists
  and overwrites only its own `99-hardening.conf` drop-in.
- **UFW and Docker.** If the user plans to run Docker, warn them Docker
  publishes ports straight into iptables and bypasses UFW — that's out of scope
  here but worth a heads-up.
- **Provider-specific facts** — billing granularity, whether price varies by
  region, IPv4 surcharges, passthrough flags for the provisioning script
  (`--extra`), cheapest slugs, resize rules — live in `references/digitalocean.md`
  and `references/hetzner.md`, not here.
- **Both providers allow duplicate server names**; re-running a provisioning
  script with the same name makes a *second* server. List first if a re-run is
  possible.
