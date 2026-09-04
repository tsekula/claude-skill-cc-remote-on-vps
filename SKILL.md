---
name: digitalocean-droplet
description: >-
  Provision a new DigitalOcean droplet with doctl and lock it down for SSH
  access: a non-root sudo user, key-only authentication (optionally on a custom
  port), and a UFW firewall. Use this whenever the user wants to spin up,
  create, set up, or bootstrap a DigitalOcean droplet, VPS, cloud server, or
  "a box on DO" — even if they only say "I need a new server" and mention
  DigitalOcean, and even if they don't spell out the hardening steps. Also use
  it when the user has an existing fresh droplet IP and wants it secured for SSH.
  Also handles the reverse — deleting a droplet this skill created and cleaning
  up after it (see Step 7) — so use it when the user wants to tear one down too.
  Optionally sets the droplet up to run Claude Code with Remote Control, so it
  can be driven from claude.ai/code or the Claude mobile app.
---

# DigitalOcean droplet with basic SSH

This skill takes a user from "I want a new droplet" to "I can `ssh` in as a
non-root user, with passwords disabled and a firewall up." It uses `doctl` (the
official DigitalOcean CLI) to create the droplet and then runs a hardening pass
over SSH.

There are two scripts:

- `scripts/provision.sh` — creates the droplet and waits until SSH answers.
- `scripts/harden.sh` — runs **on the droplet** to create the sudo user,
  configure `sshd`, and enable UFW.
- `scripts/setup-claude-code.sh` — optional, runs **on the droplet** to install
  Claude Code + the first Remote Control server (see the optional section after
  Step 6). `scripts/add-rc-server.sh` adds more.

## When to run which part

- **Fresh start** (no droplet yet): Steps 1–6 — preflight, choose region/size,
  provision, harden, verify, summarise. Record the result to memory.
- **User already made a droplet** in the web console and gives you an IP:
  skip to Step 4 (hardening), then verify and summarise.
- **Make it a Claude Code box:** after Step 6, do the optional Remote Control
  section (`references/remote-control.md`).
- **Tearing a droplet down:** jump to Step 7 — delete it and clean up, including
  the memory entry.

## Step 1 — Preflight

Confirm the tools and inputs before touching anything, because a half-created
droplet still costs money and a botched `sshd` config can lock everyone out.

1. **`doctl` installed?** Run `doctl version`. If missing, open
   `references/doctl-setup.md` and give the user the install steps **for their
   OS** (macOS/Homebrew, Linux/snap or tarball, Windows/Scoop, Docker, or build
   from source) — don't assume Ubuntu. Ask which platform they're on if it
   isn't obvious from the environment.
2. **`doctl` authenticated?** Run `doctl account get`. If it errors, point the
   user to the "Create an API token" and "Authenticate" sections of
   `references/doctl-setup.md`: create a token at
   `https://cloud.digitalocean.com/account/api/tokens` (needs write scope) and
   run `doctl auth init`. Do not ask the user to paste the token to you and
   never pass it as `--access-token` — `doctl auth init` prompts for it
   directly. For CI/automation, `DIGITALOCEAN_ACCESS_TOKEN` is the
   non-interactive alternative.
   - If `doctl auth init` **fails with a 401 and never prompts for a new
     token**, it's re-validating a stale one it already has. Send the user to
     `references/doctl-setup.md` §5: clear the saved context
     (`doctl auth remove --context default`, then `doctl auth init`), and
     check for a `DIGITALOCEAN_ACCESS_TOKEN` / `DIGITALOCEAN_API_TOKEN` env var
     that would bypass the prompt. Regenerating the token alone won't fix it if
     `doctl` never asks for the new value.
3. **SSH key.** See the dedicated section below — this is where a first-time
   user most often gets stuck, so handle it patiently and offer to generate a
   key for them.
4. **SSH port and username.** Ask for the login name of the new sudo user
   (e.g. `tom`). SSH port defaults to `22` — only change it if the user asks; a
   non-standard port cuts log noise but is not real security.
5. **Image.** Default `ubuntu-24-04-x64`. Only deviate if the user asks; the
   hardening script assumes a Debian-family image.

Droplet name, region, and size are chosen interactively in Step 2.

### SSH keys, for a first-time user

Assume the user may have never heard of an SSH key, and may be on **macOS,
Windows, or Linux** — the commands differ. `references/ssh-keys.md` has the
ELI5 explanation and the exact commands per OS; give the user only the rows for
their platform. Don't lecture, and move on once they have a key.

