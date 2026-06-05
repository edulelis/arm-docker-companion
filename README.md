# ARM Docker Companion

Public-ready installer for using an ARM Linux machine as a stable Docker host from an ARM Mac.

The common pattern is:

- ARM Mac runs the Docker CLI, Compose, Buildx, editors, and project checkout.
- ARM Linux companion runs the Docker Engine and containers.
- Docker context connects the Mac to the companion, preferably over SSH.
- Optional modules handle Colima fallback, SSD-backed Docker data, mDNS stability, NFS bind mounts, and a LAN Docker socket proxy.

This was shaped around Radxa/Rockchip + Armbian, but it is generic for ARM64 Debian/Ubuntu/Armbian companions such as Radxa Rock, Raspberry Pi 5, Ampere boxes, and ARM mini PCs.

## Use Cases

Use an ARM companion when you want Docker work to happen somewhere other than your Mac, while keeping the Mac as your editor and command center.

- Save Mac CPU, RAM, disk, and battery during heavy Compose stacks, image builds, databases, queues, and test environments.
- Avoid Docker Desktop overhead on macOS by using a real Linux Docker Engine on the LAN.
- Keep long-running development services alive while the Mac sleeps, reboots, travels, or switches projects.
- Run ARM-native Linux containers and builds without emulation surprises.
- Put noisy or stateful services such as Postgres, Redis, ClickHouse, Ollama, CI runners, media tools, and build caches on an always-on machine.
- Share one stable Docker host across multiple project checkouts or multiple Macs on the same trusted network.
- Use Colima only as a local fallback instead of making the Mac carry every workload all the time.
- Turn a Radxa, Raspberry Pi, or ARM mini PC into a lightweight home-lab build and service node.

This is not a Kubernetes replacement and it is not a good fit for untrusted networks, high-latency remote links, or workloads that need all project files to stay strictly local unless you configure that explicitly.

See [Use Cases](docs/use-cases.md) for concrete examples.

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

On ARM Linux companion:

- Docker Engine from Docker's official apt repository.
- Docker Compose and Buildx plugins.
- Docker group membership for the login user.
- Optional Docker daemon config with data-root, log rotation, and live-restore.
- Optional persistent SSD fstab mount.
- Optional Avahi `allow-interfaces` fix for mDNS reliability.
- Optional NFS client mount and systemd remount watchdog.
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

## Commands

```sh
./install.sh mac                # configure the ARM Mac
./install.sh companion-remote   # copy installer over SSH and run companion-local
./install.sh companion-local    # run directly on the ARM Linux host
./install.sh mac-nfs-export     # add a macOS /etc/exports entry and restart nfsd
./install.sh context            # create/update Docker context
./install.sh verify             # run Docker/Compose smoke checks
./install.sh doctor             # print local and remote diagnostic info
./install.sh all                # mac + companion-remote + context + verify
```

## Safety

- No secrets belong in this repo.
- `.env` is ignored by git.
- Existing root-owned files are backed up before managed rewrites.
- NFS and Docker TCP proxy modules are opt-in.
- `DRY_RUN=1 ./install.sh <command>` previews many commands.

## References

- [Docker Engine install docs](https://docs.docker.com/engine/install/)
- [Docker contexts](https://docs.docker.com/engine/manage-resources/contexts/)
- [Protect the Docker daemon socket](https://docs.docker.com/engine/security/protect-access/)
