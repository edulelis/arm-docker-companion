#!/bin/sh
set -eu

PROJECT_NAME="arm-docker-companion"
SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)

ENV_FILE=${ENV_FILE:-"$SCRIPT_DIR/.env"}
if [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC1090
  . "$ENV_FILE"
fi

DOCKER_CONTEXT_NAME=${DOCKER_CONTEXT_NAME:-arm-companion}
COMPANION_HOST=${COMPANION_HOST:-}
COMPANION_HOST_FALLBACKS=${COMPANION_HOST_FALLBACKS:-}
COMPANION_USER=${COMPANION_USER:-}
COMPANION_SSH_ALIAS=${COMPANION_SSH_ALIAS:-$DOCKER_CONTEXT_NAME}
COMPANION_SSH_HOST=${COMPANION_SSH_HOST:-}
COMPANION_SSH_IDENTITY_FILE=${COMPANION_SSH_IDENTITY_FILE:-}
COMPANION_DOCKER_ENDPOINT=${COMPANION_DOCKER_ENDPOINT:-}
COMPANION_DOCKER_ENDPOINT_FALLBACKS=${COMPANION_DOCKER_ENDPOINT_FALLBACKS:-}

INSTALL_HOMEBREW=${INSTALL_HOMEBREW:-0}
WRITE_SHELL_PROFILE=${WRITE_SHELL_PROFILE:-0}
SHELL_PROFILE=${SHELL_PROFILE:-"$HOME/.zshrc"}
START_COLIMA=${START_COLIMA:-0}
COLIMA_CPU=${COLIMA_CPU:-4}
COLIMA_MEMORY=${COLIMA_MEMORY:-8}
COLIMA_DISK=${COLIMA_DISK:-60}
ENABLE_MAC_NFS_EXPORT=${ENABLE_MAC_NFS_EXPORT:-0}
MAC_NFS_EXPORT_PATH=${MAC_NFS_EXPORT_PATH:-}
MAC_NFS_CLIENTS=${MAC_NFS_CLIENTS:-}

CONFIGURE_DOCKER_DAEMON=${CONFIGURE_DOCKER_DAEMON:-1}
DOCKER_APT_OS=${DOCKER_APT_OS:-}
DOCKER_APT_SUITE=${DOCKER_APT_SUITE:-}
COMPANION_DOCKER_DATA_ROOT=${COMPANION_DOCKER_DATA_ROOT:-/var/lib/docker}
DOCKER_LOG_MAX_SIZE=${DOCKER_LOG_MAX_SIZE:-100m}
DOCKER_LOG_MAX_FILE=${DOCKER_LOG_MAX_FILE:-3}
ENABLE_DOCKER_STORAGE_GUARD=${ENABLE_DOCKER_STORAGE_GUARD:-0}
DOCKER_STORAGE_GUARD_INTERVAL_SECONDS=${DOCKER_STORAGE_GUARD_INTERVAL_SECONDS:-15}
ENABLE_USB_STORAGE_POWER_POLICY=${ENABLE_USB_STORAGE_POWER_POLICY:-0}
USB_STORAGE_BRIDGE_VENDOR_ID=${USB_STORAGE_BRIDGE_VENDOR_ID:-}
USB_STORAGE_BRIDGE_PRODUCT_ID=${USB_STORAGE_BRIDGE_PRODUCT_ID:-}
ENABLE_USB_STORAGE_RECOVERY_REBOOT=${ENABLE_USB_STORAGE_RECOVERY_REBOOT:-0}
USB_STORAGE_RECOVERY_MIN_UPTIME_SECONDS=${USB_STORAGE_RECOVERY_MIN_UPTIME_SECONDS:-180}
USB_STORAGE_RECOVERY_REBOOT_COOLDOWN_SECONDS=${USB_STORAGE_RECOVERY_REBOOT_COOLDOWN_SECONDS:-21600}

CONFIGURE_STORAGE_MOUNT=${CONFIGURE_STORAGE_MOUNT:-0}
COMPANION_STORAGE_UUID=${COMPANION_STORAGE_UUID:-}
COMPANION_STORAGE_MOUNT=${COMPANION_STORAGE_MOUNT:-/mnt/companion-ssd}
COMPANION_STORAGE_FSTYPE=${COMPANION_STORAGE_FSTYPE:-ext4}

ENABLE_AVAHI_FIX=${ENABLE_AVAHI_FIX:-0}
AVAHI_ALLOW_INTERFACES=${AVAHI_ALLOW_INTERFACES:-}

ENABLE_NFS_CLIENT=${ENABLE_NFS_CLIENT:-0}
NFS_SERVER=${NFS_SERVER:-}
NFS_EXPORT=${NFS_EXPORT:-}
NFS_MOUNT=${NFS_MOUNT:-}
NFS_MOUNT_OPTIONS=${NFS_MOUNT_OPTIONS:-}
NFS_RECONCILE_MODE=${NFS_RECONCILE_MODE:-automount}
NFS_RECONCILE_INTERVAL_SECONDS=${NFS_RECONCILE_INTERVAL_SECONDS:-10}

ENABLE_LAN_DOCKER_PROXY=${ENABLE_LAN_DOCKER_PROXY:-0}
DOCKER_PROXY_BIND=${DOCKER_PROXY_BIND:-0.0.0.0}
DOCKER_PROXY_PORT=${DOCKER_PROXY_PORT:-23750}
DOCKER_PROXY_ALLOW_CIDR=${DOCKER_PROXY_ALLOW_CIDR:-}

CREATE_BUILDX_BUILDER=${CREATE_BUILDX_BUILDER:-1}
BUILDX_BUILDER_NAME=${BUILDX_BUILDER_NAME:-}
USE_DOCKER_CONTEXT=${USE_DOCKER_CONTEXT:-1}
DRY_RUN=${DRY_RUN:-0}
SSH_TTY_FLAGS=${SSH_TTY_FLAGS:--t}

DEV_TUNNEL_FORWARDS=${DEV_TUNNEL_FORWARDS:-}
DEV_TUNNEL_AUTO_DOCKER_PORTS=${DEV_TUNNEL_AUTO_DOCKER_PORTS:-1}
DEV_TUNNEL_PROJECT_ROOTS=${DEV_TUNNEL_PROJECT_ROOTS:-}
DEV_TUNNEL_MANIFEST_NAME=${DEV_TUNNEL_MANIFEST_NAME:-.arm-docker-companion-tunnels}
DEV_TUNNEL_STOP_COLIMA_CONFLICTS=${DEV_TUNNEL_STOP_COLIMA_CONFLICTS:-1}
DEV_TUNNEL_SKIP_BUSY_PORTS=${DEV_TUNNEL_SKIP_BUSY_PORTS:-1}
DEV_TUNNEL_SOFT_FAIL=${DEV_TUNNEL_SOFT_FAIL:-1}
DEV_TUNNEL_LAUNCHD_LABEL=${DEV_TUNNEL_LAUNCHD_LABEL:-com.arm-docker-companion.dev-tunnels}
DEV_TUNNEL_LOG_DIR=${DEV_TUNNEL_LOG_DIR:-"$HOME/Library/Logs"}
DEV_TUNNEL_LAUNCHD_PATH=${DEV_TUNNEL_LAUNCHD_PATH:-/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin}
DEV_TUNNEL_DOCKER_CONFIG=${DEV_TUNNEL_DOCKER_CONFIG:-"$HOME/.docker"}
DEV_TUNNEL_WATCH_INITIAL_SECONDS=${DEV_TUNNEL_WATCH_INITIAL_SECONDS:-5}
DEV_TUNNEL_WATCH_MAX_SECONDS=${DEV_TUNNEL_WATCH_MAX_SECONDS:-60}
DEV_TUNNEL_DOCKER_PROBE_TIMEOUT_SECONDS=${DEV_TUNNEL_DOCKER_PROBE_TIMEOUT_SECONDS:-5}
DEV_TUNNEL_ACTIVE_DOCKER_ENDPOINT=

export DOCKER_CONFIG="${DOCKER_CONFIG:-$DEV_TUNNEL_DOCKER_CONFIG}"

usage() {
  cat <<'EOF'
Usage:
  ./install.sh mac
  ./install.sh companion-remote
  ./install.sh companion-local
  ./install.sh mac-nfs-export
  ./install.sh context
  ./install.sh mac-dev-tunnels
  ./install.sh mac-dev-tunnels-watch
  ./install.sh mac-dev-tunnels-agent-install
  ./install.sh mac-dev-tunnels-agent-uninstall
  ./install.sh verify
  ./install.sh doctor
  ./install.sh all

Configuration:
  cp config/companion.env.example .env
  edit .env

Common flow from an ARM Mac:
  ./install.sh mac
  ./install.sh companion-remote
  ./install.sh context
  ./install.sh verify

Self-healing localhost ports for Mac-side tools that expect companion-published
container ports on localhost:
  ./install.sh mac-dev-tunnels
  ./install.sh mac-dev-tunnels-agent-install

Set ENV_FILE=/path/to/file to load another config file.
Set DRY_RUN=1 to print commands where supported.
EOF
}

log() {
  printf '%s\n' "[$PROJECT_NAME] $*"
}

die() {
  printf '%s\n' "[$PROJECT_NAME] error: $*" >&2
  exit 1
}

have() {
  command -v "$1" >/dev/null 2>&1
}

run() {
  if [ "$DRY_RUN" = "1" ]; then
    printf '+'
    printf ' %s' "$@"
    printf '\n'
  else
    "$@"
  fi
}

as_root() {
  if [ "$(id -u)" -eq 0 ]; then
    run "$@"
  else
    run sudo "$@"
  fi
}

require_var() {
  eval "value=\${$1:-}"
  [ -n "$value" ] || die "$1 is required"
}

backup_file() {
  if [ -f "$1" ] && [ "$DRY_RUN" != "1" ]; then
    as_root cp "$1" "$1.bak.$(date +%Y%m%d%H%M%S)"
  fi
}

install_root_file() {
  path=$1
  mode=${2:-0644}
  tmp=$(mktemp)
  cat > "$tmp"
  if [ "$DRY_RUN" = "1" ]; then
    log "would install $path"
    sed 's/^/  /' "$tmp"
    rm -f "$tmp"
    return
  fi
  as_root install -m "$mode" "$tmp" "$path"
  rm -f "$tmp"
}

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

shell_quote() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

xml_escape() {
  printf '%s' "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g'
}

remote_target() {
  host=$(companion_ssh_host)
  if [ -n "$COMPANION_USER" ]; then
    printf '%s@%s' "$COMPANION_USER" "$host"
  else
    printf '%s' "$host"
  fi
}

companion_ssh_host() {
  if [ -n "$COMPANION_SSH_HOST" ]; then
    printf '%s' "$COMPANION_SSH_HOST"
    return
  fi
  require_var COMPANION_HOST
  printf '%s' "$COMPANION_HOST"
}

mac_formulae() {
  printf '%s\n' git jq docker docker-buildx docker-compose colima lima socat coreutils shellcheck
}

brew_path() {
  if have brew; then
    command -v brew
    return
  fi
  if [ -x /opt/homebrew/bin/brew ]; then
    printf '%s\n' /opt/homebrew/bin/brew
    return
  fi
  return 1
}

install_homebrew_if_needed() {
  if brew_path >/dev/null 2>&1; then
    return
  fi
  [ "$INSTALL_HOMEBREW" = "1" ] || die "Homebrew is missing. Install it first or set INSTALL_HOMEBREW=1."
  have curl || die "curl is required to install Homebrew"
  if [ "$DRY_RUN" = "1" ]; then
    log "would install Homebrew from https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"
  else
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi
}

install_mac_formulae() {
  install_homebrew_if_needed
  brew_bin=$(brew_path || true)
  if [ -z "$brew_bin" ]; then
    [ "$DRY_RUN" = "1" ] || die "Homebrew was installed but brew is not on PATH; open a new shell and rerun"
    mac_formulae | while IFS= read -r formula; do
      run brew install "$formula"
    done
    return
  fi
  mac_formulae | while IFS= read -r formula; do
    if "$brew_bin" list --formula "$formula" >/dev/null 2>&1; then
      log "brew formula already installed: $formula"
    else
      run "$brew_bin" install "$formula"
    fi
  done
}

write_managed_block() {
  file=$1
  begin=$2
  end=$3
  block=$4
  mode=${5:-600}
  tmp=$(mktemp)
  if [ -f "$file" ]; then
    awk -v begin="$begin" -v end="$end" '
      $0 == begin { skip = 1; next }
      $0 == end { skip = 0; next }
      skip != 1 { print }
    ' "$file" > "$tmp"
  fi
  needs_blank=0
  [ -s "$tmp" ] && needs_blank=1
  {
    [ "$needs_blank" = "1" ] && printf '\n'
    printf '%s\n' "$begin"
    printf '%s\n' "$block"
    printf '%s\n' "$end"
  } >> "$tmp"
  if [ "$DRY_RUN" = "1" ]; then
    log "would update managed block in $file"
    {
      printf '%s\n' "$begin"
      printf '%s\n' "$block"
      printf '%s\n' "$end"
    } | sed 's/^/  /'
    rm -f "$tmp"
    return
  fi
  install -m "$mode" "$tmp" "$file"
  rm -f "$tmp"
}

configure_mac_ssh() {
  [ -n "$COMPANION_HOST" ] || return 0
  ssh_host=$(companion_ssh_host)
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
  identity_line=""
  if [ -n "$COMPANION_SSH_IDENTITY_FILE" ]; then
    identity_line="  IdentityFile $COMPANION_SSH_IDENTITY_FILE"
  fi
  user_line=""
  if [ -n "$COMPANION_USER" ]; then
    user_line="  User $COMPANION_USER"
  fi
  block=$(cat <<EOF
Host $COMPANION_SSH_ALIAS
  HostName $ssh_host
$user_line
$identity_line
  ControlMaster auto
  ControlPath ~/.ssh/cm-%r@%h:%p
  ControlPersist 300
  ServerAliveInterval 30
  ServerAliveCountMax 4
  PreferredAuthentications publickey
EOF
)
  write_managed_block "$HOME/.ssh/config" "# BEGIN arm-docker-companion" "# END arm-docker-companion" "$block"
}

configure_shell_profile() {
  [ "$WRITE_SHELL_PROFILE" = "1" ] || return 0
  block=$(cat <<'EOF'
export DOCKER_BUILDKIT=1
export COMPOSE_DOCKER_CLI_BUILD=1
EOF
)
  touch "$SHELL_PROFILE"
  write_managed_block "$SHELL_PROFILE" "# BEGIN arm-docker-companion" "# END arm-docker-companion" "$block" 0644
}

start_colima_if_requested() {
  [ "$START_COLIMA" = "1" ] || return 0
  have colima || die "colima is not installed"
  run colima start --cpu "$COLIMA_CPU" --memory "$COLIMA_MEMORY" --disk "$COLIMA_DISK"
}

configure_mac_nfs_export_if_requested() {
  [ "$ENABLE_MAC_NFS_EXPORT" = "1" ] || return 0
  cmd_mac_nfs_export
}

cmd_mac() {
  [ "$(uname -s)" = "Darwin" ] || die "mac command must run on macOS"
  [ "$(uname -m)" = "arm64" ] || die "this setup expects an ARM Mac"
  install_mac_formulae
  configure_mac_ssh
  configure_shell_profile
  configure_mac_nfs_export_if_requested
  start_colima_if_requested
  log "mac setup complete"
}

cmd_mac_nfs_export() {
  [ "$(uname -s)" = "Darwin" ] || die "mac-nfs-export must run on macOS"
  require_var MAC_NFS_EXPORT_PATH
  require_var MAC_NFS_CLIENTS
  [ -d "$MAC_NFS_EXPORT_PATH" ] || die "MAC_NFS_EXPORT_PATH does not exist: $MAC_NFS_EXPORT_PATH"
  case "$MAC_NFS_EXPORT_PATH" in
    *" "*) die "MAC_NFS_EXPORT_PATH with spaces is not supported by this installer" ;;
  esac
  uid=$(id -u)
  gid=$(id -g)
  export_line="$MAC_NFS_EXPORT_PATH -alldirs -mapall=$uid:$gid $MAC_NFS_CLIENTS"
  if [ -f /etc/exports ] && grep -F "$MAC_NFS_EXPORT_PATH " /etc/exports >/dev/null 2>&1; then
    log "NFS export already present for $MAC_NFS_EXPORT_PATH"
  else
    [ -f /etc/exports ] || as_root touch /etc/exports
    backup_file /etc/exports
    if [ "$DRY_RUN" = "1" ]; then
      log "would append to /etc/exports: $export_line"
    else
      printf '%s\n' "$export_line" | sudo tee -a /etc/exports >/dev/null
    fi
  fi
  as_root nfsd enable
  as_root nfsd restart
}

