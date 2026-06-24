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

If the board boots from SD/eMMC and the SSD-backed Docker data path must be
fail-closed, add:

```sh
ENABLE_DOCKER_STORAGE_GUARD=1
DOCKER_STORAGE_GUARD_INTERVAL_SECONDS=15
```

This prevents Docker from silently starting on the wrong filesystem when the
USB SSD disappears and disables `docker.socket` so socket activation cannot
revive a bad daemon behind your back.

If the SSD is USB-attached, disable autosuspend and keep the bridge powered.
Use `lsusb` to find the real bridge IDs:

```sh
ENABLE_USB_STORAGE_POWER_POLICY=1
USB_STORAGE_BRIDGE_VENDOR_ID=0bda
USB_STORAGE_BRIDGE_PRODUCT_ID=9210
```

The example IDs above are for one Realtek RTL9210 bridge; use the IDs from your
own enclosure.

Some USB SSD enclosures fail after a power event before Linux can create
`/dev/sdX` or `/dev/disk/by-uuid/...`. Kernel logs usually show messages such
as `device descriptor read`, `not accepting address`, `unable to enumerate`, or
`Cannot enable. Maybe the USB cable is bad?`. A normal storage reconcile cannot
mount a disk that the kernel cannot see, so use the opt-in reboot recovery for
that class of failure:

```sh
ENABLE_DOCKER_STORAGE_GUARD=1
ENABLE_USB_STORAGE_RECOVERY_REBOOT=1
USB_STORAGE_RECOVERY_MIN_UPTIME_SECONDS=180
USB_STORAGE_RECOVERY_REBOOT_COOLDOWN_SECONDS=21600
```

The reboot is rate-limited and only triggers when the expected storage UUID is
absent and recent kernel logs match USB enumeration failures.

## Mac Localhost Tunnels

On a Radxa used as a Docker companion, Docker-published ports are bound on the
Radxa. Tools running on the Mac that use `localhost` still need Mac-side
forwards.

Use `mac-dev-tunnels` to create or repair those forwards:

```sh
DOCKER_CONTEXT_NAME=arm-companion \
COMPANION_HOST=companion.local \
COMPANION_HOST_FALLBACKS="192.0.2.10" \
COMPANION_USER=your-user \
COMPANION_SSH_ALIAS=arm-companion \
./install.sh mac-dev-tunnels
```

Install the launchd healer when the Radxa should remain the default even after
sleep, network changes, or Colima fallback usage:

```sh
./install.sh mac-dev-tunnels-agent-install
```

The healer is conservative: it only stops Colima when Colima is the process
holding one of the Docker-published ports that need to point at the Radxa. By
default it probes the configured Docker endpoint candidates, uses the reachable
endpoint to read published TCP host ports, falls back to SSH `docker ps` if
endpoint inspection fails, and mirrors those ports onto Mac `127.0.0.1`. The
launchd watcher retries from 5 seconds and exponentially backs off to a 60
second cap when the Radxa is temporarily unreachable. Individual Docker
endpoint probes are bounded to 5 seconds when `gtimeout`/`timeout` is
available.

If the primary companion hostname is intermittently stale, set `COMPANION_HOST_FALLBACKS` to a
direct IP or alternate hostname. The tunnel healer will try the mDNS Docker
endpoint first and then equivalent fallback endpoints before giving up for that
watch pass. When `COMPANION_SSH_ALIAS` is configured, it also tries the SSH
Docker endpoint as a transport fallback after TCP endpoint candidates. Set
`COMPANION_SSH_HOST` too when the generated SSH alias should use the direct IP.

## NFS Mount Recovery

If the Radxa mounts a Mac checkout by NFS and stale automount state becomes the
problem after sleep or reboot, switch to direct reconcile mode:

```sh
ENABLE_NFS_CLIENT=1
NFS_SERVER=mac.local
NFS_EXPORT=/Users/you/Repositories/project
NFS_MOUNT=/Users/you/Repositories/project
NFS_RECONCILE_MODE=direct
NFS_RECONCILE_INTERVAL_SECONDS=15
```

That replaces `x-systemd.automount` with a direct mount plus a timer that
force-unmounts and remounts the export when the old mount state goes stale.

### Loopback Port Failure Trail

Use this checklist when a Mac-side test runner cannot reach a companion-hosted
container port:

1. Confirm which machine owns Docker:

   ```sh
   docker context show
   docker context ls
   docker info --format '{{.Name}} {{.OperatingSystem}} {{.Architecture}}'
   ```

2. Confirm Docker sees the container and its published port:

   ```sh
   docker --context arm-companion ps --format '{{.Names}}|{{.Ports}}'
   ```

3. Compare the three paths:

   ```sh
   nc -vz 127.0.0.1 <port>
   nc -vz localhost <port>
   nc -vz <companion-lan-ip> <port>
   ```

4. Interpret the result:

   - `127.0.0.1:<port>` failing on the Mac means the Mac tunnel is absent or
     unhealthy.
   - `<companion-lan-ip>:<port>` failing is expected for Docker publishes bound
     to companion loopback, for example `127.0.0.1:<port>->6379/tcp`.
   - A different service published as `0.0.0.0:<port>->...` working over the
     LAN only proves that LAN-routable publishes work; it does not make
     loopback-only publishes reachable from the Mac.

5. Repair the Mac-side tunnel instead of changing the project repo:

   ```sh
   ./install.sh mac-dev-tunnels
   launchctl kickstart -k gui/$(id -u)/com.arm-docker-companion.dev-tunnels
   nc -vz 127.0.0.1 <port>
   ```

For Redis, a direct RESP ping is a useful final check:

```sh
printf '*1\r\n$4\r\nPING\r\n' | nc -w 2 127.0.0.1 <port>
```

### Notes From A Failed Debugging Pass

This is the sequence to remember from the localhost tunnel failure:

- Checking the application container first was misleading. The Redis container
  was already running and listening inside Docker.
- Trying Mac `127.0.0.1:<redis-port>` failed because no Mac-side listener owned
  that port yet.
- Trying the Radxa LAN address also failed for loopback-only publishes, which is
  expected when Docker shows `127.0.0.1:<redis-port>->6379/tcp`.
- Comparing with a service published on `0.0.0.0:<port>` proved the Radxa Docker
  host was reachable, but did not make loopback-only Redis reachable.
- Binding Redis to `0.0.0.0` in the application repo was the wrong direction for
  this setup. It exposes a private development dependency on the LAN and mixes
  Radxa-specific transport concerns into project config.
- The right repair is in this companion repo: keep project services loopback-only
  on the Radxa and make `mac-dev-tunnels` mirror those published ports onto Mac
  `127.0.0.1`.
- The launchd watcher also hit a transport race where endpoint probing succeeded
  but Docker port inspection failed. The tunnel healer now retries port
  inspection through the configured SSH target before giving up.