The flow:

1. **Check for an existing key** (`references/ssh-keys.md` §1). If one exists,
   offer to reuse it *or* make a fresh one just for this droplet — a per-server
   key is tidier to revoke later, but reusing a personal key is fine. Let them
   choose.
2. **If none, offer to generate one** (§2) — `ssh-keygen -t ed25519 -f
   <path>/id_ed25519_<droplet-name> -N ""`, adjusting path syntax for the OS.
   Explain the flags in plain terms from the reference. If the user wants a
   passphrase, they must run it themselves so they can type it — note that and
   move on.
3. **Tell them which file is which** (§3): the private key never leaves the
   `.ssh` folder and should be backed up once to a password manager; the
   `.pub` is the harmless half that goes on the droplet. If the private key is
   lost, access is recovered only via the DigitalOcean web console.

Record the chosen key path. You'll pass `--ssh-key <path>.pub` to
`provision.sh`, and use the matching private key with `-i <path>` for
`ssh`/`scp` in Steps 4–5. Offer the `~/.ssh/config` host alias from §4 at the
end so the user never retypes any of this.

## Step 2 — Choose region, then size (cost-first)

Do this as a short back-and-forth with the user. Don't silently pick a region
or size — the size is what they pay for, so put the cheap options in front of
them.

### 2a. Region

```bash
doctl compute region list --format Name,Slug,Available --no-header | grep -i '\btrue$'
```

Present regions to the user by their **full name**, not the slug — "Frankfurt
1", not `fra1`. Keep the slug in parentheses for reference, e.g.
`Frankfurt 1 (fra1)`. Group them by continent so the choice is obvious:

- **North America:** New York, San Francisco, Toronto, Atlanta, and others
- **Europe:** Amsterdam, London, Frankfurt
- **Asia-Pacific:** Singapore, Bangalore, Sydney

Ask which one, and recommend the one physically closest to wherever traffic
will originate (the user, their team, or their end users) — latency is the only
thing that varies, price does not. If the user already named a region, confirm
it by full name and move on.

### 2b. Size — show prices, then recommend for the actual workload

Pull the live price list (never quote prices from memory — they change) and
show the cheapest shared-CPU options, sorted by monthly price:

```bash
doctl compute size list \
  --format Slug,Memory,VCPUs,Disk,PriceMonthly,PriceHourly --no-header \
  | grep '^s-' | sort -k5 -n | head -n 8
```

Memory is in MB, disk in GB, `PriceMonthly` in USD. The `-amd` / `-intel`
suffixed slugs are dedicated-CPU variants that cost ~$1–2 more for the same
RAM — skip them unless the user wants guaranteed CPU. Recommend the plain
`s-Nvcpu-Ngb` slug.

Show the options as a small table, then **make a specific recommendation based
on what the droplet is for.** Ask the user what they'll run on it if it isn't
already clear from the conversation. Guidance:

| Intended use | Recommend | Why |
|---|---|---|
| Bastion / jump host, tiny static site, hobby script | `s-1vcpu-512mb-10gb` ($4) | Idle footprint is tiny; anything with a build step will OOM here |
| Small web app or API, single service | `s-1vcpu-1gb` ($6) | The common baseline |
| **Running Claude Code / an AI coding agent on the box** | **`s-2vcpu-4gb` ($24), or `s-1vcpu-2gb` ($12) as a floor** | Node plus Claude Code idles around 0.5–1 GB; add MCP servers, language servers, `npm install`, test suites and compilers and 1 GB OOMs mid-task. 2 vCPU keeps the agent responsive while a build runs. |
| Docker / databases / CI runner | `s-2vcpu-4gb` ($24)+ | Containers and DB caches are memory-hungry |

If the user picks a 1 GB or smaller size for a Claude Code / dev workload,
flag the risk once (installs and builds will get OOM-killed), suggest either
sizing up or adding swap, but respect their choice.

Mention that billing is hourly (the monthly figure is just a cap), so a
short-lived test costs a cent or two, and that resizing up later is possible
but needs a brief reboot (disk can only grow, never shrink). Confirm the final
**name + region (full name) + size** back to the user before moving on.

> Size availability varies slightly by region and account. If `provision.sh`
> fails with a size/region error, re-run 2b filtered to what that region
> offers and pick another.

## Step 3 — Provision

Run the provisioning script with the confirmed values:

```bash
scripts/provision.sh \
  --name web-01 \
  --region nyc3 \
  --size s-1vcpu-1gb \
  --image ubuntu-24-04-x64 \
  --ssh-key ~/.ssh/id_ed25519_web-01.pub   # the .pub chosen in Step 1
```

What it does:

- Registers the public key with DigitalOcean if it isn't already (matches by
  key fingerprint, so re-runs are safe).
- Creates the droplet with `--wait` so it returns only once the droplet is
  active.
- Polls TCP 22 on the public IP until `sshd` responds (usually 15–40s after
  active).
- Prints the droplet's public IPv4 as the last line and writes it to
  `./.droplet-ip` for the next step.

If the script fails after the droplet was created, it prints the droplet ID so
you can `doctl compute droplet delete <id>` rather than leaking a paid
resource.

## Step 4 — Harden

Copy the hardening script to the droplet and run it as root. At this point root
key login still works because DigitalOcean installed the registered key for
root.

```bash
IP=$(cat ./.droplet-ip)
KEY=~/.ssh/id_ed25519_web-01          # the private key chosen in Step 1
scp -i "$KEY" scripts/harden.sh root@"$IP":/root/harden.sh
ssh -i "$KEY" root@"$IP" "bash /root/harden.sh --user tom --port 22 --swap 2G --pubkey \"$(cat "$KEY".pub)\""
```

`-i "$KEY"` tells `ssh`/`scp` which private key to use; skip it only if the key
has the default name (`~/.ssh/id_ed25519`). Pass `--swap` on droplets under
4 GB RAM that will run build tooling or Claude Code (see Step 2b) — rule of
thumb is swap = RAM, so `--swap 1G` on a 1 GB box, `--swap 2G` on a 2 GB box.
Omit it on 4 GB+ or a pure bastion.

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
  `-p <port>`, and any DigitalOcean Cloud Firewall or local `ssh_config` needs
  updating too.

### Optional: save a shortcut so they never retype this

For a first-time user, offer to add the `~/.ssh/config` host alias from
`references/ssh-keys.md` §4 so future logins are just `ssh <droplet-name>`
(the reference notes the Windows path caveat).

## Step 6 — Summary

First, print the **connection details block** below verbatim (filled in) as the
last thing in your reply. It exists so that this Claude session — or any tool —
can SSH into the droplet straight away without hunting through prose. Keep the
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

Then the human-readable recap:

- droplet name, region (full name), size, image, droplet ID
- what was hardened: root SSH disabled, password auth disabled, passwordless
  `sudo` for `<user>`, UFW active with ports `<ssh>`, 80, 443 open; swapfile if
  `--swap` was used
- which key file is the private one to guard, and the reminder to back it up
- if the `~/.ssh/config` alias was added, note that `ssh <droplet-name>` now
  works too

### Record it to memory

If you have a persistent memory or notes facility, save the droplet's details
there now so a future session can connect without re-deriving anything. This is
"project"-type context: an ongoing resource, not a one-off fact.

Use a stable, predictable key — `droplet-<name>` (e.g. `droplet-cc-dev`) — so
the deprovision step (Step 7) can find and remove it. Store, at minimum:

- droplet name, DigitalOcean droplet **ID**, region, size, image
- public IPv4
- **SSH host** (`<user>@<ip>`), **SSH port**, absolute **path to the private
  key**
- the ready-to-run `ssh -i <key> -p <port> <user>@<ip>` command
- creation date, and a one-line note that it was hardened by this skill

Keep it accurate: if the droplet is later resized, rebuilt, or its key
changes, update the same entry rather than adding a second one.

## Optional: run Claude Code on the droplet (Remote Control)

If the user wants to drive Claude Code *on the droplet* from `claude.ai/code`
or the Claude mobile app — "make this a Claude Code box", "control it from my
phone" — set up Remote Control. Full walkthrough in
`references/remote-control.md`; the short version:

1. **Sizing.** Claude Code needs Node 22 and each Remote Control server idles
   ~150–300 MB on top of that. Steer to `s-2vcpu-4gb`, or `s-1vcpu-2gb`
   `--swap 2G` as a floor for one or two servers (see Step 2b).
2. **Name the first server.** A Remote Control server serves **one directory**
   and appears as **one named session** in `claude.ai/code` and the mobile Code
   tab. Ask the user what to call this first one — it becomes
   `~/projects/<name>` and the session label, so it should mean something
   (`sandbox` for throwaway work, or a project/repo name). `[a-z0-9-]` only.
   They can add more servers later.
