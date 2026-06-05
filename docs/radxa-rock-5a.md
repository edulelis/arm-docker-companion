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

