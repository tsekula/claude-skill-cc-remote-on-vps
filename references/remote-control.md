# Run Claude Code on the droplet with Remote Control

Remote Control keeps a `claude` process running **on the droplet** and lets you
drive it from `claude.ai/code` and the Claude mobile app (Code tab). Execution
and the filesystem stay on the droplet; only chat messages and tool results
travel through Anthropic's API over **outbound HTTPS**. No inbound ports, so the
skill's UFW rules need no change.

Official docs: https://code.claude.com/docs/en/remote-control

## Prerequisites

- **Claude Pro or Max** (Team/Enterprise need an Owner to enable the Remote
  Control toggle). API-key auth does **not** work.
- On the droplet, none of these set in the environment (they disable Remote
  Control): `ANTHROPIC_API_KEY`, `ANTHROPIC_BASE_URL` pointing off
  `api.anthropic.com`, `DISABLE_TELEMETRY`, `DO_NOT_TRACK`,
  `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`, `DISABLE_GROWTHBOOK`.
- **Node 22+**. Ubuntu 24.04's apt only has 18, so the helper script installs
  Node 22 from nodejs.org.

## 1. Install (automated)

Copy `scripts/setup-claude-code.sh` to the droplet and run it **as the sudo
user** (not root):

```bash
scp -i <key> scripts/setup-claude-code.sh <user>@<ip>:/tmp/
ssh -i <key> <user>@<ip> "bash /tmp/setup-claude-code.sh --name <droplet-name> --service"
```

It installs Node 22, `@anthropic-ai/claude-code`, and `tmux`; creates
`~/projects/scratch`; and with `--service` installs a `systemd --user` unit
plus `loginctl enable-linger` so Remote Control survives logout and reboot. It
does **not** log you in — that's interactive — and prints the remaining steps.

Flags: `--project-dir PATH` (default `~/projects/scratch`), `--name NAME`
(session name shown in claude.ai/code, default hostname), `--service`.

## 2. Log in (interactive, headless-friendly)

Claude Code login needs a browser. On a headless droplet it prints a URL and
waits for a pasted code — no localhost callback, so no SSH tunnel needed.

```bash
ssh -i <key> <user>@<ip>
cd ~/projects/scratch && claude
```

- Choose **"Claude account with subscription"**.
- Open the printed `https://claude.com/cai/oauth/authorize?...` URL in a browser
  signed in to your Claude account, approve, and copy the code from the
  `platform.claude.com` page it redirects to (looks like `<code>#<state>`).
- Paste it at the `Paste code here` prompt.
- Accept the **workspace trust** dialog (Remote Control refuses to start in an
  untrusted directory, and never from `$HOME`).
- `/exit`.

Driving this for someone over chat: run `claude` in a `tmux` session so it
stays alive between steps, `tmux capture-pane -p` to read the URL, relay it,
and `tmux send-keys -t <sess> -l "<code>"` then `send-keys Enter` to submit.

## 3. Start Remote Control

### With the systemd service (persists across reboot)

```bash
systemctl --user enable --now claude-rc
systemctl --user status claude-rc --no-pager
```

The session appears as your `--name` at `claude.ai/code` and in the mobile
**Code** tab. If it doesn't connect:
`journalctl --user -u claude-rc -n 30 --no-pager`.

Manage it: `systemctl --user {restart,stop,disable} claude-rc`.

Why this works unattended: run without a TTY, `claude remote-control` skips its
interactive "Enable Remote Control? (y/n)" gate and connects straight away. The
unit sets `TERM=dumb` and `StandardOutput=null` to swallow the once-a-second
status-line redraw.

### Without systemd — tmux only

```bash
tmux new -s cc
cd ~/projects/scratch && claude remote-control --name <droplet-name>
#   Ctrl-b then d   to detach; it keeps running until the droplet reboots
```

Reattach later with `tmux attach -t cc`. This does **not** survive a reboot;
re-run `scripts/setup-claude-code.sh --service` to upgrade to the systemd unit.

## 4. Connect

- **Web**: the session URL from the terminal, or pick the session by name at
  `claude.ai/code`.
- **Mobile**: Claude app → **Code** tab → the session (computer icon, green dot
  = online). No app yet? Run `/mobile` in a `claude` session for a QR.
- **QR**: in a foreground `claude remote-control`, press <kbd>space</kbd>.

Recover the session URL later: it's
`https://claude.ai/code?environment=<env id>`; the env id is stable per
directory. `claude remote-control --continue` in the project dir also
reattaches (within ~4h of the last server there).

## 5. Push notifications

In a plain `claude` session on the droplet: `/config` → enable **Push when
Claude decides** and/or **Push when actions required**. Needs the mobile app
installed and signed in to the same account.

## Operating notes

- **Reboot**: with the systemd unit + linger, Remote Control comes back on its
  own. Workspace trust and the login token persist in `~/.claude*`.
- **Updating Claude Code**: `sudo npm i -g @anthropic-ai/claude-code`, then
  `systemctl --user restart claude-rc`.
- **Teardown**: destroying the droplet (skill Step 7) takes the Remote Control
  session, the login token, and the systemd unit with it — nothing to undo on
  the account side. The session just disappears from `claude.ai/code`.
- **One account, shared control**: anyone signed into that Claude account can
  drive the droplet while Remote Control is up, and the transcript is stored on
  Anthropic servers per the Data usage policy.