detect_docker_repo_os() {
  # shellcheck disable=SC1091
  . /etc/os-release
  if [ -n "$DOCKER_APT_OS" ]; then
    printf '%s' "$DOCKER_APT_OS"
    return
  fi
  os_id=${ID:-}
  os_like=${ID_LIKE:-}
  suite=${VERSION_CODENAME:-}
  if [ -n "${UBUNTU_CODENAME:-}" ]; then
    printf 'ubuntu'
    return
  fi
  if [ "$os_id" = "armbian" ]; then
    case "$suite" in
      noble|jammy|focal|bionic|plucky|questing|oracular|mantic|lunar|kinetic)
        printf 'ubuntu'
        return
        ;;
      trixie|bookworm|bullseye)
        printf 'debian'
        return
        ;;
    esac
  fi
  case " $os_id $os_like " in
    *ubuntu*) printf 'ubuntu' ;;
    *debian*) printf 'debian' ;;
    *) die "unsupported distro for Docker apt repo: ${PRETTY_NAME:-unknown}; set DOCKER_APT_OS and DOCKER_APT_SUITE" ;;
  esac
}

detect_docker_repo_suite() {
  # shellcheck disable=SC1091
  . /etc/os-release
  if [ -n "$DOCKER_APT_SUITE" ]; then
    printf '%s' "$DOCKER_APT_SUITE"
    return
  fi
  docker_os=$(detect_docker_repo_os)
  suite=${VERSION_CODENAME:-}
  if [ "$docker_os" = "ubuntu" ] && [ -n "${UBUNTU_CODENAME:-}" ]; then
    suite=$UBUNTU_CODENAME
  fi
  [ -n "$suite" ] || die "could not detect apt suite from /etc/os-release"
  printf '%s' "$suite"
}

