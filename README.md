# ARM Docker Companion

Public-ready installer for using an ARM Linux machine as a stable Docker host from an ARM Mac.

The common pattern is:

- ARM Mac runs the Docker CLI, Compose, Buildx, editors, and project checkout.
- ARM Linux companion runs the Docker Engine and containers.
- Docker context connects the Mac to the companion, preferably over SSH.
- Optional modules handle Colima fallback, SSD-backed Docker data, stale Docker cleanup, mDNS stability, NFS bind mounts, and a LAN Docker socket proxy.

This was shaped around Radxa/Rockchip + Armbian, but it is generic for ARM64 Debian/Ubuntu/Armbian companions such as Radxa Rock, Raspberry Pi 5, Ampere boxes, and ARM mini PCs.

## Why This Exists

ARM Macs are excellent developer machines, but Docker can still become the thing that makes them feel heavy: large Compose stacks eat RAM, image builds heat the machine, local volumes fill the internal SSD, and long-running services disappear when the Mac sleeps or reboots.

This project lets the Mac stay the command center while an ARM Linux companion does the container work. You keep using `docker`, `docker compose`, and Buildx from the Mac, but the daemon, images, volumes, databases, queues, workers, and test containers live on another machine.

Good use cases:

- Save Mac CPU, RAM, disk, and battery during heavy Docker workloads.
- Move Postgres, Redis, ClickHouse, queues, workers, AI services, media tools, and build caches onto an always-on machine.
- Avoid Docker Desktop overhead by using a real Linux Docker Engine on the LAN.
- Keep development services running while the Mac sleeps, reboots, travels, or switches projects.
- Run ARM-native Linux containers and builds without macOS VM behavior or emulation surprises.
- Share one stable Docker host across multiple project checkouts or multiple Macs on a trusted network.
- Keep Docker data on external SSD/NVMe attached to the companion instead of filling the Mac's internal storage.
- Use Colima as a local fallback instead of making the Mac carry every container workload all the time.
- Turn a Radxa, Raspberry Pi, or ARM mini PC into a practical home-lab build and service node.

Concrete examples:

- A monorepo with API, frontend, Postgres, Redis, workers, and integration tests runs on the companion while your editor and browser stay responsive on the Mac.
- A database-heavy project keeps volumes and seed data on the companion SSD, so switching branches or rebooting the Mac does not destroy the local service state.
- A home-lab setup keeps reverse proxies, dashboards, local AI, CI runners, or smoke-test services online even when the Mac is closed.
- A team or household with multiple ARM Macs points Docker contexts at one trusted LAN host instead of duplicating large images and volumes on every machine.

This is not a Kubernetes replacement. It is also not a good fit for untrusted networks, high-latency remote links, x86-only workloads, or projects where every source file and container volume must remain strictly local to the Mac.

If an AI agent is doing the setup for you, see [AGENTS.md](AGENTS.md) for the SSH-driven runbook and safety rules.

## Quick Start

```sh
git clone https://github.com/edulelis/arm-docker-companion.git
cd arm-docker-companion
cp config/companion.env.example .env
$EDITOR .env

./install.sh mac
./install.sh companion-remote
./install.sh context
./install.sh verify
```

Minimum `.env`:

```sh
DOCKER_CONTEXT_NAME=arm-companion
COMPANION_HOST=armbox.local
COMPANION_USER=your-user
COMPANION_SSH_ALIAS=arm-companion
```

After setup:

```sh
docker context use arm-companion
docker ps
docker compose up
```

## What It Installs

On macOS ARM64:

- Homebrew Docker CLI, Compose plugin, Buildx plugin, Colima fallback, `jq`, `socat`, and ShellCheck.
- Optional SSH config block with ControlMaster, ControlPersist, and keepalives.
- Optional shell profile exports for BuildKit.
- Optional macOS NFS export for a project checkout.
- Optional self-healing macOS localhost tunnels that mirror companion-published
  Docker ports for tools that still connect to `localhost`.

On ARM Linux companion:

- Docker Engine from Docker's official apt repository.
- Docker Compose and Buildx plugins.
- Docker group membership for the login user.
- Optional Docker daemon config with data-root, log rotation, and live-restore.
- Optional persistent SSD fstab mount.
- Optional fail-closed storage guard that stops Docker when the expected SSD/NVMe is absent and restarts it when storage returns.
- Optional daily cleanup of stale containers, images, networks, volumes, and build cache.
- Optional Avahi `allow-interfaces` fix for mDNS reliability.
- Optional NFS client mount with either the original automount watchdog or a direct remount/reconcile timer for stale sleep/restart cases.
- Optional systemd `socat` Docker socket LAN proxy.

For Armbian, the installer maps Ubuntu codenames such as `noble` to Docker's Ubuntu apt repository. If your derivative distro reports unusual metadata, set `DOCKER_APT_OS=ubuntu|debian` and `DOCKER_APT_SUITE=<codename>` in `.env`.

## Recommended Connection

Use SSH Docker contexts:

```sh
docker context create arm-companion --docker host=ssh://your-user@armbox.local
docker context use arm-companion
```

The installer creates or updates this context when `COMPANION_DOCKER_ENDPOINT` is empty.

## Optional LAN Docker Proxy

The LAN proxy is disabled by default. A raw Docker TCP socket gives clients root-equivalent control of the companion. Use it only on a trusted, restricted LAN or behind a firewall/VPN.

Enable it explicitly:

```sh
ENABLE_LAN_DOCKER_PROXY=1
DOCKER_PROXY_BIND=0.0.0.0
DOCKER_PROXY_PORT=23750
COMPANION_DOCKER_ENDPOINT=tcp://armbox.local:23750
```

For most users, SSH is the better default.

## Storage Model

For small ARM boards, the stable pattern is:

- boot from reliable SD/eMMC
- store Docker data on SSD/NVMe
- mount storage with `nofail`
- keep Docker usable even if external storage is absent

Set:

```sh
CONFIGURE_STORAGE_MOUNT=1
COMPANION_STORAGE_UUID=your-filesystem-uuid
COMPANION_STORAGE_MOUNT=/mnt/companion-ssd
CONFIGURE_DOCKER_DAEMON=1
COMPANION_DOCKER_DATA_ROOT=/mnt/companion-ssd/docker
```

The installer does not format disks. Create filesystems and backups yourself.

For boards that boot from SD/eMMC but should never let Docker silently fall back
to the wrong disk, enable the fail-closed guard:

```sh
CONFIGURE_STORAGE_MOUNT=1
COMPANION_STORAGE_UUID=your-filesystem-uuid
COMPANION_STORAGE_MOUNT=/mnt/companion-ssd
CONFIGURE_DOCKER_DAEMON=1
COMPANION_DOCKER_DATA_ROOT=/mnt/companion-ssd/docker
ENABLE_DOCKER_STORAGE_GUARD=1
DOCKER_STORAGE_GUARD_INTERVAL_SECONDS=15
```

This keeps `docker.service` from starting unless the expected storage UUID is
mounted under the companion storage path and the Docker data root resolves to
that same filesystem. It also disables `docker.socket` so socket activation
cannot resurrect Docker against the wrong storage path.

For USB SSDs, you can also disable USB autosuspend and keep USB power control
forced on:

```sh
ENABLE_USB_STORAGE_POWER_POLICY=1
USB_STORAGE_BRIDGE_VENDOR_ID=0bda
USB_STORAGE_BRIDGE_PRODUCT_ID=9210
```

The vendor/product IDs are optional. When provided, udev also triggers the
storage reconcile service when that bridge changes state.

Some USB SSD bridges can fail before Linux sees a block device after a power
event. In that case the guard cannot mount anything because `/dev/disk/by-uuid`
never appears. For that specific failure mode, opt into a rate-limited reboot:

```sh
ENABLE_DOCKER_STORAGE_GUARD=1
ENABLE_USB_STORAGE_RECOVERY_REBOOT=1
USB_STORAGE_RECOVERY_MIN_UPTIME_SECONDS=180
USB_STORAGE_RECOVERY_REBOOT_COOLDOWN_SECONDS=21600
```

The reboot path only triggers when the expected storage UUID is absent and
recent kernel logs show USB descriptor or enumeration failures. It is off by
default because a host reboot is disruptive and cannot repair a physically
unplugged drive.

