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
COMPANION_USER=${COMPANION_USER:-}
COMPANION_SSH_ALIAS=${COMPANION_SSH_ALIAS:-$DOCKER_CONTEXT_NAME}
COMPANION_SSH_IDENTITY_FILE=${COMPANION_SSH_IDENTITY_FILE:-}
COMPANION_DOCKER_ENDPOINT=${COMPANION_DOCKER_ENDPOINT:-}

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

ENABLE_LAN_DOCKER_PROXY=${ENABLE_LAN_DOCKER_PROXY:-0}
DOCKER_PROXY_BIND=${DOCKER_PROXY_BIND:-0.0.0.0}
DOCKER_PROXY_PORT=${DOCKER_PROXY_PORT:-23750}
DOCKER_PROXY_ALLOW_CIDR=${DOCKER_PROXY_ALLOW_CIDR:-}

CREATE_BUILDX_BUILDER=${CREATE_BUILDX_BUILDER:-1}
BUILDX_BUILDER_NAME=${BUILDX_BUILDER_NAME:-}
USE_DOCKER_CONTEXT=${USE_DOCKER_CONTEXT:-1}
DRY_RUN=${DRY_RUN:-0}
SSH_TTY_FLAGS=${SSH_TTY_FLAGS:--t}

usage() {
  cat <<'EOF'
Usage:
  ./install.sh mac
  ./install.sh companion-remote
  ./install.sh companion-local
  ./install.sh mac-nfs-export
  ./install.sh context
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

remote_target() {
  require_var COMPANION_HOST
  if [ -n "$COMPANION_USER" ]; then
    printf '%s@%s' "$COMPANION_USER" "$COMPANION_HOST"
  else
    printf '%s' "$COMPANION_HOST"
  fi
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
  HostName $COMPANION_HOST
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
  as_root mkdir -p "$NFS_MOUNT"
  line="$NFS_SERVER:$NFS_EXPORT $NFS_MOUNT nfs4 rw,hard,intr,_netdev,nofail,x-systemd.automount,x-systemd.idle-timeout=60 0 0"
  if grep -F " $NFS_MOUNT nfs" /etc/fstab >/dev/null 2>&1; then
    log "NFS mount already present in /etc/fstab"
  else
    backup_file /etc/fstab
    if [ "$DRY_RUN" = "1" ]; then
      log "would append to /etc/fstab: $line"
    else
      printf '%s\n' "$line" | sudo tee -a /etc/fstab >/dev/null
    fi
  fi

  mount_json=$(shell_quote "$NFS_MOUNT")
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

  install_root_file /etc/systemd/system/arm-companion-nfs-remount.timer 0644 <<'EOF'
[Unit]
Description=Run ARM companion NFS remount watchdog

[Timer]
OnBootSec=30s
OnUnitActiveSec=10s
AccuracySec=2s
Unit=arm-companion-nfs-remount.service

[Install]
WantedBy=timers.target
EOF
  as_root systemctl daemon-reload
  as_root systemctl enable --now arm-companion-nfs-remount.timer
}

configure_lan_docker_proxy() {
  [ "$ENABLE_LAN_DOCKER_PROXY" = "1" ] || return 0
  log "WARNING: exposing the Docker socket over TCP gives clients root-equivalent control of this host."
  install_root_file /etc/systemd/system/arm-companion-docker-proxy.service 0644 <<EOF
[Unit]
Description=ARM companion Docker socket LAN proxy
Requires=docker.socket
After=network-online.target docker.service docker.socket

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
  configure_storage_mount
  configure_docker_daemon
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
    DOCKER_LOG_MAX_FILE CONFIGURE_STORAGE_MOUNT COMPANION_STORAGE_UUID \
    COMPANION_STORAGE_MOUNT COMPANION_STORAGE_FSTYPE ENABLE_AVAHI_FIX \
    AVAHI_ALLOW_INTERFACES ENABLE_NFS_CLIENT NFS_SERVER NFS_EXPORT \
    NFS_MOUNT ENABLE_LAN_DOCKER_PROXY DOCKER_PROXY_BIND DOCKER_PROXY_PORT \
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

docker_endpoint() {
  if [ -n "$COMPANION_DOCKER_ENDPOINT" ]; then
    printf '%s' "$COMPANION_DOCKER_ENDPOINT"
    return
  fi
  require_var COMPANION_HOST
  if [ -n "$COMPANION_SSH_ALIAS" ]; then
    printf 'ssh://%s' "$COMPANION_SSH_ALIAS"
  elif [ -n "$COMPANION_USER" ]; then
    printf 'ssh://%s@%s' "$COMPANION_USER" "$COMPANION_HOST"
  else
    printf 'ssh://%s' "$COMPANION_HOST"
  fi
}

cmd_context() {
  have docker || die "docker CLI is required"
  endpoint=$(docker_endpoint)
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
  verify) cmd_verify ;;
  doctor) cmd_doctor ;;
  all) cmd_all ;;
  help|-h|--help) usage ;;
  *) usage; die "unknown command: $command_name" ;;
esac
