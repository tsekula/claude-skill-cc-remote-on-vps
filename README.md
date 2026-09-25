# Claude Code Remote Control on VPS

*(skill name `cc-remote-on-vps`)*

## What is this?

Normally Claude Code runs on your own computer. Close the laptop and it stops.

This skill gets Claude to set up a small rented computer in the cloud (a
"server", or "VPS") that stays on around the clock, with Claude Code running on
it. You then talk to it from wherever you are: the Claude website, the Claude
desktop app, or the Claude app on your phone.

Some things you can do with that:

- Start a coding task at your desk, then check on it from your phone.
- Let Claude keep working on a long job while your laptop is closed.
- Have a safe "sandbox" where Claude can install and try things without
  touching your own computer.

You don't need to know anything about servers. You tell Claude you want one,
answer a few simple questions, and Claude does the rest: it rents the server,
locks it down, installs Claude Code, and hands you a session you can open from
anywhere.

## What you need before you start

- **A paid Claude plan** (Pro, Max, Team or Enterprise). A free account or an
  API key won't work for this.
- **An account with one cloud company.** The skill works with two. Either is
  fine:
  - **Hetzner** (hetzner.com/cloud). Usually the cheapest. Its data centres are
    mostly in Europe, plus the US and Singapore.
  - **DigitalOcean** (digitalocean.com). Well known and easy to use, with more
    locations worldwide, but it costs more.
- **A computer** running Windows, macOS or Linux, with the Claude desktop app.