install_companion_packages() {
  have apt-get || die "companion-local currently supports Debian/Ubuntu/Armbian apt hosts"
  as_root apt-get update
  as_root apt-get install -y ca-certificates curl gnupg lsb-release avahi-daemon nfs-common jq rsync socat
}

install_docker_engine() {
  docker_os=$(detect_docker_repo_os)
  docker_suite=$(detect_docker_repo_suite)
  arch=$(dpkg --print-architecture)

  as_root apt-get remove -y docker.io docker-doc docker-compose podman-docker containerd runc || true
  as_root install -m 0755 -d /etc/apt/keyrings
  tmp=$(mktemp)
  curl -fsSL "https://download.docker.com/linux/$docker_os/gpg" -o "$tmp"
  as_root install -m 0644 "$tmp" /etc/apt/keyrings/docker.asc
  rm -f "$tmp"

  install_root_file /etc/apt/sources.list.d/docker.sources 0644 <<EOF
Types: deb
URIs: https://download.docker.com/linux/$docker_os
Suites: $docker_suite
Components: stable
Architectures: $arch
Signed-By: /etc/apt/keyrings/docker.asc
EOF

  as_root apt-get update
  as_root apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  as_root systemctl enable --now docker
}

configure_storage_mount() {
  [ "$CONFIGURE_STORAGE_MOUNT" = "1" ] || return 0
  require_var COMPANION_STORAGE_UUID
  as_root mkdir -p "$COMPANION_STORAGE_MOUNT"
  line="UUID=$COMPANION_STORAGE_UUID $COMPANION_STORAGE_MOUNT $COMPANION_STORAGE_FSTYPE defaults,noatime,nofail,x-systemd.device-timeout=10s 0 2"
  if grep -F "UUID=$COMPANION_STORAGE_UUID " /etc/fstab >/dev/null 2>&1; then
    log "storage UUID already present in /etc/fstab"
  else
    backup_file /etc/fstab
    if [ "$DRY_RUN" = "1" ]; then
      log "would append to /etc/fstab: $line"
    else
      printf '%s\n' "$line" | sudo tee -a /etc/fstab >/dev/null
    fi
  fi
  as_root mount "$COMPANION_STORAGE_MOUNT" || true
}

configure_docker_daemon() {
  [ "$CONFIGURE_DOCKER_DAEMON" = "1" ] || return 0
  root_json=$(json_escape "$COMPANION_DOCKER_DATA_ROOT")
  max_size_json=$(json_escape "$DOCKER_LOG_MAX_SIZE")
  max_file_json=$(json_escape "$DOCKER_LOG_MAX_FILE")
  as_root mkdir -p "$COMPANION_DOCKER_DATA_ROOT" /etc/docker
  if [ "$COMPANION_DOCKER_DATA_ROOT" != "/var/lib/docker" ] &&
     [ -d /var/lib/docker ] &&
     [ ! -e "$COMPANION_DOCKER_DATA_ROOT/image" ]; then
    as_root systemctl stop docker || true
    as_root rsync -aHAX --numeric-ids /var/lib/docker/ "$COMPANION_DOCKER_DATA_ROOT/" || true
  fi
  backup_file /etc/docker/daemon.json
  install_root_file /etc/docker/daemon.json 0644 <<EOF
{
  "data-root": "$root_json",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "$max_size_json",
    "max-file": "$max_file_json"
  },
  "live-restore": true
}
EOF
  as_root systemctl restart docker
}

configure_usb_storage_power_policy() {
  case "$ENABLE_USB_STORAGE_POWER_POLICY" in
    0|1) ;;
    *) die "ENABLE_USB_STORAGE_POWER_POLICY must be 0 or 1" ;;
  esac
  [ "$ENABLE_USB_STORAGE_POWER_POLICY" = "1" ] || return 0
  if { [ -n "$USB_STORAGE_BRIDGE_VENDOR_ID" ] && [ -z "$USB_STORAGE_BRIDGE_PRODUCT_ID" ]; } ||
     { [ -z "$USB_STORAGE_BRIDGE_VENDOR_ID" ] && [ -n "$USB_STORAGE_BRIDGE_PRODUCT_ID" ]; }; then
    die "USB_STORAGE_BRIDGE_VENDOR_ID and USB_STORAGE_BRIDGE_PRODUCT_ID must be set together"
  fi

  install_root_file /usr/local/bin/arm-companion-usb-power-apply.sh 0755 <<'EOF'
#!/bin/sh
set -eu

mode=${1:-apply}

