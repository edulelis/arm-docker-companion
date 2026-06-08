# Radxa / Rockchip Notes

These notes are generic and do not depend on a specific private machine.

## mDNS / Avahi

On some Rockchip Armbian images, Docker bridge interfaces can confuse mDNS announcements. If the host advertises a Docker bridge address instead of the LAN address, pin Avahi to the physical LAN interface.

Find the interface:

```sh
ip -br addr
```

Then set:

```sh
ENABLE_AVAHI_FIX=1
AVAHI_ALLOW_INTERFACES=end0
```

Use the real physical interface for your board. Common names include `end0`, `eth0`, and `enP*`.

## Storage

A robust small-board pattern is:

- boot from SD/eMMC
- mount SSD/NVMe at `/mnt/companion-ssd`
- set Docker `data-root` to `/mnt/companion-ssd/docker`
- use `nofail` in fstab so the board still boots when storage is absent

Get the filesystem UUID:

```sh
lsblk -f
```

Then configure:

```sh
CONFIGURE_STORAGE_MOUNT=1
COMPANION_STORAGE_UUID=your-uuid
COMPANION_STORAGE_MOUNT=/mnt/companion-ssd
COMPANION_DOCKER_DATA_ROOT=/mnt/companion-ssd/docker
```

The installer never formats disks.

## Mac Localhost Tunnels

On a Radxa used as a Docker companion, Docker-published ports are bound on the
Radxa. Tools running on the Mac that use `localhost` still need Mac-side
forwards.

Use `mac-dev-tunnels` to create or repair those forwards:

```sh
DOCKER_CONTEXT_NAME=radxa \
COMPANION_HOST=rock-5a.local \
COMPANION_USER=eduardo \
COMPANION_SSH_ALIAS=radxa \
COMPANION_DOCKER_ENDPOINT=tcp://rock-5a.local:23750 \
./install.sh mac-dev-tunnels
```

Install the launchd healer when the Radxa should remain the default even after
sleep, network changes, or Colima fallback usage:

```sh
./install.sh mac-dev-tunnels-agent-install
```

The healer is conservative: it only stops Colima when Colima is the process
holding one of the Docker-published ports that need to point at the Radxa. By
default it mirrors every published TCP host port from the configured Docker
context onto Mac `127.0.0.1`. The launchd watcher retries from 5 seconds and
exponentially backs off to a 60 second cap when the Radxa is temporarily
unreachable.