You **don't** need to install anything else yourself. If Claude needs a tool
(the cloud company's command-line tool, for example), it installs it for you.

### What it costs

The cloud company bills you for as long as the server exists, whether you use
it or not. Rough prices for the size this skill recommends (4 GB of memory):

| Company | Roughly per month |
|---|---|
| Hetzner (`cx23`) | about €6, plus VAT |
| DigitalOcean (`s-2vcpu-4gb`) | about $24 |

Claude shows you the real, current prices before it creates anything. Both
companies charge by the hour, so a server you try for an afternoon and then
delete costs a few cents.

**Turning the server off doesn't stop the bill. Only deleting it does.** The
last section below shows how.

## Setting it up

### Step 1: Get the skill

Download the latest
[`cc-remote-on-vps.skill`](https://github.com/tsekula/claude-skill-cc-remote-on-vps/raw/refs/heads/master/cc-remote-on-vps.skill)
file and save it somewhere easy to find, like your Downloads folder.

It's a zip file in disguise. Don't unzip it. If an upload window only accepts
`.zip` files, make a copy and rename the copy from `.skill` to `.zip`.

### Step 2: Add it to your Claude account

1. Go to [claude.ai](https://claude.ai) and sign in with your paid account.
2. Open **Settings → Capabilities** and make sure **Code execution and file
   creation** is switched on.
3. Open **Customize → Skills**, click **+**, choose **Create skill**, then
   **Upload a skill**.
4. Pick the file you downloaded, wait for it to upload, and switch it on.

The skill is private to your account. It follows you to the Claude desktop app
too, because skills belong to your account, not to one device.

### Step 3: Ask Claude to build your server

Do this part **in the Claude desktop app, in the Code tab, on your own
computer**. That matters: Claude creates a "key" file (it works like a house
key for the server) and saves it on your computer. If you did this in a
browser-only session, the key could vanish when the session ends.

1. Install the Claude desktop app from
   [claude.com/download](https://claude.com/download) and sign in with the same
   account.
2. Open the **Code** tab and start a new session. Any folder is fine.
3. Type something like:

   > Use the cc-remote-on-vps skill to set up a new Hetzner server for me.

   (or "DigitalOcean server", whichever company you picked).

Claude then walks you through it. Expect to:

- **Say where you are**, so it can pick a nearby data centre.
- **Pick a size.** It shows prices and recommends one. The recommendation is
  fine.
- **Choose a name for the server** (like `my-claude-box`) and a username for
  yourself (like `sam`).
- **Create an API token** at the cloud company. This is a password-like code
  that lets Claude create the server for you. Claude tells you exactly where to
  click. Then you paste the token into **your own terminal window** with one
  command Claude gives you. Never paste it into the chat, and Claude won't ask
  you to.
- **Approve a few actions** when Claude asks permission to run things. That's
  normal.
- **Log in to Claude on the server.** Near the end, Claude gives you a link.
  Open it, approve, and paste back the code it shows. This connects the server
  to your Claude account.
- **Name your first session.** `sandbox` is a good choice for experiments, or
  use the name of a project.

The whole thing takes about 10–15 minutes. At the end, Claude shows you two
blocks of details. The **SSH CONNECTION DETAILS** block is how to reach the
server. The **REMOTE CONTROL READY** block has your session's name and link.
Keep both somewhere safe, like a note in your password manager.

**Back up your key.** Claude tells you which file is your private key (it lives
in a folder called `.ssh` in your home folder). Save a copy in your password
manager. If you lose it, you lose your way into the server.

### Step 4: Use it from anywhere

- **Web:** go to [claude.ai/code](https://claude.ai/code) and pick your session
  by name.
- **Desktop:** open the **Code** tab in the Claude app. Your session is listed
  there.
- **Phone:** install the Claude app (iPhone or Android), sign in, open the
  **Code** tab, and tap your session. A green dot means it's online.

Want a ping on your phone when Claude needs you or finishes? In a session, type
`/config` and switch on push notifications.

## Everyday use: what to say to Claude

You manage everything by asking Claude in plain English, from a Code session on
your computer. Swap in your own server and session names.

| When you want to… | Say something like… |
|---|---|
| Set up a server | "Use the cc-remote-on-vps skill to set up a new Hetzner server." |
| Add a second project, in its own session | "Add a Remote Control session called `blog` to my server `my-claude-box`." |
| Start work on one of your GitHub projects | "Add a session called `my-app` to `my-claude-box` and clone `https://github.com/me/my-app` into it." |
| Check everything is running | "Check the Remote Control sessions on `my-claude-box` are running." |
| Fix a session that's gone missing or stuck | "Restart the `sandbox` session on `my-claude-box`." |
| Update Claude Code on the server | "Update Claude Code on `my-claude-box` and restart its sessions." (It also updates itself automatically.) |
| Make the server bigger | "Resize `my-claude-box` to 8 GB of memory." (Takes a short restart. You can grow the disk but never shrink it.) |
| Get your connection details again | "How do I connect to `my-claude-box`?" |
| Delete it and stop paying | "Delete my server `my-claude-box` and clean up after it." |

Claude saves the details of each server it builds (where it is, how to log in)
to its memory when it can, so later requests usually just work. If it can't
find them, paste in the **SSH CONNECTION DETAILS** block from setup.

Each session runs in its own folder on the server and shows up under its own
name in the app. Two or three sessions at once is comfortable on the
recommended size.

## Doing it yourself (optional)

You never *have* to touch the server directly. If you're curious, here are the
handful of commands that cover the basics. Run them in a terminal on your
computer (on Windows, **Terminal** or **PowerShell**; on a Mac, **Terminal**).

**Log in to the server:**

```bash
ssh my-claude-box
```

That short version works if you let Claude add a shortcut during setup.
Otherwise, use the `Connect:` line from your SSH CONNECTION DETAILS block. It
looks like `ssh -i <key file> sam@<address>`. Type `exit` to leave.

**Once you're logged in to the server**, swap `sandbox` for your session's
name:

| What | Command |
|---|---|
| Is my session running? | `systemctl --user status claude-rc@sandbox` |
| Restart a session | `systemctl --user restart claude-rc@sandbox` |
| Pause a session (frees memory, keeps its work) | `systemctl --user stop claude-rc@sandbox` |
| Start it again | `systemctl --user start claude-rc@sandbox` |
| See why a session isn't connecting | `journalctl --user -u claude-rc@sandbox -n 30` |
| Update Claude Code now | `claude update` |
| How much memory is in use? | `free -h` |

**Deleting the server yourself**, from your own computer, not the server:

```bash
hcloud server delete my-claude-box                        # Hetzner
doctl compute droplet delete my-claude-box --force        # DigitalOcean
```

Asking Claude is better, because it also tidies up the leftover key, its
notes, and (on Hetzner) any spare IP address that would keep costing a little.

## Is it safe?

The server runs 24/7 and Claude can change things on it, so the skill locks it
down before anything else. In plain terms:

- **No passwords.** You get in with your key file only. Bots that guess
  passwords all day have nothing to guess.
- **No logging in as the all-powerful "root" account.** You get a normal
  account that can do admin tasks when needed. A mistake, yours or Claude's,
  can't take over the whole machine by default.
- **A firewall** blocks everything except the way in you use (SSH) and two
  standard web ports kept open for later. Remote Control doesn't need an open
  port at all: the server calls out to Claude, nothing calls in.
- **Security fixes install themselves**, so known holes get patched without
  you logging in.
- **Settings are checked before they're switched on**, so a mistake can't lock
  you out.
- **Optional extra:** you can ask for `fail2ban`, which blocks addresses that
  keep failing to log in. It's not essential when there's no password to
  guess, but it cuts down the noise.

Two things to keep in mind:

- **Anyone signed in to your Claude account can drive the server** while
  Remote Control is on. Protect your Claude login (a strong password and
  two-factor sign-in).
- **Your conversations with the server go through Anthropic**, like any other
  Claude conversation. The files stay on your server.

## If something goes wrong

- **"Command not found" after Claude installed a tool.** Close your terminal
  window and open a new one. Windows only picks up newly installed tools in new
  windows.
- **Your session doesn't show up in the app.** Ask Claude to "check the Remote
  Control sessions on my server", or restart the session with the command
  above. Make sure you're signed in to the same Claude account everywhere.
- **"Permission denied" when you log in yourself.** You're probably using the
  wrong key file or username. Use the exact `Connect:` line from your SSH
  CONNECTION DETAILS.
- **You lost your key file.** You can still reach the server through the cloud
  company's website (look for a "console" button on the server's page). Ask
  Claude to walk you through adding a new key. Or, if nothing important is on
  it, delete the server and build a fresh one.
- **Claude's work keeps stopping on a busy task.** The server may be running
  out of memory. Ask Claude to resize it to the next size up.

---

## For the technically curious

What the skill runs, and where:

| File | What it does | Runs on |
|---|---|---|
| [`SKILL.md`](SKILL.md) | The step-by-step instructions Claude follows | — |
| `scripts/install-cli.sh` | Installs or updates `hcloud` / `doctl` (checksum-verified, no admin rights) and adds it to PATH | Your computer |
| `scripts/provision-hetzner.sh`, `scripts/provision-digitalocean.sh` | Creates the server and waits until it answers | Your computer |
| `scripts/harden.sh` | Creates the non-root sudo user, installs your key, turns off password and root login, sets up the firewall, swap, automatic security updates, and optional `fail2ban`. Checks the SSH settings before applying them. | The server, as root |
| `scripts/setup-claude-code.sh` | Installs Claude Code (Anthropic's native installer) and the `claude-rc@` background service | The server, as your user |
| `scripts/add-rc-server.sh` | Adds another session: one folder under `~/projects`, optionally cloning a repo | The server, as your user |
| `references/*.md` | Provider details, SSH key help, Remote Control details | — |

On Windows, the scripts run through Git Bash, which Claude installs if it's
missing.

### Installing from this repository instead

If you use the `claude` command-line tool, you can link this folder in as a
personal skill instead of uploading the `.skill` file:

```bash
mkdir -p ~/.claude/skills
ln -s "$(pwd)" ~/.claude/skills/cc-remote-on-vps
```

On Windows, from PowerShell run as administrator:

```powershell
New-Item -ItemType SymbolicLink -Path "$HOME\.claude\skills\cc-remote-on-vps" -Target (Get-Location)
```

Or just copy the folder into `~/.claude/skills/`.