apply_power_policy() {
  if [ -w /sys/module/usbcore/parameters/autosuspend ]; then
    echo -1 >/sys/module/usbcore/parameters/autosuspend || true
  fi

  for dev in /sys/bus/usb/devices/*; do
    [ -d "$dev" ] || continue
    if [ -w "$dev/power/control" ]; then
      echo on >"$dev/power/control" || true
    fi
    if [ -w "$dev/power/autosuspend" ]; then
      echo -1 >"$dev/power/autosuspend" || true
    fi
  done
}

status() {
  printf 'usbcore.autosuspend=%s\n' "$(cat /sys/module/usbcore/parameters/autosuspend 2>/dev/null || echo missing)"
  for dev in /sys/bus/usb/devices/*; do
    [ -f "$dev/idVendor" ] || continue
    printf '%s vendor=%s product=%s power=%s autosuspend=%s\n' \
      "$(basename "$dev")" \
      "$(cat "$dev/idVendor" 2>/dev/null)" \
      "$(cat "$dev/idProduct" 2>/dev/null)" \
      "$(cat "$dev/power/control" 2>/dev/null || echo missing)" \
      "$(cat "$dev/power/autosuspend" 2>/dev/null || echo missing)"
  done
}

case "$mode" in
  apply|--apply)
    apply_power_policy
    status
    ;;
  status|--status)
    status
    ;;
  *)
    echo "usage: $0 [apply|status]" >&2
    exit 64
    ;;
esac
EOF

  install_root_file /etc/systemd/system/arm-companion-usb-power.service 0644 <<'EOF'
[Unit]
Description=Disable USB autosuspend for ARM companion storage reliability
After=systemd-udevd.service local-fs.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/arm-companion-usb-power-apply.sh apply

[Install]
WantedBy=multi-user.target
EOF

  install_root_file /etc/udev/rules.d/99-arm-companion-usb-power.rules 0644 <<'EOF'
ACTION=="add|change", SUBSYSTEM=="usb", TEST=="power/control", ATTR{power/control}="on"
ACTION=="add|change", SUBSYSTEM=="usb", TEST=="power/autosuspend", ATTR{power/autosuspend}="-1"
EOF

  if [ -n "$USB_STORAGE_BRIDGE_VENDOR_ID" ] && [ -n "$USB_STORAGE_BRIDGE_PRODUCT_ID" ]; then
    if [ "$ENABLE_DOCKER_STORAGE_GUARD" = "1" ]; then
      install_root_file /etc/udev/rules.d/99-arm-companion-usb-storage.rules 0644 <<EOF
ACTION=="add|change", SUBSYSTEM=="usb", ATTR{idVendor}=="$USB_STORAGE_BRIDGE_VENDOR_ID", ATTR{idProduct}=="$USB_STORAGE_BRIDGE_PRODUCT_ID", TEST=="power/control", ATTR{power/control}="on"
ACTION=="add|change", SUBSYSTEM=="usb", ATTR{idVendor}=="$USB_STORAGE_BRIDGE_VENDOR_ID", ATTR{idProduct}=="$USB_STORAGE_BRIDGE_PRODUCT_ID", TEST=="power/autosuspend", ATTR{power/autosuspend}="-1"
ACTION=="add|remove|change", SUBSYSTEM=="usb", ATTR{idVendor}=="$USB_STORAGE_BRIDGE_VENDOR_ID", ATTR{idProduct}=="$USB_STORAGE_BRIDGE_PRODUCT_ID", TAG+="systemd", ENV{SYSTEMD_WANTS}+="arm-companion-docker-storage-reconcile.service"
EOF
    else
      install_root_file /etc/udev/rules.d/99-arm-companion-usb-storage.rules 0644 <<EOF
ACTION=="add|change", SUBSYSTEM=="usb", ATTR{idVendor}=="$USB_STORAGE_BRIDGE_VENDOR_ID", ATTR{idProduct}=="$USB_STORAGE_BRIDGE_PRODUCT_ID", TEST=="power/control", ATTR{power/control}="on"
ACTION=="add|change", SUBSYSTEM=="usb", ATTR{idVendor}=="$USB_STORAGE_BRIDGE_VENDOR_ID", ATTR{idProduct}=="$USB_STORAGE_BRIDGE_PRODUCT_ID", TEST=="power/autosuspend", ATTR{power/autosuspend}="-1"
EOF
    fi
  fi

  as_root systemctl daemon-reload
  as_root udevadm control --reload
  as_root udevadm trigger --subsystem-match=usb || true
  as_root systemctl enable --now arm-companion-usb-power.service
  as_root systemctl start arm-companion-usb-power.service || true
}

configure_docker_storage_guard() {
  [ "$ENABLE_DOCKER_STORAGE_GUARD" = "1" ] || return 0
  require_var COMPANION_STORAGE_UUID
  require_var COMPANION_STORAGE_MOUNT
  require_var COMPANION_DOCKER_DATA_ROOT

  storage_uuid_q=$(shell_quote "$COMPANION_STORAGE_UUID")
  storage_mount_q=$(shell_quote "$COMPANION_STORAGE_MOUNT")
  docker_root_q=$(shell_quote "$COMPANION_DOCKER_DATA_ROOT")
  usb_recovery_reboot_q=$(shell_quote "$ENABLE_USB_STORAGE_RECOVERY_REBOOT")
  usb_recovery_min_uptime_q=$(shell_quote "$USB_STORAGE_RECOVERY_MIN_UPTIME_SECONDS")
  usb_recovery_cooldown_q=$(shell_quote "$USB_STORAGE_RECOVERY_REBOOT_COOLDOWN_SECONDS")

  case "$ENABLE_USB_STORAGE_RECOVERY_REBOOT" in
    0|1) ;;
    *) die "ENABLE_USB_STORAGE_RECOVERY_REBOOT must be 0 or 1" ;;
  esac
  case "$USB_STORAGE_RECOVERY_MIN_UPTIME_SECONDS" in
    ''|*[!0-9]*) die "USB_STORAGE_RECOVERY_MIN_UPTIME_SECONDS must be a non-negative integer" ;;
  esac
  case "$USB_STORAGE_RECOVERY_REBOOT_COOLDOWN_SECONDS" in
    ''|*[!0-9]*) die "USB_STORAGE_RECOVERY_REBOOT_COOLDOWN_SECONDS must be a non-negative integer" ;;
  esac

  as_root mkdir -p "$COMPANION_STORAGE_MOUNT" "$COMPANION_DOCKER_DATA_ROOT" /etc/systemd/system/docker.service.d

  install_root_file /usr/local/bin/arm-companion-docker-storage-guard.sh 0755 <<EOF
#!/bin/sh
set -eu

mode=\${1:-pre-start}
expected_uuid=$storage_uuid_q
storage_mount=$storage_mount_q
docker_root=$docker_root_q
enable_usb_recovery_reboot=$usb_recovery_reboot_q
usb_recovery_min_uptime_seconds=$usb_recovery_min_uptime_q
usb_recovery_reboot_cooldown_seconds=$usb_recovery_cooldown_q
state_dir=/var/lib/arm-docker-companion
usb_recovery_reboot_mark=\$state_dir/usb-storage-reboot

device_present() {
  [ -e "/dev/disk/by-uuid/\$expected_uuid" ]
}

storage_mount_unit() {
  systemd-escape --path --suffix=mount "\$storage_mount"
}

mounted_uuid_ok() {
  if ! findmnt -rn -T "\$storage_mount" >/dev/null 2>&1; then
    return 1
  fi
  source_device=\$(findmnt -rn -o SOURCE -T "\$storage_mount" 2>/dev/null || true)
  actual_uuid=\$(blkid -s UUID -o value "\$source_device" 2>/dev/null || true)
  [ -n "\$actual_uuid" ] && [ "\$actual_uuid" = "\$expected_uuid" ]
}

ensure_storage_mount() {
  mkdir -p "\$storage_mount"
  if mounted_uuid_ok; then
    return 0
  fi
  if findmnt -rn -T "\$storage_mount" >/dev/null 2>&1; then
    umount -lf "\$storage_mount" >/dev/null 2>&1 || true
  fi
  unit=\$(storage_mount_unit)
  systemctl start "\$unit" >/dev/null 2>&1 || mount "\$storage_mount" >/dev/null 2>&1 || true
  mounted_uuid_ok
}

docker_root_ok() {
  mkdir -p "\$docker_root"
  if ! findmnt -rn -T "\$docker_root" >/dev/null 2>&1; then
    return 1
  fi
  source_device=\$(findmnt -rn -o SOURCE -T "\$docker_root" 2>/dev/null || true)
  actual_uuid=\$(blkid -s UUID -o value "\$source_device" 2>/dev/null || true)
  [ -n "\$actual_uuid" ] && [ "\$actual_uuid" = "\$expected_uuid" ]
}

uptime_seconds() {
  awk '{print int(\$1)}' /proc/uptime 2>/dev/null || echo 0
}

recent_usb_enumeration_failure() {
  journalctl -k -b --since "10 minutes ago" --no-pager 2>/dev/null |
    grep -Eq 'usb (usb[0-9]+-port[0-9]+|[0-9]+-[0-9]+):.*(Cannot enable|device descriptor read|not accepting address|unable to enumerate)'
}

maybe_reboot_for_usb_storage() {
  [ "\$enable_usb_recovery_reboot" = "1" ] || return 0

  uptime=\$(uptime_seconds)
  if [ "\$uptime" -lt "\$usb_recovery_min_uptime_seconds" ]; then
    echo "arm-docker-companion: storage absent; deferring USB recovery reboot until uptime exceeds \${usb_recovery_min_uptime_seconds}s" >&2
    return 0
  fi

  if ! recent_usb_enumeration_failure; then
    return 0
  fi

  now=\$(date +%s)
  last=0
  if [ -r "\$usb_recovery_reboot_mark" ]; then
    last=\$(cat "\$usb_recovery_reboot_mark" 2>/dev/null || echo 0)
  fi
  case "\$last" in
    ''|*[!0-9]*) last=0 ;;
  esac

  if [ \$((now - last)) -lt "\$usb_recovery_reboot_cooldown_seconds" ]; then
    echo "arm-docker-companion: storage absent with USB enumeration failures; reboot already attempted within cooldown" >&2
    return 0
  fi

  mkdir -p "\$state_dir"
  printf '%s\n' "\$now" >"\$usb_recovery_reboot_mark"
  sync
  echo "arm-docker-companion: storage absent with USB enumeration failures; rebooting to recover USB storage" >&2
  systemctl reboot --no-wall >/dev/null 2>&1 || shutdown -r now >/dev/null 2>&1 || true
}

pre_start() {
  if ! device_present; then
    echo "arm-docker-companion: storage UUID \$expected_uuid is absent; refusing Docker start" >&2
    return 42
  fi
  if ! ensure_storage_mount; then
    echo "arm-docker-companion: \$storage_mount is not mounted from UUID \$expected_uuid" >&2
    return 43
  fi
  if ! docker_root_ok; then
    echo "arm-docker-companion: \$docker_root is not on the expected storage device" >&2
    return 44
  fi
}

reconcile() {
  if device_present && ensure_storage_mount && docker_root_ok; then
    systemctl start docker.service >/dev/null 2>&1 || true
    exit 0
  fi

  systemctl stop docker.service >/dev/null 2>&1 || true
  if ! device_present; then
    maybe_reboot_for_usb_storage
  fi
  exit 0
}

status() {
  echo "storage_uuid=\$expected_uuid"
  echo "device_present=\$(device_present && echo yes || echo no)"
  echo "storage_mount=\$(findmnt -rn -o SOURCE,TARGET,OPTIONS -T "\$storage_mount" 2>/dev/null || echo missing)"
  echo "docker_root=\$(findmnt -rn -o SOURCE,TARGET,OPTIONS -T "\$docker_root" 2>/dev/null || echo missing)"
  echo "usb_recovery_reboot=\$enable_usb_recovery_reboot"
  echo "usb_recovery_reboot_last=\$(cat "\$usb_recovery_reboot_mark" 2>/dev/null || echo never)"
}

case "\$mode" in
  pre-start|--pre-start)
    pre_start
    ;;
  reconcile|--reconcile)
    reconcile
    ;;
  status|--status)
    status
    ;;
  *)
    echo "usage: \$0 [pre-start|reconcile|status]" >&2
    exit 64
    ;;
esac
EOF

  install_root_file /etc/systemd/system/docker.service.d/arm-companion-storage-guard.conf 0644 <<EOF
[Unit]
After=local-fs.target
RequiresMountsFor=$COMPANION_STORAGE_MOUNT $COMPANION_DOCKER_DATA_ROOT

[Service]
ExecStartPre=/usr/local/bin/arm-companion-docker-storage-guard.sh pre-start
Restart=on-failure
RestartSec=5
StartLimitIntervalSec=0
EOF

  install_root_file /etc/systemd/system/arm-companion-docker-storage-reconcile.service 0644 <<'EOF'
[Unit]
Description=Reconcile Docker with companion storage availability
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/arm-companion-docker-storage-guard.sh reconcile
EOF

  install_root_file /etc/systemd/system/arm-companion-docker-storage-reconcile.timer 0644 <<EOF
[Unit]
Description=Periodically reconcile Docker with companion storage availability

[Timer]
OnBootSec=20s
OnUnitActiveSec=${DOCKER_STORAGE_GUARD_INTERVAL_SECONDS}s
AccuracySec=3s
Unit=arm-companion-docker-storage-reconcile.service

[Install]
WantedBy=timers.target
EOF

  as_root systemctl daemon-reload
  as_root systemctl disable --now docker.socket || true
  as_root systemctl enable --now arm-companion-docker-storage-reconcile.timer
  as_root systemctl start arm-companion-docker-storage-reconcile.service || true
}

configure_avahi() {
  [ "$ENABLE_AVAHI_FIX" = "1" ] || return 0
  require_var AVAHI_ALLOW_INTERFACES
  file=/etc/avahi/avahi-daemon.conf
  tmp=$(mktemp)
  backup_file "$file"
  awk -v ifs="$AVAHI_ALLOW_INTERFACES" '
    BEGIN { in_server = 0; done = 0 }
    /^\[server\]/ { print; in_server = 1; next }
    in_server == 1 && /^\[/ {
      if (done == 0) { print "allow-interfaces=" ifs; done = 1 }
      in_server = 0
    }
    in_server == 1 && /^allow-interfaces=/ {
      if (done == 0) { print "allow-interfaces=" ifs; done = 1 }
      next
    }
    { print }
    END {
      if (done == 0) {
        if (in_server == 0) { print "[server]" }
        print "allow-interfaces=" ifs
      }
    }
  ' "$file" > "$tmp"
  if [ "$DRY_RUN" = "1" ]; then
    log "would update $file"
    sed 's/^/  /' "$tmp"
    rm -f "$tmp"
  else
    as_root install -m 0644 "$tmp" "$file"
    rm -f "$tmp"
    as_root systemctl restart avahi-daemon
  fi
}

configure_nfs_client() {
  [ "$ENABLE_NFS_CLIENT" = "1" ] || return 0
  require_var NFS_SERVER
  require_var NFS_EXPORT
  require_var NFS_MOUNT
  case "$NFS_RECONCILE_MODE" in
    automount|direct) ;;
    *) die "NFS_RECONCILE_MODE must be automount or direct" ;;
  esac
  as_root mkdir -p "$NFS_MOUNT"

  if [ -n "$NFS_MOUNT_OPTIONS" ]; then
    nfs_mount_options=$NFS_MOUNT_OPTIONS
  else
    case "$NFS_RECONCILE_MODE" in
      direct)
        nfs_mount_options=rw,soft,timeo=50,retrans=2,nolock,_netdev,nofail,x-systemd.mount-timeout=10
        ;;
      *)
        nfs_mount_options=rw,hard,intr,_netdev,nofail,x-systemd.automount,x-systemd.idle-timeout=60
        ;;
    esac
  fi

  line="$NFS_SERVER:$NFS_EXPORT $NFS_MOUNT nfs4 $nfs_mount_options 0 0"
  if [ "$DRY_RUN" = "1" ]; then
    log "would replace or append in /etc/fstab: $line"
  else
    backup_file /etc/fstab
    tmp=$(mktemp)
    awk -v mountpoint="$NFS_MOUNT" '$2 != mountpoint { print }' /etc/fstab > "$tmp"
    printf '%s\n' "$line" >> "$tmp"
    sudo install -m 0644 "$tmp" /etc/fstab
    rm -f "$tmp"
  fi

  mount_json=$(shell_quote "$NFS_MOUNT")
  export_json=$(shell_quote "$NFS_SERVER:$NFS_EXPORT")

  if [ "$NFS_RECONCILE_MODE" = "direct" ]; then
    install_root_file /usr/local/bin/arm-companion-nfs-reconcile.sh 0755 <<EOF
#!/bin/sh
set -eu
mount_point=$mount_json
expected_export=$export_json
check_timeout=${NFS_RECONCILE_INTERVAL_SECONDS}

mounted() {
  findmnt -rn -M "\$mount_point" >/dev/null 2>&1
}

mounted_source_ok() {
  mounted || return 1
  source_mount=\$(findmnt -rn -o SOURCE -M "\$mount_point" 2>/dev/null || true)
  [ "\$source_mount" = "\$expected_export" ]
}

responding() {
  timeout "\$check_timeout" ls "\$mount_point" >/dev/null 2>&1
}

start_mount() {
  mount_unit=\$(systemd-escape --path --suffix=mount "\$mount_point")
  mkdir -p "\$mount_point"
  systemctl start "\$mount_unit" >/dev/null 2>&1 || mount "\$mount_point" >/dev/null 2>&1
}

stop_mount() {
  mount_unit=\$(systemd-escape --path --suffix=mount "\$mount_point")
  systemctl stop "\$mount_unit" >/dev/null 2>&1 || true
  umount -lf "\$mount_point" >/dev/null 2>&1 || true
}

if mounted_source_ok && responding; then
  exit 0
fi
if mounted; then
  stop_mount
fi
start_mount
if mounted_source_ok && responding; then
  exit 0
fi
exit 1
EOF

    install_root_file /etc/systemd/system/arm-companion-nfs-reconcile.service 0644 <<'EOF'
[Unit]
Description=Reconcile ARM companion NFS bind source when it becomes stale
After=network-online.target

[Service]
Type=oneshot
TimeoutStartSec=30
ExecStart=/usr/local/bin/arm-companion-nfs-reconcile.sh
EOF

    install_root_file /etc/systemd/system/arm-companion-nfs-reconcile.timer 0644 <<EOF
[Unit]
Description=Run ARM companion NFS reconcile watchdog

[Timer]
OnBootSec=30s
OnUnitActiveSec=${NFS_RECONCILE_INTERVAL_SECONDS}s
AccuracySec=2s
Unit=arm-companion-nfs-reconcile.service

[Install]
WantedBy=timers.target
EOF
    as_root systemctl daemon-reload
    mount_unit=$(systemd-escape --path --suffix=mount "$NFS_MOUNT")
    automount_unit=$(systemd-escape --path --suffix=automount "$NFS_MOUNT")
    as_root systemctl disable --now arm-companion-nfs-remount.timer || true
    as_root systemctl stop arm-companion-nfs-remount.service "$automount_unit" "$mount_unit" || true
    as_root umount -lf "$NFS_MOUNT" || true
    as_root systemctl enable --now arm-companion-nfs-reconcile.timer
    as_root systemctl start arm-companion-nfs-reconcile.service || true
    return 0
  fi

  install_root_file /usr/local/bin/arm-companion-nfs-remount.sh 0755 <<EOF
#!/bin/sh
set -eu
mount_point=$mount_json
log_file=/var/log/arm-companion-nfs-remount.log
if mountpoint -q "\$mount_point"; then
  if timeout 2 stat "\$mount_point" >/dev/null 2>&1; then
    exit 0
  fi
  umount -fl "\$mount_point" >>"\$log_file" 2>&1 || true
fi
mount "\$mount_point" >>"\$log_file" 2>&1 || true
EOF

  install_root_file /etc/systemd/system/arm-companion-nfs-remount.service 0644 <<'EOF'
[Unit]
Description=Remount ARM companion NFS bind source when it becomes stale
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/arm-companion-nfs-remount.sh
EOF

  install_root_file /etc/systemd/system/arm-companion-nfs-remount.timer 0644 <<EOF
[Unit]
Description=Run ARM companion NFS remount watchdog

[Timer]
OnBootSec=30s
OnUnitActiveSec=${NFS_RECONCILE_INTERVAL_SECONDS}s
AccuracySec=2s
Unit=arm-companion-nfs-remount.service

[Install]
WantedBy=timers.target
EOF
  as_root systemctl daemon-reload
  as_root systemctl disable --now arm-companion-nfs-reconcile.timer || true
  as_root systemctl enable --now arm-companion-nfs-remount.timer
}

configure_lan_docker_proxy() {
  [ "$ENABLE_LAN_DOCKER_PROXY" = "1" ] || return 0
  log "WARNING: exposing the Docker socket over TCP gives clients root-equivalent control of this host."
  install_root_file /etc/systemd/system/arm-companion-docker-proxy.service 0644 <<EOF
[Unit]
Description=ARM companion Docker socket LAN proxy
Requires=docker.service
After=network-online.target docker.service

[Service]
Type=simple
ExecStart=/usr/bin/socat TCP-LISTEN:$DOCKER_PROXY_PORT,bind=$DOCKER_PROXY_BIND,fork,reuseaddr UNIX-CONNECT:/var/run/docker.sock
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF
  as_root systemctl daemon-reload
  as_root systemctl enable --now arm-companion-docker-proxy.service
  if [ -n "$DOCKER_PROXY_ALLOW_CIDR" ] && have ufw; then
    as_root ufw allow from "$DOCKER_PROXY_ALLOW_CIDR" to any port "$DOCKER_PROXY_PORT" proto tcp || true
  fi
}

cmd_companion_local() {
  [ "$(uname -s)" = "Linux" ] || die "companion-local must run on Linux"
  case "$(uname -m)" in
    aarch64|arm64) ;;
    *) die "this setup expects an ARM64/aarch64 companion" ;;
  esac
  install_companion_packages
  install_docker_engine
  configure_usb_storage_power_policy
  configure_storage_mount
  configure_docker_daemon
  configure_docker_storage_guard
  target_user=${SUDO_USER:-$(id -un)}
  as_root groupadd -f docker
  as_root usermod -aG docker "$target_user" || true
  configure_avahi
  configure_nfs_client
  configure_lan_docker_proxy
  as_root systemctl enable --now docker
  log "companion setup complete. Open a new SSH session for docker group membership to apply."
}

remote_env_pairs() {
  for name in \
    DOCKER_CONTEXT_NAME CONFIGURE_DOCKER_DAEMON DOCKER_APT_OS \
    DOCKER_APT_SUITE COMPANION_DOCKER_DATA_ROOT DOCKER_LOG_MAX_SIZE \
    DOCKER_LOG_MAX_FILE ENABLE_DOCKER_STORAGE_GUARD \
    DOCKER_STORAGE_GUARD_INTERVAL_SECONDS ENABLE_USB_STORAGE_POWER_POLICY \
    USB_STORAGE_BRIDGE_VENDOR_ID USB_STORAGE_BRIDGE_PRODUCT_ID \
    ENABLE_USB_STORAGE_RECOVERY_REBOOT \
    USB_STORAGE_RECOVERY_MIN_UPTIME_SECONDS USB_STORAGE_RECOVERY_REBOOT_COOLDOWN_SECONDS \
    CONFIGURE_STORAGE_MOUNT COMPANION_STORAGE_UUID \
    COMPANION_STORAGE_MOUNT COMPANION_STORAGE_FSTYPE ENABLE_AVAHI_FIX \
    AVAHI_ALLOW_INTERFACES ENABLE_NFS_CLIENT NFS_SERVER NFS_EXPORT \
    NFS_MOUNT NFS_MOUNT_OPTIONS NFS_RECONCILE_MODE \
    NFS_RECONCILE_INTERVAL_SECONDS ENABLE_LAN_DOCKER_PROXY DOCKER_PROXY_BIND DOCKER_PROXY_PORT \
    DOCKER_PROXY_ALLOW_CIDR DRY_RUN
  do
    eval "value=\${$name:-}"
    printf ' %s=%s' "$name" "$(shell_quote "$value")"
  done
}

cmd_companion_remote() {
  target=$(remote_target)
  remote_script=/tmp/arm-docker-companion-install.sh
  log "copying installer to $target"
  run scp "$SCRIPT_DIR/install.sh" "$target:$remote_script"
  env_pairs=$(remote_env_pairs)
  # shellcheck disable=SC2086
  run ssh $SSH_TTY_FLAGS "$target" "chmod +x $remote_script &&$env_pairs sh $remote_script companion-local"
}

docker_endpoint_for_host() {
  host=$1
  if [ -n "$COMPANION_SSH_ALIAS" ]; then
    printf 'ssh://%s\n' "$COMPANION_SSH_ALIAS"
  elif [ -n "$COMPANION_USER" ]; then
    printf 'ssh://%s@%s\n' "$COMPANION_USER" "$host"
  else
    printf 'ssh://%s\n' "$host"
  fi
}

docker_endpoint_host_fallbacks() {
  endpoint=$1
  [ -n "$COMPANION_HOST_FALLBACKS" ] || return 0
  case "$endpoint" in
    *://*) ;;
    *) return 0 ;;
  esac

  scheme=${endpoint%%://*}
  rest=${endpoint#*://}
  case "$rest" in
    */*)
      authority=${rest%%/*}
      suffix="/${rest#*/}"
      ;;
    *)
      authority=$rest
      suffix=
      ;;
  esac

  userinfo=
  hostport=$authority
  case "$hostport" in
    *@*)
      userinfo="${hostport%%@*}@"
      hostport=${hostport#*@}
      ;;
  esac

  # Keep the parser intentionally simple: host:port endpoints cover Docker TCP
  # proxy and SSH fallbacks. Bracketed IPv6 can still use explicit endpoint
  # fallbacks through COMPANION_DOCKER_ENDPOINT_FALLBACKS.
  case "$hostport" in
    \[*\]*) return 0 ;;
  esac

  case "$hostport" in
    *:*)
      host=${hostport%%:*}
      port_part=${hostport#"$host"}
      ;;
    *)
      host=$hostport
      port_part=
      ;;
  esac

  if [ -n "$COMPANION_HOST" ] && [ "$host" != "$COMPANION_HOST" ]; then
    return 0
  fi

  for fallback_host in $COMPANION_HOST_FALLBACKS; do
    printf '%s://%s%s%s%s\n' "$scheme" "$userinfo" "$fallback_host" "$port_part" "$suffix"
  done
}

