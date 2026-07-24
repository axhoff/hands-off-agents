# hands-off agents

keep remote coding agents available after logout, crashes, and server reboots.

each agent gets its own small, inspectable installer. no shared runtime and no
blind process killing.

| agent | installer | status |
| --- | --- | --- |
| codex | [`install-codex.sh`](./install-codex.sh) | ready |
| claude | `install-claude.sh` | planned |

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
