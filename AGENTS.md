# Agent Runbook

This repository is designed so an AI agent can configure an ARM Mac and an ARM Linux Docker companion from an SSH target.

## Safety Rules

- Never commit `.env`, SSH keys, tokens, host inventories, private IPs, or personal paths.
- Prefer SSH Docker contexts. Do not enable the LAN Docker socket proxy unless the human explicitly asks for it.
- Treat membership in the `docker` group as root-equivalent on the companion.
- Use `DRY_RUN=1` before making changes when the target machine is unfamiliar.
- Do not format disks. The installer only mounts already-prepared storage.
- If SSH authentication fails, stop and show the exact failure. Do not generate or replace keys unless asked.

## Required Inputs

Ask for or infer these before setup:

- `COMPANION_HOST`: DNS, mDNS, or IP reachable from the Mac.
- `COMPANION_USER`: SSH user on the companion.
- `DOCKER_CONTEXT_NAME`: desired local Docker context name, usually `arm-companion`.
- Optional `COMPANION_SSH_IDENTITY_FILE`: SSH key path if the default SSH agent is not enough.
- Optional storage UUID and mount point if Docker data should live on SSD/NVMe.
- Optional USB storage bridge vendor/product IDs if USB autosuspend hardening or USB recovery should be configured.
- Optional NFS export/mount paths if containers need direct access to a Mac checkout.
- Whether daily Docker cleanup is wanted, which object categories may be
  purged, and the minimum stale age.

## Basic Agent Flow

From the repo root:

```sh
cp config/companion.env.example .env
```

Edit `.env` with at least:

```sh
DOCKER_CONTEXT_NAME=arm-companion
COMPANION_HOST=armbox.local
COMPANION_USER=your-user
COMPANION_SSH_ALIAS=arm-companion
```

Validate connectivity:

```sh
ssh "$COMPANION_USER@$COMPANION_HOST" 'uname -a'
```

Preview the setup:

```sh
DRY_RUN=1 ./install.sh mac
DRY_RUN=1 ./install.sh companion-remote
DRY_RUN=1 ./install.sh context
```

Apply:

```sh
./install.sh mac
./install.sh companion-remote
./install.sh context
./install.sh verify
```

## SSH-Only Fast Path

If the Mac already has Docker CLI installed and the companion already has Docker Engine installed:

```sh
DOCKER_CONTEXT_NAME=arm-companion \
COMPANION_HOST=armbox.local \
COMPANION_USER=your-user \
./install.sh context
```

Then verify:

```sh
./install.sh verify
```

## Persistent Storage Path

If the human provides a storage UUID:

```sh
CONFIGURE_STORAGE_MOUNT=1
COMPANION_STORAGE_UUID=your-filesystem-uuid
COMPANION_STORAGE_MOUNT=/mnt/companion-ssd
CONFIGURE_DOCKER_DAEMON=1
COMPANION_DOCKER_DATA_ROOT=/mnt/companion-ssd/docker
ENABLE_DOCKER_STORAGE_GUARD=1
```

Confirm the disk exists first:

```sh
ssh "$COMPANION_USER@$COMPANION_HOST" 'lsblk -f'
```

Do not create filesystems or change partitions unless explicitly requested.
For flaky USB SSD bridges, add `ENABLE_USB_STORAGE_POWER_POLICY=1` and bridge
IDs from `lsusb`; use `ENABLE_USB_STORAGE_RECOVERY_REBOOT=1` only when the
human accepts a rate-limited companion reboot after USB enumeration failures.

## Optional Docker Cleanup

Enable cleanup only after the human chooses the retention and purge scope.
Keep running containers and volumes disabled unless explicitly requested, and
run a non-destructive plan before the first purge:

```sh
ENABLE_DOCKER_STALE_CLEANUP=1
DOCKER_STALE_AFTER_HOURS=168
DOCKER_CLEANUP_RUNNING_CONTAINERS=0
DOCKER_CLEANUP_CONTAINER_VOLUMES=0
DOCKER_CLEANUP_UNUSED_VOLUMES=0
./install.sh companion-remote
ssh "$COMPANION_USER@$COMPANION_HOST" 'sudo docker-stale-cleanup plan'
```

Use the `docker.cleanup.keep=true` label or
`DOCKER_PROTECTED_NAME_REGEX` for workloads that must never be removed.

## Optional NFS Path

Use this only when containers on the companion need bind mounts from the Mac checkout.

Mac side:

```sh
ENABLE_MAC_NFS_EXPORT=1
MAC_NFS_EXPORT_PATH=/Users/you/Repositories/project
MAC_NFS_CLIENTS=armbox.local
./install.sh mac-nfs-export
```

Companion side:

```sh
ENABLE_NFS_CLIENT=1
NFS_SERVER=mac.local
NFS_EXPORT=/Users/you/Repositories/project
NFS_MOUNT=/Users/you/Repositories/project
./install.sh companion-remote
```

## Diagnostics

Use:

```sh
./install.sh doctor
docker context ls
docker --context "$DOCKER_CONTEXT_NAME" info
```

Common fixes:

- New Docker group membership needs a fresh SSH login.
- mDNS resolving to the wrong interface may need `ENABLE_AVAHI_FIX=1`.
- Slow or stale bind mounts may need the NFS remount watchdog or a local checkout on the companion.