docker_endpoint_candidates() {
  if [ -n "$COMPANION_DOCKER_ENDPOINT" ]; then
    printf '%s\n' "$COMPANION_DOCKER_ENDPOINT"
    docker_endpoint_host_fallbacks "$COMPANION_DOCKER_ENDPOINT"
    if [ -n "$COMPANION_SSH_ALIAS" ] &&
       [ "$COMPANION_DOCKER_ENDPOINT" != "ssh://$COMPANION_SSH_ALIAS" ]; then
      printf 'ssh://%s\n' "$COMPANION_SSH_ALIAS"
    fi
    for endpoint in $COMPANION_DOCKER_ENDPOINT_FALLBACKS; do
      printf '%s\n' "$endpoint"
    done
    return
  fi
  require_var COMPANION_HOST
  docker_endpoint_for_host "$COMPANION_HOST"
  if [ -z "$COMPANION_SSH_ALIAS" ]; then
    for fallback_host in $COMPANION_HOST_FALLBACKS; do
      docker_endpoint_for_host "$fallback_host"
    done
  fi
}

docker_endpoint() {
  docker_endpoint_candidates | sed -n '1p'
}

update_docker_context_endpoint() {
  endpoint=$1
  if docker context inspect "$DOCKER_CONTEXT_NAME" >/dev/null 2>&1; then
    run docker context update "$DOCKER_CONTEXT_NAME" \
      --description "ARM companion Docker host" \
      --docker "host=$endpoint"
  else
    run docker context create "$DOCKER_CONTEXT_NAME" \
      --description "ARM companion Docker host" \
      --docker "host=$endpoint"
  fi
  if [ "$USE_DOCKER_CONTEXT" = "1" ]; then
    run docker context use "$DOCKER_CONTEXT_NAME"
  fi
}

