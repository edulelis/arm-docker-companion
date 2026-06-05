# Use Cases

This project is for people who like working on an ARM Mac, but do not want the Mac to be the only machine doing Docker work.

## Save Mac Resources

Large Compose stacks can keep CPUs hot, pressure memory, fill disks, and make the editor feel worse. Moving the Docker daemon to an ARM Linux companion lets the Mac stay focused on the editor, browser, terminal, and local tooling while containers run elsewhere.

Good examples:

- monorepos with Postgres, Redis, queues, workers, and frontend dev servers
- integration test environments
- image builds with large dependency layers
- local AI, media, or indexing services

## Use A Real Linux Docker Engine

Docker on macOS normally runs through a Linux VM. A companion machine is already Linux, so containers, bind mounts, networking, cgroups, and storage behave more like they will on a real server.

This is useful when you want fewer macOS-specific Docker surprises.

## Keep Services Running

An always-on companion can keep development databases, caches, dashboards, tunnels, or home-lab services running while the Mac sleeps or moves between networks.

This works especially well for services that are useful across projects:

- databases
- reverse proxies
- Home Assistant adjacent tooling
- build caches
- internal dashboards
- CI or smoke-test runners

## Build ARM-Native Images

ARM Macs and ARM Linux boards share the same broad CPU architecture, but the companion runs native Linux. That makes it a convenient build host for `linux/arm64` images without relying on emulation.

You can still build multi-platform images with Buildx when needed, but the default ARM Linux path is simple and fast.

## Separate State From The Laptop

Docker data can grow quickly. Putting Docker's `data-root` on SSD/NVMe attached to the companion keeps container layers, volumes, logs, and caches off the Mac.

This is helpful when the Mac has limited internal storage or when you want Docker state to survive Mac reinstalls, laptop swaps, or day-to-day project churn.

## Share A Trusted LAN Docker Host

Multiple Macs can point their Docker contexts at the same companion. That can be useful for a small home lab, pair programming setup, or one-person workflow across laptop and desktop machines.

Use SSH contexts by default. The optional LAN socket proxy is only for trusted networks where you understand the security risk.

## Keep A Local Fallback

The companion can be the default Docker host while Colima remains installed as a fallback. If the companion is offline, switch contexts and keep moving:

```sh
docker context use colima
```

When the companion is back:

```sh
docker context use arm-companion
```

## When Not To Use This

This setup is the wrong tool when:

- the companion is on an untrusted network
- network latency is high
- your workload needs large source-tree bind mounts over a slow link
- your project requires x86-only Linux images
- you cannot tolerate another machine becoming part of your development dependency chain

For those cases, keep Docker local or use a proper remote development environment.

