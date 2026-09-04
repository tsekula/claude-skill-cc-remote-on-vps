# SSH keys — for a first-time user, on any OS

Give the user only the rows for **their** operating system. Commands differ
between macOS, Windows, and Linux; the concepts don't.

## The idea (ELI5)

An SSH key is a matched pair of files:

- The **private** key is like a house key in your pocket — never share it,
  never email it, never paste it anywhere.
- The **public** key is like a padlock you can hand out freely.

We put the public padlock on the server. Only your private key opens it. This
beats a password because there's nothing to guess or phish.

The two files live in a folder called `.ssh` inside your home directory. Your
computer's SSH program looks there automatically.

| OS | Home `.ssh` folder |
|----|--------------------|
| macOS | `/Users/<you>/.ssh/` — type it as `~/.ssh/` |
| Linux | `/home/<you>/.ssh/` — type it as `~/.ssh/` |
| Windows | `C:\Users\<you>\.ssh\` — type it as `~\.ssh\` in PowerShell |

## 0. Is the `ssh` command available?

- **macOS / Linux:** built in. `ssh -V` prints a version.
- **Windows 10/11:** the OpenSSH client ships with Windows but may be off.
  Check with `ssh -V` in PowerShell. If "not recognized", enable it:
  Settings → System → Optional features → Add a feature → **OpenSSH Client**,
  or run in an **admin** PowerShell:
  `Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0`
  (Alternatively use Git Bash or WSL, which bundle their own `ssh`.)

## 1. Do they already have a key?

**macOS / Linux (Terminal):**
```bash
ls -l ~/.ssh/*.pub 2>/dev/null
```

**Windows (PowerShell):**
```powershell
Get-ChildItem ~\.ssh\*.pub -ErrorAction SilentlyContinue
```

If a `.pub` file is listed, they have a key and can reuse it, or make a fresh
one dedicated to this server (cleaner to revoke later). If nothing lists,
generate one.

## 2. Generate a key

The command is the same everywhere; only the path syntax differs. Offer to run
it for them.

**macOS / Linux:**
```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_<server-name> -C "<server-name>" -N ""
```

**Windows (PowerShell):**
```powershell
ssh-keygen -t ed25519 -f "$env:USERPROFILE\.ssh\id_ed25519_<server-name>" -C "<server-name>" -N '""'
```
(If `$env:USERPROFILE\.ssh` doesn't exist yet: `mkdir "$env:USERPROFILE\.ssh"`.)

Flag by flag:

- `-t ed25519` — the modern, strong key type.
- `-f ...` — where the pair is written and what it's named. Naming it after the
  server name makes it obvious later which key is which.
- `-C "..."` — a label stored inside the public file, for your future self.
- `-N ""` (PowerShell: `-N '""'`) — no passphrase, so the key just works. This
  is the simplest choice for a first server. For an extra layer — a password
  that protects the private *file itself* — the user should run the command
  **without** the `-N` part in their own terminal, so they can type the
  passphrase privately. Claude can't type it for them. A passphrase can also be
  added later:
  `ssh-keygen -p -f ~/.ssh/id_ed25519_<server-name>`.

## 3. What was created, and how to look after it

Two files, e.g. for `<server-name>` = `web-01`:

| File | What it is | Rule |
|------|-----------|------|
| `id_ed25519_web-01` | **private** key | Never leaves `~/.ssh`. Don't put it in Dropbox/OneDrive/iCloud/Google Drive. Don't paste it into chat. |
| `id_ed25519_web-01.pub` | **public** key | Safe to share. This is what goes on the server (the skill handles that). |

**Back it up once, now.** If the private key is lost, key-based login is gone
and recovery means the provider's web console or rescue mode. A good backup is a
secure note in a password manager (1Password, Bitwarden, Apple Passwords, …).

**Permissions:**

- **macOS / Linux:** `ssh-keygen` already sets them correctly (`700` on
  `~/.ssh`, `600` on the private key). Nothing to do.
- **Windows:** normally fine as created. If `ssh` later complains the key is
  "too open" / "bad permissions", lock the file to your account:
  ```powershell
  icacls "$env:USERPROFILE\.ssh\id_ed25519_<server-name>" /inheritance:r /grant:r "$($env:USERNAME):(R)"
  ```

## 4. Optional niceties

**Remember the passphrase (if they set one) via the agent:**

- **macOS:** `ssh-add --apple-use-keychain ~/.ssh/id_ed25519_<server-name>`
  (stores it in Keychain; re-added automatically on reboot).
- **Windows:** start the agent once (admin PowerShell:
  `Set-Service ssh-agent -StartupType Automatic; Start-Service ssh-agent`),
  then `ssh-add "$env:USERPROFILE\.ssh\id_ed25519_<server-name>"`.
- **Linux:** `ssh-add ~/.ssh/id_ed25519_<server-name>` (agent usually already
  running under the desktop session).

**Host alias** so future logins are just `ssh <server-name>` — add to
`~/.ssh/config` (Windows: `C:\Users\<you>\.ssh\config`, no file extension):

```
Host <server-name>
    HostName <ip>
    User <user>
    Port <port>
    IdentityFile ~/.ssh/id_ed25519_<server-name>
```

On Windows the `IdentityFile` line may need the full path,
`C:\Users\<you>\.ssh\id_ed25519_<server-name>`.