docker_endpoint_is_reachable() {
  endpoint=$1
  probe_err=$(mktemp)
  timeout_bin=
  if have gtimeout; then
    timeout_bin=gtimeout
  elif have timeout; then
    timeout_bin=timeout
  fi

  if [ -n "$timeout_bin" ]; then
    "$timeout_bin" "$DEV_TUNNEL_DOCKER_PROBE_TIMEOUT_SECONDS" docker --host "$endpoint" ps >/dev/null 2>"$probe_err"
    probe_status=$?
  else
    docker --host "$endpoint" ps >/dev/null 2>"$probe_err"
    probe_status=$?
  fi

  if [ "$probe_status" -eq 0 ]; then
    rm -f "$probe_err"
    return 0
  fi
  if [ "$probe_status" -eq 124 ]; then
    log "docker endpoint probe timed out after ${DEV_TUNNEL_DOCKER_PROBE_TIMEOUT_SECONDS}s: $endpoint"
  fi
  if [ -s "$probe_err" ]; then
    first_error=$(sed -n '1p' "$probe_err")
    log "docker endpoint probe failed: $endpoint: $first_error"
  fi
  rm -f "$probe_err"
  return 1
}

cmd_context() {
  have docker || die "docker CLI is required"
  endpoint=
  for candidate_endpoint in $(docker_endpoint_candidates); do
    if [ "$DRY_RUN" = "1" ] || docker_endpoint_is_reachable "$candidate_endpoint"; then
      endpoint=$candidate_endpoint
      break
    fi
    log "docker context endpoint is not reachable yet: $DOCKER_CONTEXT_NAME -> $candidate_endpoint"
  done
  if [ -z "$endpoint" ]; then
    endpoint=$(docker_endpoint)
    log "no Docker endpoint candidates are reachable; configuring primary endpoint anyway"
  fi
  update_docker_context_endpoint "$endpoint"
  if [ "$CREATE_BUILDX_BUILDER" = "1" ]; then
    builder=$BUILDX_BUILDER_NAME
    [ -n "$builder" ] || builder="$DOCKER_CONTEXT_NAME-builder"
    if docker buildx inspect "$builder" >/dev/null 2>&1; then
      run docker buildx use "$builder"
    else
      run docker buildx create --name "$builder" --driver docker-container --use "$DOCKER_CONTEXT_NAME"
    fi
    run docker buildx inspect --bootstrap
  fi
  log "docker context ready: $DOCKER_CONTEXT_NAME -> $endpoint"
}

