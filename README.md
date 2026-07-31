# hands-off agents

keep remote coding agents available after logout, crashes, and server reboots.

each agent gets its own small, inspectable installer. no shared runtime and no
blind process killing.

| agent | installer | status |
| --- | --- | --- |
| codex | [`install-codex.sh`](./install-codex.sh) | ready |
| claude | [`install-claude.sh`](./install-claude.sh) | ready |

## codex

### requirements

- linux with systemd user services
- internet access; `curl` or `wget` is needed only when codex is missing
- `sudo` access if user lingering is not already enabled

### install

download and inspect the script:

```bash
wget -q https://raw.githubusercontent.com/axhoff/hands-off-agents/main/install-codex.sh
less install-codex.sh
bash install-codex.sh --pair
```

the installer:

- installs codex with openai's official standalone installer when it is missing
- guides chatgpt device login and leaves the browser link and one-time code
  visible
- checks the platform, systemd, and chatgpt authentication
- enables user lingering so services start without an ssh login
- discovers codex's managed standalone binary
- retries a failed relay enrollment after a clean daemon stop and reports
  `codex doctor` diagnostics if recovery fails
- replaces the temporary pid daemon with a systemd user service
- backs up an existing service file before replacing it
- enables restart-on-failure and startup after reboot
- waits for the remote relay connection
- optionally prints a short-lived device pairing code

### manage

```bash
systemctl --user status codex-remote-control.service
systemctl --user restart codex-remote-control.service
journalctl --user -u codex-remote-control.service -f
```

if setup reports an errored connection, the installer now attempts the common
stop/start recovery three times. persistent failures usually need a refreshed
chatgpt device login, mfa, workspace remote-control permission, or outbound
https access—not manual deletion of codex state files.

## claude

the installer prepares desktop-over-ssh access, completes claude.ai login when
needed, then starts claude code remote control. the login flow displays any
one-time code directly in the terminal. remote control then displays a session
url; press space to show its qr code for the claude mobile app.

remote control runs locally and connects outward over https. keep the
`claude remote-control` process running while using it from claude.ai/code or
the mobile app.

the usual culprit is `MaxSessions 2` in a hardened sshd config: the first
couple of channels (probe, version check) fit, the one that launches the
server is refused.

### requirements

- linux (amd64/arm64) with an openssh server
- `sudo` access for sshd checks and fixes
- claude code v2.1.51 or later
- a claude.ai subscription login; api-key authentication is not supported
- permission to trust the selected project directory when claude first opens it
- run as the user the app connects as, on the remote host

### install

download and inspect the script:

```bash
wget -q https://raw.githubusercontent.com/axhoff/hands-off-agents/main/install-claude.sh
less install-claude.sh
bash install-claude.sh
```

the guided finish will:

1. run `claude auth login --claudeai` when needed, leaving the login url and
   one-time code visible in your terminal
2. ask whether to start remote control
3. run `claude remote-control`, which displays the session url
4. let you press space to display the qr code for your phone

run it from the project directory you want to expose, or specify one:

```bash
bash install-claude.sh --project ~/src/my-project --name "my server"
```

or report-only, changing nothing:

```bash
bash install-claude.sh --check
```

prepare desktop-over-ssh access without starting remote control:

```bash
bash install-claude.sh --prepare-only
```

the script:

- checks architecture, home writability, `noexec` mounts, and disk space
- checks that shell rc files stay silent for non-interactive ssh commands
- puts `claude` on the non-interactive PATH (above any interactivity guard)
- checks sshd for `ForceCommand`, `PermitTTY`, restricted `authorized_keys`
- raises `MaxSessions` to 10 where a hardened config lowered it, editing only
  the global section and never touching `Match` blocks
- backs up every file it edits, validates with `sshd -t` before reloading,
  and rolls everything back automatically if validation or reload fails
- checks the remote-control cli version and incompatible auth/provider vars
- guides claude.ai login without capturing the one-time code
- launches server mode and leaves the session url and qr code visible

### troubleshoot

the app's client-side log on the mac names the failing step:

```bash
tail -40 ~/Library/Logs/Claude/ssh.log
```

`exec channel open failed` after a successful auth is the `MaxSessions`
symptom. an `AllowTcpForwarding no` warning from the script can be ignored
until everything else checks out.

## important

- use one app-server owner per host
- don't run a separate ssh-launched codex app-server beside this service
- don't use broad commands such as `pkill codex`
- the host must remain powered on and connected to the internet
- codex remote control is currently experimental

see the official
[remote connections documentation](https://learn.chatgpt.com/docs/remote-connections).

claude setup follows the official
[remote control documentation](https://code.claude.com/docs/en/remote-control).

## license

mit
