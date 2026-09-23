# Run Claude Code on the server with Remote Control

Remote Control keeps a `claude` process running **on the box** and lets you
drive it from `claude.ai/code` and the Claude mobile app (Code tab). Execution
and the filesystem stay on the box; only chat messages and tool results
travel through Anthropic's API over **outbound HTTPS**. No inbound ports, so the
skill's UFW rules need no change.

Official docs: https://code.claude.com/docs/en/remote-control

## Model: one server per directory

A `claude remote-control` process is a **server for one directory**. Every
session it spawns shares that directory (`--spawn same-dir`), and it shows up as
**one named entry** in `claude.ai/code` and the mobile Code tab.

To work on several things — a sandbox plus one or more repos — run **several
servers**, one per directory, each its own systemd instance. See
[Multiple Remote Control servers](#multiple-remote-control-servers).

## Prerequisites

- **Claude Pro or Max** (Team/Enterprise need an Owner to enable the Remote
  Control toggle). API-key auth does **not** work.
- On the box, none of these set in the environment (they disable Remote
  Control): `ANTHROPIC_API_KEY`, `ANTHROPIC_BASE_URL` pointing off
  `api.anthropic.com`, `DISABLE_TELEMETRY`, `DO_NOT_TRACK`,
  `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`, `DISABLE_GROWTHBOOK`.
- Nothing else: the helper script uses Anthropic's **native installer**
  (`curl -fsSL https://claude.ai/install.sh | bash`, run as the sudo user,
  never with `sudo`), which puts a self-updating binary at
  `~/.local/bin/claude`. No Node.js required. It needs ~512 MB free RAM
  while installing.

## 1. Install + first server (automated)

Ask the user what to call the **first** Remote Control server. That name becomes
the directory `~/projects/<name>` **and** the session label they'll see in
`claude.ai/code` and the mobile Code tab, so it should mean something —
`sandbox` for throwaway experiments, or a project/repo name. `[a-z0-9-]` only.

Copy `scripts/setup-claude-code.sh` to the box and run it **as the sudo
user** (not root):

```bash
scp -i <key> scripts/setup-claude-code.sh <user>@<ip>:/tmp/
ssh -i <key> <user>@<ip> "bash /tmp/setup-claude-code.sh --name <first-server-name> --service"
```

It installs Claude Code (native), `tmux`, and `git`; removes an old global
npm install of Claude Code if one is there; creates
`~/projects/<name>`; and with `--service` installs the **templated**
`systemd --user` unit `claude-rc@.service` plus `loginctl enable-linger` so
servers survive logout and reboot. It does **not** log you in — that's
interactive — and prints the remaining steps.

Flags: `--name NAME` (default `sandbox`), `--service`.

## 2. Log in (interactive, headless-friendly)

Claude Code login needs a browser. On a headless box it prints a URL and
waits for a pasted code — no localhost callback, so no SSH tunnel needed.

```bash
ssh -i <key> <user>@<ip>
cd ~/projects/<name> && claude
```

- Choose **"Claude account with subscription"**.
- Open the printed `https://claude.com/cai/oauth/authorize?...` URL in a browser
  signed in to your Claude account, approve, and copy the code from the
  `platform.claude.com` page it redirects to (looks like `<code>#<state>`).
- Paste it at the `Paste code here` prompt.
- Accept the **workspace trust** dialog (Remote Control refuses to start in an
  untrusted directory, and never from `$HOME`).
- `/exit`.

Login is once per box — the token in `~/.claude*` covers every server.
Workspace trust, though, is **per directory**: repeat the `cd … && claude` +
trust step for each new server directory.

Driving login for someone over chat: run `claude` in a `tmux` session so it
stays alive between steps, `tmux capture-pane -p` to read the URL, relay it,
and `tmux send-keys -t <sess> -l "<code>"` then `send-keys Enter` to submit.

## 3. Start the first server

### With systemd (persists across reboot)

```bash
systemctl --user enable --now claude-rc@<name>
systemctl --user status claude-rc@<name> --no-pager
```

Appears as `<name>` at `claude.ai/code` and in the mobile **Code** tab. If it
doesn't connect: `journalctl --user -u claude-rc@<name> -n 30 --no-pager`.

Manage it: `systemctl --user {restart,stop,disable} claude-rc@<name>`.

Why this works unattended: run without a TTY, `claude remote-control` skips its
interactive "Enable Remote Control? (y/n)" gate and connects straight away. The
unit sets `TERM=dumb` and `StandardOutput=null` to swallow the once-a-second
status-line redraw.

### Without systemd — tmux only

```bash
tmux new -s <name>
cd ~/projects/<name> && claude remote-control --name <name>
#   Ctrl-b then d   to detach; runs until the box reboots
```

Reattach with `tmux attach -t <name>`. Re-run `setup-claude-code.sh --service`
to upgrade to the systemd unit.

## Multiple Remote Control servers

The unit is templated (`claude-rc@.service`), so each server is an instance
named after its directory under `~/projects`:

```bash
# on the box, as the sudo user, after setup-claude-code.sh
./add-rc-server.sh --name myapp --repo git@github.com:me/myapp.git
#   (omit --repo for an empty directory)

cd ~/projects/myapp && claude          # accept trust, then /exit
systemctl --user enable --now claude-rc@myapp
```

`add-rc-server.sh` makes the directory (cloning the repo if `--repo` is given),
checks the templated unit is installed, and prints the trust + enable steps. Now
`claude.ai/code` lists `sandbox`, `myapp`, … each driving its own directory.

Running many at once: each server idles ~150–300 MB. On a 2 GB box keep it
to 2–3; sensible on 4 GB+. Stop ones you're not using with
`systemctl --user stop claude-rc@<name>` (state is kept; `start` brings it
back).

`--spawn worktree` (edit the unit's `ExecStart`, or add a drop-in with
`systemctl --user edit claude-rc@<name>`) puts each on-demand session in its own
git worktree so parallel sessions in one repo don't collide.

## Private GitHub repositories

`add-rc-server.sh --repo` just runs `git clone`; a private repo needs auth **on
the box** first. This is not part of server setup — set it up when needed.
Pick one:

- **GitHub CLI, device flow** (easiest headless):
  ```bash
  sudo apt-get install -y gh        # or: see cli.github.com for the apt repo
  gh auth login                     # choose GitHub.com > HTTPS > device code
  ```
  It prints a one-time code and a URL; open the URL in a browser signed in to
  GitHub, enter the code, approve. `gh` then configures git credentials, so
  `git clone https://github.com/<owner>/<repo>.git` works. Relay the code the
  same way as the Claude login.

- **Deploy key** (scoped to one repo):
  ```bash
  ssh-keygen -t ed25519 -f ~/.ssh/id_<repo> -N ""
  cat ~/.ssh/id_<repo>.pub
  ```
  Add that public key at the repo's **Settings → Deploy keys** (check "Allow
  write access" only if the box needs to push). Then add to `~/.ssh/config`:
  ```
  Host github.com-<repo>
      HostName github.com
      User git
      IdentityFile ~/.ssh/id_<repo>
  ```
  and clone `git@github.com-<repo>:<owner>/<repo>.git`.

- **Fine-grained PAT**: create one at GitHub → Settings → Developer settings,
  scoped to the repo with Contents: Read. Clone
  `https://<token>@github.com/<owner>/<repo>.git`, or store it with
  `git config --global credential.helper store` after one prompted clone. The
  token sits in `~/.git-credentials` in plaintext — prefer `gh` or a deploy key.

For pushing back, `gh` and a write-enabled deploy key both work; a PAT needs
Contents: Read **and** Write.

## Connect

- **Web**: the session URL from the terminal, or pick the session by name at
  `claude.ai/code`.
- **Mobile**: Claude app → **Code** tab → the session (computer icon, green dot
  = online). No app yet? Run `/mobile` in a `claude` session for a QR.
- **QR**: in a foreground `claude remote-control`, press <kbd>space</kbd>.

Recover a session URL later: it's `https://claude.ai/code?environment=<env id>`;
the env id is stable per directory. `claude remote-control --continue` in the
project dir also reattaches (within ~4h of the last server there).

## Push notifications

In a plain `claude` session on the box: `/config` → enable **Push when
Claude decides** and/or **Push when actions required**. Needs the mobile app
installed and signed in to the same account.

## Operating notes

- **Reboot**: enabled `claude-rc@*` instances come back on their own (unit +
  linger). Workspace trust and the login token persist in `~/.claude*`.
- **Updating Claude Code**: the native build updates itself in the
  background; a running server picks up the new version when restarted. To
  force it now: `claude update`, then
  `systemctl --user restart 'claude-rc@*'`.
- **Teardown**: destroying the box (skill Step 8) takes every Remote Control
  session, the login token, and the units with it — nothing to undo on the
  account side. The sessions just disappear from `claude.ai/code`.
- **One account, shared control**: anyone signed into that Claude account can
  drive the box while Remote Control is up, and the transcript is stored on
  Anthropic servers per the Data usage policy.