ensure_context_for_dev_tunnels() {
  have docker || die "docker CLI is required"
  for endpoint in $(docker_endpoint_candidates); do
    if [ "$DRY_RUN" = "1" ]; then
      DEV_TUNNEL_ACTIVE_DOCKER_ENDPOINT=$endpoint
      update_docker_context_endpoint "$endpoint"
      log "docker context ready: $DOCKER_CONTEXT_NAME -> $endpoint"
      return 0
    fi
    if docker_endpoint_is_reachable "$endpoint"; then
      DEV_TUNNEL_ACTIVE_DOCKER_ENDPOINT=$endpoint
      update_docker_context_endpoint "$endpoint"
      log "docker context ready: $DOCKER_CONTEXT_NAME -> $endpoint"
      return 0
    fi
    log "docker context endpoint is not reachable yet: $DOCKER_CONTEXT_NAME -> $endpoint"
  done

  if [ "$DEV_TUNNEL_SOFT_FAIL" = "1" ]; then
    log "docker context is not reachable yet: $DOCKER_CONTEXT_NAME"
    return 1
  fi
  die "docker context is not reachable: $DOCKER_CONTEXT_NAME"
}

dev_tunnel_ssh_target() {
  if [ -n "$COMPANION_SSH_ALIAS" ]; then
    printf '%s' "$COMPANION_SSH_ALIAS"
  else
    remote_target
  fi
}

listener_pids_for_port() {
  port=$1
  lsof -nP -iTCP:"$port" -sTCP:LISTEN -Fp 2>/dev/null | sed -n 's/^p//p'
}

listener_commands_for_port() {
  port=$1
  listener_pids_for_port "$port" | while IFS= read -r pid; do
    [ -n "$pid" ] || continue
    ps -p "$pid" -o command= 2>/dev/null || true
  done
}

port_has_colima_listener() {
  port=$1
  listener_commands_for_port "$port" | grep -E '(^|/| )colima( |$)|\.colima/|/lima/' >/dev/null 2>&1
}

port_has_ssh_listener() {
  port=$1
  listener_commands_for_port "$port" | grep -E '(^|/| )ssh( |:|$)' >/dev/null 2>&1
}

port_is_open() {
  port=$1
  nc -z 127.0.0.1 "$port" >/dev/null 2>&1
}

wait_for_port_to_free() {
  port=$1
  tries=0
  while listener_pids_for_port "$port" | grep . >/dev/null 2>&1; do
    tries=$((tries + 1))
    [ "$tries" -le 20 ] || die "local port $port is still busy"
    sleep 1
  done
}

stop_colima_for_conflict_if_needed() {
  port=$1
  [ "$DEV_TUNNEL_STOP_COLIMA_CONFLICTS" = "1" ] || return 0
  have colima || return 0
  if port_has_colima_listener "$port"; then
    log "stopping Colima because it owns requested local port $port"
    run colima stop
    [ "$DRY_RUN" = "1" ] && return 0
    wait_for_port_to_free "$port"
  fi
}

socket_path_for_forward() {
  label=$1
  local_port=$2
  remote_host=$3
  remote_port=$4
  digest=$(printf '%s:%s:%s:%s' "$label" "$local_port" "$remote_host" "$remote_port" | cksum | awk '{print $1}')
  printf '%s/.ssh/arm-companion-dev-%s.ctl' "$HOME" "$digest"
}

close_stale_tunnel_socket() {
  socket=$1
  target=$2
  if [ -S "$socket" ]; then
    ssh -S "$socket" -O exit "$target" >/dev/null 2>&1 || true
  fi
  rm -f "$socket"
}

normalize_forward_spec() {
  spec=$1
  case "$spec" in
    *:*)
      first=${spec%%:*}
      rest=${spec#*:}
      case "$rest" in
        *:*)
          second=${rest%%:*}
          third=${rest#*:}
          printf '%s %s %s\n' "$first" "$second" "$third"
          ;;
        *)
          printf '%s 127.0.0.1 %s\n' "$first" "$rest"
          ;;
      esac
      ;;
    *)
      printf '%s 127.0.0.1 %s\n' "$spec" "$spec"
      ;;
  esac
}

is_port_number() {
  value=$1
  case "$value" in
    ''|*[!0-9]*) return 1 ;;
    *) [ "$value" -gt 0 ] && [ "$value" -le 65535 ] ;;
  esac
}

start_dev_forward() {
  label=$1
  spec=$2
  normalized=$(normalize_forward_spec "$spec")
  # shellcheck disable=SC2086
  set -- $normalized
  local_port=$1
  remote_host=$2
  remote_port=$3
  is_port_number "$local_port" || die "invalid local port in tunnel spec: $spec"
  is_port_number "$remote_port" || die "invalid remote port in tunnel spec: $spec"

  target=$(dev_tunnel_ssh_target)
  socket=$(socket_path_for_forward "$label" "$local_port" "$remote_host" "$remote_port")

  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"

  if port_is_open "$local_port"; then
    if port_has_colima_listener "$local_port"; then
      stop_colima_for_conflict_if_needed "$local_port"
    elif port_has_ssh_listener "$local_port"; then
      log "localhost port already has an SSH listener for $label: $local_port"
      return 0
    elif [ "$DEV_TUNNEL_SKIP_BUSY_PORTS" = "1" ]; then
      log "skipping busy localhost port for $label: $local_port"
      return 0
    else
      die "localhost port is already busy for $label: $local_port"
    fi
  fi

  if listener_pids_for_port "$local_port" | grep . >/dev/null 2>&1; then
    stop_colima_for_conflict_if_needed "$local_port"
  fi

  if listener_pids_for_port "$local_port" | grep . >/dev/null 2>&1; then
    if [ "$DEV_TUNNEL_SKIP_BUSY_PORTS" = "1" ]; then
      log "skipping busy localhost port for $label: $local_port"
      return 0
    fi
    die "cannot bind localhost port for $label: $local_port"
  fi

  close_stale_tunnel_socket "$socket" "$target"
  log "opening localhost tunnel for $label: 127.0.0.1:$local_port -> $target:$remote_host:$remote_port"
  run ssh -fN -M -S "$socket" \
    -o ExitOnForwardFailure=yes \
    -o ServerAliveInterval=15 \
    -o ServerAliveCountMax=3 \
    -L "127.0.0.1:$local_port:$remote_host:$remote_port" \
    "$target"

  [ "$DRY_RUN" = "1" ] && return 0
  port_is_open "$local_port" || die "tunnel did not become reachable on localhost:$local_port"
  log "localhost tunnel healthy for $label: $local_port"
}

start_forward_for_published_port() {
  label=$1
  port=$2
  is_port_number "$port" || return 0
  start_dev_forward "$label" "$port:127.0.0.1:$port"
}

start_forwards_for_docker_published_ports() {
  [ "$DEV_TUNNEL_AUTO_DOCKER_PORTS" = "1" ] || return 0
  have docker || die "docker CLI is required"
  published_file=$(mktemp)
  docker_ps_err=$(mktemp)
  if [ -n "$DEV_TUNNEL_ACTIVE_DOCKER_ENDPOINT" ]; then
    docker_ps_status=0
    docker --host "$DEV_TUNNEL_ACTIVE_DOCKER_ENDPOINT" ps --format '{{.Names}}|{{.Ports}}' > "$published_file" 2>"$docker_ps_err" || docker_ps_status=$?
  else
    docker_ps_status=0
    docker --context "$DOCKER_CONTEXT_NAME" ps --format '{{.Names}}|{{.Ports}}' > "$published_file" 2>"$docker_ps_err" || docker_ps_status=$?
  fi
  if [ "$docker_ps_status" -ne 0 ]; then
    ssh_target=$(dev_tunnel_ssh_target)
    if [ -s "$docker_ps_err" ]; then
      first_error=$(sed -n '1p' "$docker_ps_err")
      log "Docker port inspection failed (exit $docker_ps_status): $first_error"
    else
      log "Docker port inspection failed (exit $docker_ps_status) with no stderr"
    fi
    : > "$docker_ps_err"
    log "trying SSH Docker port inspection: $ssh_target"
    docker_ps_status=0
    ssh -o BatchMode=yes -o ConnectTimeout="$DEV_TUNNEL_DOCKER_PROBE_TIMEOUT_SECONDS" \
      "$ssh_target" "docker ps --format '{{.Names}}|{{.Ports}}'" > "$published_file" 2>"$docker_ps_err" || docker_ps_status=$?
  fi
  if [ "$docker_ps_status" -ne 0 ]; then
    if [ -s "$docker_ps_err" ]; then
      first_error=$(sed -n '1p' "$docker_ps_err")
      log "SSH Docker port inspection failed (exit $docker_ps_status): $first_error"
    else
      log "SSH Docker port inspection failed (exit $docker_ps_status) with no stderr"
    fi
    rm -f "$published_file" "$docker_ps_err"
    if [ "$DEV_TUNNEL_SOFT_FAIL" = "1" ]; then
      log "could not inspect published Docker ports; will retry later"
      return 1
    fi
    die "could not inspect published Docker ports"
  fi
  published_rows=$(cat "$published_file")
  rm -f "$published_file" "$docker_ps_err"

  printf '%s\n' "$published_rows" | while IFS='|' read -r container_name published_ports; do
    [ -n "$published_ports" ] || continue
    printf '%s\n' "$published_ports" | tr ',' '\n' | while IFS= read -r port_mapping; do
      case "$port_mapping" in
        *'->'*'/tcp'*)
          port=$(printf '%s' "$port_mapping" | sed -n 's/.*:\([0-9][0-9]*\)->[0-9][0-9]*\/tcp.*/\1/p')
          [ -n "$port" ] || continue
          start_forward_for_published_port "$container_name" "$port"
          ;;
      esac
    done
  done
}

