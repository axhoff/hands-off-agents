#!/usr/bin/env bash
set -Eeuo pipefail

service_name="codex-remote-control.service"
service_dir="${HOME}/.config/systemd/user"
service_file="${service_dir}/${service_name}"
pair_after_install=false
temporary_daemon_started=false
unit_tmp=""

say() {
  printf '==> %s\n' "$*"
}

warn() {
  printf 'warning: %s\n' "$*" >&2
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
usage: install-codex.sh [--pair]

installs codex remote control as a persistent systemd user service.

options:
  --pair  create a short-lived pairing code after installation
  -h      show this help
EOF
}

cleanup() {
  if [[ -n "${unit_tmp}" && -e "${unit_tmp}" ]]; then
    rm -f -- "${unit_tmp}"
  fi

  if [[ "${temporary_daemon_started}" == true ]]; then
    "${codex_bin}" remote-control stop >/dev/null 2>&1 || true
  fi
}

trap cleanup EXIT

while (($#)); do
  case "$1" in
    --pair)
      pair_after_install=true
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
  shift
done

[[ "$(uname -s)" == Linux ]] || die "this installer supports linux only"
((EUID != 0)) || die "run this as your normal user, not root"

for command_name in systemctl loginctl journalctl sed install mktemp; do
  command -v "${command_name}" >/dev/null 2>&1 ||
    die "required command not found: ${command_name}"
done

if command -v codex >/dev/null 2>&1; then
  codex_bin="$(command -v codex)"
elif [[ -x "${HOME}/.local/bin/codex" ]]; then
  codex_bin="${HOME}/.local/bin/codex"
elif [[ -x "${HOME}/.codex/packages/standalone/current/codex" ]]; then
  codex_bin="${HOME}/.codex/packages/standalone/current/codex"
else
  die "codex was not found; install it and make sure it is on PATH"
fi

systemctl --user show-environment >/dev/null 2>&1 ||
  die "the systemd user manager is unavailable"

say "checking chatgpt authentication"
login_status="$("${codex_bin}" login status 2>&1)" || {
  printf '%s\n' "${login_status}" >&2
  die "codex login check failed"
}
printf '%s\n' "${login_status}"
grep -qi 'logged in using chatgpt' <<<"${login_status}" ||
  die "remote control requires a chatgpt login; run: codex login --device-auth"

current_user="$(id -un)"
linger="$(loginctl show-user "${current_user}" -p Linger --value 2>/dev/null || true)"
if [[ "${linger}" != yes ]]; then
  command -v sudo >/dev/null 2>&1 ||
    die "user lingering is disabled and sudo is unavailable; ask an admin to run: loginctl enable-linger ${current_user}"
  say "enabling user services at boot (sudo may prompt)"
  sudo loginctl enable-linger "${current_user}"
else
  say "user lingering is already enabled"
fi

if systemctl --user is-active --quiet "${service_name}"; then
  say "stopping the existing systemd service"
  systemctl --user stop "${service_name}"
fi

say "starting remote control once to discover the managed codex binary"
if ! start_json="$("${codex_bin}" remote-control start --json)"; then
  printf '%s\n' "${start_json:-}" >&2
  die "remote control could not start; stop any competing ssh-launched app-server and retry"
fi
temporary_daemon_started=true

parse_managed_path() {
  local json="$1"

  if command -v jq >/dev/null 2>&1; then
    jq -er '.daemon.managedCodexPath // empty' <<<"${json}" 2>/dev/null && return
  fi

  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json,sys; print(json.load(sys.stdin)["daemon"]["managedCodexPath"])' \
      <<<"${json}" 2>/dev/null && return
  fi

  sed -n 's/.*"managedCodexPath"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
    <<<"${json}"
}

managed_codex_path="$(parse_managed_path "${start_json}")"
[[ -n "${managed_codex_path}" ]] ||
  die "could not read managedCodexPath from codex output"
[[ "${managed_codex_path}" == /* ]] ||
  die "codex returned a non-absolute managed path"
[[ -x "${managed_codex_path}" ]] ||
  die "managed codex binary is not executable: ${managed_codex_path}"
[[ "${managed_codex_path}" != *$'\n'* && "${managed_codex_path}" != *'"'* ]] ||
  die "managed codex path contains unsupported characters"

say "managed codex binary: ${managed_codex_path}"
say "stopping the temporary daemon"
"${codex_bin}" remote-control stop
temporary_daemon_started=false

mkdir -p -- "${service_dir}"

if [[ -f "${service_file}" ]] &&
   ! grep -q '^# installed by install-codex.sh$' "${service_file}"; then
  backup_file="${service_file}.backup.$(date -u +%Y%m%dT%H%M%SZ)"
  cp -- "${service_file}" "${backup_file}"
  warn "backed up the existing service to ${backup_file}"
fi

unit_tmp="$(mktemp "${service_file}.tmp.XXXXXX")"
cat >"${unit_tmp}" <<EOF
# installed by install-codex.sh
[Unit]
Description=Codex Remote Control
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
WorkingDirectory=%h
ExecStart="${managed_codex_path}" remote-control
Restart=always
RestartSec=5
TimeoutStopSec=30

[Install]
WantedBy=default.target
EOF

install -m 0644 "${unit_tmp}" "${service_file}"
rm -f -- "${unit_tmp}"
unit_tmp=""

say "enabling and starting ${service_name}"
systemctl --user daemon-reload
systemctl --user enable --now "${service_name}"

connected=false
for _ in {1..30}; do
  if journalctl --user -u "${service_name}" -n 30 --no-pager 2>/dev/null |
     grep -q 'available for remote control'; then
    connected=true
    break
  fi

  if ! systemctl --user is-active --quiet "${service_name}"; then
    sleep 1
    continue
  fi

  sleep 1
done

if [[ "${connected}" == true ]]; then
  say "remote control is connected and persistent"
elif systemctl --user is-active --quiet "${service_name}"; then
  warn "the service is active, but relay connection was not confirmed within 30 seconds"
else
  systemctl --user status "${service_name}" --no-pager || true
  journalctl --user -u "${service_name}" -n 50 --no-pager || true
  die "the service did not stay active"
fi

printf '\nuseful commands:\n'
printf '  systemctl --user status %s\n' "${service_name}"
printf '  systemctl --user restart %s\n' "${service_name}"
printf '  journalctl --user -u %s -f\n' "${service_name}"

if [[ "${pair_after_install}" == true ]]; then
  printf '\n'
  "${codex_bin}" remote-control pair
else
  printf '\npair a device with:\n'
  printf '  codex remote-control pair\n'
fi
