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
- codex installed and authenticated with a chatgpt account
- `sudo` access if user lingering is not already enabled

### install

download and inspect the script:

```bash
wget -q https://raw.githubusercontent.com/axhoff/hands-off-agents/main/install-codex.sh
less install-codex.sh
bash install-codex.sh --pair
```

the installer:

- checks the platform, systemd, and chatgpt authentication
- enables user lingering so services start without an ssh login
- discovers codex's managed standalone binary
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

## claude

the claude code desktop app connects to remote hosts over ssh, multiplexes
several exec channels over one connection, and deploys its own server binary
into the user's home directory. persistence is handled by the app itself (it
leaves a daemon running and redeploys on reconnect), so unlike codex there is
no service to install — but a hardened host breaks the connection with one
generic error: *"couldn't run a command on the remote"*.

the usual culprit is `MaxSessions 2` in a hardened sshd config: the first
couple of channels (probe, version check) fit, the one that launches the
server is refused.

### requirements

- linux (amd64/arm64) with an openssh server
- `sudo` access for sshd checks and fixes
- run as the user the app connects as, on the remote host

### install

download and inspect the script:

```bash
wget -q https://raw.githubusercontent.com/axhoff/hands-off-agents/main/install-claude.sh
less install-claude.sh
bash install-claude.sh
```

or report-only, changing nothing:

```bash
bash install-claude.sh --check
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

## license

mit