## Optional Docker Cleanup

The cleanup timer is disabled until explicitly enabled. Its conservative
defaults remove stopped containers, unused images, networks, and build cache
only after seven days. Running containers and volumes are preserved by
default.

```sh
ENABLE_DOCKER_STALE_CLEANUP=1
DOCKER_STALE_AFTER_HOURS=168
DOCKER_CLEANUP_STALE_CONTAINERS=1
DOCKER_CLEANUP_RUNNING_CONTAINERS=0
DOCKER_CLEANUP_CONTAINER_VOLUMES=0
DOCKER_CLEANUP_UNUSED_VOLUMES=0
DOCKER_CLEANUP_IMAGES=1
DOCKER_CLEANUP_NETWORKS=1
DOCKER_CLEANUP_BUILD_CACHE=1
DOCKER_PROTECTED_NAME_REGEX='^buildx_buildkit_.*$'
DOCKER_CLEANUP_KEEP_LABEL=docker.cleanup.keep
DOCKER_REQUIRE_DATA_ROOT_MOUNT=0
```

After applying the companion setup, preview the next run without deleting
anything:

```sh
sudo docker-stale-cleanup plan
```

The timer runs daily with a randomized delay of up to 30 minutes. Container
age means creation time, not last activity. Enabling running-container cleanup
can therefore remove a healthy long-running service unless its name matches
`DOCKER_PROTECTED_NAME_REGEX` or it has the keep label. A protected container
also preserves the rest of its Docker Compose project.

Setting `ENABLE_DOCKER_STALE_CLEANUP=0` and rerunning the installer disables a
cleanup timer previously installed by this project without removing its files.

To keep a container or Compose project independently of its name:

```yaml
services:
  app:
    labels:
      docker.cleanup.keep: "true"
```

## Optional NFS Bind Mounts

If containers on the companion need a project checkout from the Mac:

```sh
ENABLE_MAC_NFS_EXPORT=1
MAC_NFS_EXPORT_PATH=/Users/you/Repositories/project
MAC_NFS_CLIENTS=armbox.local

ENABLE_NFS_CLIENT=1
NFS_SERVER=mac.local
NFS_EXPORT=/Users/you/Repositories/project
NFS_MOUNT=/Users/you/Repositories/project
```

Run:

```sh
./install.sh mac-nfs-export
./install.sh companion-remote
```

If stale automount state becomes the problem after Mac sleep or either machine
restarts, switch the companion to direct mount reconcile mode:

```sh
ENABLE_NFS_CLIENT=1
NFS_SERVER=mac.local
NFS_EXPORT=/Users/you/Repositories/project
NFS_MOUNT=/Users/you/Repositories/project
NFS_RECONCILE_MODE=direct
NFS_RECONCILE_INTERVAL_SECONDS=15
```

That mode avoids `x-systemd.automount` and uses a timer to force-unmount and
remount stale NFS state instead.

## Commands

```sh
./install.sh mac                # configure the ARM Mac
./install.sh companion-remote   # copy installer over SSH and run companion-local
./install.sh companion-local    # run directly on the ARM Linux host
./install.sh mac-nfs-export     # add a macOS /etc/exports entry and restart nfsd
./install.sh context            # create/update Docker context
./install.sh mac-dev-tunnels    # heal localhost tunnels to companion-published Docker ports
./install.sh mac-dev-tunnels-agent-install    # run the self-healing launchd watcher
./install.sh mac-dev-tunnels-agent-uninstall  # remove the launchd tunnel healer
./install.sh verify             # run Docker/Compose smoke checks
./install.sh doctor             # print local and remote diagnostic info
./install.sh all                # mac + companion-remote + context + verify
```

## Safety

- No secrets belong in this repo.
- `.env` is ignored by git.
- Existing root-owned files are backed up before managed rewrites.
- NFS, stale cleanup, and Docker TCP proxy modules are opt-in.
- `DRY_RUN=1 ./install.sh <command>` previews many commands.

## References

- [Docker Engine install docs](https://docs.docker.com/engine/install/)
- [Docker contexts](https://docs.docker.com/engine/manage-resources/contexts/)
- [Protect the Docker daemon socket](https://docs.docker.com/engine/security/protect-access/)