project_manifest_label() {
  project_root=$1
  basename "$project_root"
}

forward_specs_from_project_manifest() {
  project_root=$1
  [ -d "$project_root" ] || return 0
  manifest="$project_root/$DEV_TUNNEL_MANIFEST_NAME"
  [ -f "$manifest" ] || return 0
  label=$(project_manifest_label "$project_root")
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      ''|\#*) continue ;;
    esac
    start_dev_forward "$label" "$line"
  done < "$manifest"
}

run_mac_dev_tunnels_once() {
  [ "$(uname -s)" = "Darwin" ] || die "mac-dev-tunnels must run on macOS"
  have ssh || die "ssh is required"
  have lsof || die "lsof is required"
  have nc || die "nc is required"
  if ! ensure_context_for_dev_tunnels; then
    return 1
  fi

  found=0
  if [ "$DEV_TUNNEL_AUTO_DOCKER_PORTS" = "1" ]; then
    found=1
    start_forwards_for_docker_published_ports || return 1
  fi

  for spec in $DEV_TUNNEL_FORWARDS; do
    found=1
    start_dev_forward "env" "$spec"
  done

  if [ -n "$DEV_TUNNEL_PROJECT_ROOTS" ]; then
    for project_root in $DEV_TUNNEL_PROJECT_ROOTS; do
      found=1
      forward_specs_from_project_manifest "$project_root"
    done
  fi

  [ "$found" = "1" ] || die "no dev tunnel forwards configured"
}

cmd_mac_dev_tunnels() {
  if ! run_mac_dev_tunnels_once; then
    [ "$DEV_TUNNEL_SOFT_FAIL" = "1" ] && return 0
    die "dev tunnel reconciliation failed"
  fi
}

cmd_mac_dev_tunnels_watch() {
  delay=$DEV_TUNNEL_WATCH_INITIAL_SECONDS
  max_delay=$DEV_TUNNEL_WATCH_MAX_SECONDS
  is_port_number "$delay" || die "DEV_TUNNEL_WATCH_INITIAL_SECONDS must be a positive integer"
  is_port_number "$max_delay" || die "DEV_TUNNEL_WATCH_MAX_SECONDS must be a positive integer"

  while :; do
    if run_mac_dev_tunnels_once; then
      delay=$DEV_TUNNEL_WATCH_INITIAL_SECONDS
    else
      log "dev tunnel reconciliation failed; retrying in ${delay}s"
    fi

    sleep "$delay"
    if [ "$delay" -lt "$max_delay" ]; then
      delay=$((delay * 2))
      [ "$delay" -le "$max_delay" ] || delay=$max_delay
    fi
  done
}

cmd_mac_dev_tunnels_agent_install() {
  [ "$(uname -s)" = "Darwin" ] || die "mac-dev-tunnels-agent-install must run on macOS"
  plist_dir="$HOME/Library/LaunchAgents"
  plist="$plist_dir/$DEV_TUNNEL_LAUNCHD_LABEL.plist"
  mkdir -p "$plist_dir" "$DEV_TUNNEL_LOG_DIR"
  script_path=$(xml_escape "$SCRIPT_DIR/install.sh")
  env_path=$(xml_escape "$ENV_FILE")
  stdout_path=$(xml_escape "$DEV_TUNNEL_LOG_DIR/$DEV_TUNNEL_LAUNCHD_LABEL.out.log")
  stderr_path=$(xml_escape "$DEV_TUNNEL_LOG_DIR/$DEV_TUNNEL_LAUNCHD_LABEL.err.log")
  label_xml=$(xml_escape "$DEV_TUNNEL_LAUNCHD_LABEL")
  launchd_path=$(xml_escape "$DEV_TUNNEL_LAUNCHD_PATH")
  launchd_home=$(xml_escape "$HOME")
  docker_config=$(xml_escape "$DEV_TUNNEL_DOCKER_CONFIG")

  tmp=$(mktemp)
  cat > "$tmp" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$label_xml</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/sh</string>
    <string>$script_path</string>
    <string>mac-dev-tunnels-watch</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>ENV_FILE</key>
    <string>$env_path</string>
    <key>PATH</key>
    <string>$launchd_path</string>
    <key>HOME</key>
    <string>$launchd_home</string>
    <key>DOCKER_CONFIG</key>
    <string>$docker_config</string>
  </dict>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>$stdout_path</string>
  <key>StandardErrorPath</key>
  <string>$stderr_path</string>
</dict>
</plist>
EOF

  if [ "$DRY_RUN" = "1" ]; then
    log "would install launchd agent $plist"
    sed 's/^/  /' "$tmp"
    rm -f "$tmp"
    return
  fi

  install -m 0644 "$tmp" "$plist"
  rm -f "$tmp"
  launchctl bootout "gui/$(id -u)" "$plist" >/dev/null 2>&1 || true
  launchctl bootstrap "gui/$(id -u)" "$plist"
  launchctl kickstart -k "gui/$(id -u)/$DEV_TUNNEL_LAUNCHD_LABEL" || true
  log "launchd agent installed: $plist"
}

cmd_mac_dev_tunnels_agent_uninstall() {
  [ "$(uname -s)" = "Darwin" ] || die "mac-dev-tunnels-agent-uninstall must run on macOS"
  plist="$HOME/Library/LaunchAgents/$DEV_TUNNEL_LAUNCHD_LABEL.plist"
  if [ "$DRY_RUN" = "1" ]; then
    log "would uninstall launchd agent $plist"
    return
  fi
  launchctl bootout "gui/$(id -u)" "$plist" >/dev/null 2>&1 || true
  rm -f "$plist"
  log "launchd agent uninstalled: $plist"
}

cmd_verify() {
  have docker || die "docker CLI is required"
  ctx=${VERIFY_CONTEXT:-$DOCKER_CONTEXT_NAME}
  run docker --context "$ctx" version
  run docker --context "$ctx" info --format 'server={{.ServerVersion}} os={{.OperatingSystem}} arch={{.Architecture}} root={{.DockerRootDir}}'
  run docker --context "$ctx" compose version
  run docker --context "$ctx" run --rm --platform linux/arm64 hello-world
  if [ -f "$SCRIPT_DIR/examples/docker-compose.smoke.yml" ]; then
    run docker --context "$ctx" compose -f "$SCRIPT_DIR/examples/docker-compose.smoke.yml" up --abort-on-container-exit --remove-orphans
    run docker --context "$ctx" compose -f "$SCRIPT_DIR/examples/docker-compose.smoke.yml" down --remove-orphans
  fi
  log "verification complete"
}

cmd_doctor() {
  log "local uname: $(uname -s) $(uname -m)"
  if have docker; then
    docker context ls || true
    docker version || true
    docker buildx version || true
    docker compose version || true
  else
    log "docker CLI not found"
  fi
  if [ -n "$COMPANION_HOST" ]; then
    target=$(remote_target)
    # shellcheck disable=SC2086
    ssh $SSH_TTY_FLAGS "$target" 'uname -a; docker version || sudo docker version || true; docker info || sudo docker info || true' || true
  fi
}

cmd_all() {
  cmd_mac
  cmd_companion_remote
  cmd_context
  cmd_verify
}

command_name=${1:-help}
case "$command_name" in
  mac) cmd_mac ;;
  companion-remote) cmd_companion_remote ;;
  companion-local) cmd_companion_local ;;
  mac-nfs-export) cmd_mac_nfs_export ;;
  context) cmd_context ;;
  mac-dev-tunnels) cmd_mac_dev_tunnels ;;
  mac-dev-tunnels-watch) cmd_mac_dev_tunnels_watch ;;
  mac-dev-tunnels-agent-install) cmd_mac_dev_tunnels_agent_install ;;
  mac-dev-tunnels-agent-uninstall) cmd_mac_dev_tunnels_agent_uninstall ;;
  verify) cmd_verify ;;
  doctor) cmd_doctor ;;
  all) cmd_all ;;
  help|-h|--help) usage ;;
  *) usage; die "unknown command: $command_name" ;;
esac