3. **Install.** Copy `scripts/setup-claude-code.sh` to the droplet, run it as
   the sudo user: `bash setup-claude-code.sh --name <first-server-name>
   --service`. It installs Node 22 (from nodejs.org — apt only has 18), Claude
   Code, `tmux`, `git`; makes `~/projects/<name>`; and installs the templated
   `claude-rc@.service` unit + linger so servers survive reboot.
4. **Log in** (interactive — you can't do it for them, but you can relay). In
   an SSH session: `cd ~/projects/<name> && claude`, choose the subscription
   option. Claude Code prints an OAuth URL and waits for a pasted code. Give
   the URL to the user; they approve in a browser signed into their Claude
   (Pro/Max) account and paste back the `<code>#<state>` string; you feed it in
   (via `tmux send-keys` if driving a tmux session). Then accept the workspace
   trust dialog and `/exit`. Login is once per droplet; **trust is per
   directory**.
5. **Start it.** `systemctl --user enable --now claude-rc@<name>`, then
   `systemctl --user status claude-rc@<name>`. Without a TTY,
   `claude remote-control` skips its y/n gate and just connects.
6. **Hand off.** Give the user the session URL
   (`https://claude.ai/code?environment=<env id>`) and tell them it also shows
   as `<name>` in `claude.ai/code` and the mobile **Code** tab. Mention
   `/config` → push notifications.

**More servers / repos.** To add another directory or clone a repo into its own
session: on the droplet, `./add-rc-server.sh --name <other> [--repo <git-url>]`,
then trust the dir and `systemctl --user enable --now claude-rc@<other>`. For a
**private** repo the droplet needs GitHub auth first (`gh auth login` device
flow, a deploy key, or a PAT) — this is *not* part of droplet setup; walk the
user through it from `references/remote-control.md` → "Private GitHub
repositories" only when they need it.

Add a note to the droplet's memory entry that it runs Remote Control, listing
the server name(s) and the `systemctl --user … claude-rc@<name>` commands.

No firewall change is needed — Remote Control is outbound HTTPS only.

## Step 7 — Deleting the droplet later

When the user asks to tear a droplet down:

1. **Confirm** which droplet by name **and** ID, and that they accept it's
   immediate and irreversible — the disk and everything on it is gone, no
   snapshot unless they made one.
2. Delete it:
   ```bash
   doctl compute droplet delete <id> --force
   ```
3. Verify it's gone: `doctl compute droplet list`.
4. **Clean up the traces** so nothing stale is left behind:
   - **Memory.** Remove the `droplet-<name>` entry you saved in Step 6 (or, if
     your memory system prefers, mark it destroyed with the date). A deleted
     droplet's connection details must not linger as if still live.
   - **Auto-imported SSH key.** If `provision.sh` registered a one-off key on
     the DigitalOcean account for this droplet (named `<name>-<date>`), remove
     it: `doctl compute ssh-key list`, then
     `doctl compute ssh-key delete <id> --force`. **Never** delete the user's
     pre-existing personal keys.
   - **Known-hosts.** `ssh-keygen -R <ip>` (also
     `ssh-keygen -R "[<ip>]:<port>"` if a non-standard port was used).
   - **Local key pair.** If a per-droplet key was generated in Step 1 and isn't
     used anywhere else, offer to delete
     `~/.ssh/id_ed25519_<name>{,.pub}` — but ask first, don't assume.
   - Remove a leftover `./.droplet-ip` file if present.
5. Confirm to the user what was deleted and what was cleaned up.

## Notes and edge cases

- **Idempotency.** Re-running `provision.sh` with the same name creates a
  *second* droplet — DigitalOcean allows duplicate names. Check
  `doctl compute droplet list` first if a re-run is possible.
- **`harden.sh` re-runs** are safe: it skips user creation if the user exists
  and overwrites only its own `99-hardening.conf` drop-in.
- **UFW and Docker.** If the user plans to run Docker, warn them Docker
  publishes ports straight into iptables and bypasses UFW — that's out of scope
  here but worth a heads-up.
- **IPv6 / monitoring / VPC.** Add `--enable-ipv6`, `--enable-monitoring`, or
  `--vpc-uuid` to the `provision.sh` invocation via its passthrough `--extra`
  flag if the user asks.
- **Cost.** Billing is hourly up to the monthly cap. Tear a test droplet down
  via Step 7 as soon as you're done — a forgotten droplet bills silently.
  Snapshots and reserved IPs bill separately if added.
- **Cheapest size** is `s-1vcpu-512mb-10gb`; see Step 2b for when it's too
  small.
