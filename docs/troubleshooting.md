# Troubleshooting

## Docker Context Fails Over SSH

Check SSH first:

```sh
ssh arm-companion 'docker version || sudo docker version'
```

Then check the context:

```sh
docker context inspect arm-companion
docker --context arm-companion version
```

If the user was just added to the `docker` group, open a new SSH session.

## Hostname Resolves To The Wrong IP

If mDNS returns a Docker bridge address, enable the Avahi interface pin:

```sh
ENABLE_AVAHI_FIX=1
AVAHI_ALLOW_INTERFACES=end0
./install.sh companion-remote
```

Use `ip -br addr` on the companion to find the real LAN interface.

## NFS Mount Is Stale After The Mac Sleeps

Enable the NFS watchdog:

```sh
ENABLE_NFS_CLIENT=1
NFS_SERVER=mac.local
NFS_EXPORT=/Users/you/Repositories/project
NFS_MOUNT=/Users/you/Repositories/project
./install.sh companion-remote
```

Inspect:

```sh
systemctl status arm-companion-nfs-remount.timer
journalctl -u arm-companion-nfs-remount.service
tail -n 100 /var/log/arm-companion-nfs-remount.log
```

If the problem is the automount state itself, not just a stale NFS file handle,
switch to direct reconcile mode and redeploy:

```sh
NFS_RECONCILE_MODE=direct
NFS_RECONCILE_INTERVAL_SECONDS=15
./install.sh companion-remote
```

Then inspect:

```sh
systemctl status arm-companion-nfs-reconcile.timer
journalctl -u arm-companion-nfs-reconcile.service
```

## Docker Context Works But Localhost Ports Fail

Some local tools use `localhost` ports even when Docker itself runs on the
companion. A Docker context only points the Docker CLI at the companion; it does
not make published container ports on the companion automatically appear on Mac
`localhost`.

Use the Mac dev tunnel healer:

```sh
DOCKER_CONTEXT_NAME=arm-companion \
COMPANION_HOST=companion.local \
COMPANION_HOST_FALLBACKS="192.0.2.10" \
COMPANION_USER=your-user \
COMPANION_SSH_ALIAS=arm-companion \
./install.sh mac-dev-tunnels
```

For a persistent self-healing background check:

```sh
./install.sh mac-dev-tunnels-agent-install
```

By default the healer probes the configured Docker endpoint candidates, uses
the reachable endpoint to read published TCP host ports, falls back to SSH
`docker ps` if endpoint inspection fails, mirrors those ports onto Mac
`127.0.0.1`, stops Colima only when Colima owns one of those ports, and repairs
broken SSH forwards on the next watch pass. The launchd watcher starts retrying
after 5 seconds, exponentially backs off on failures, caps retries at 60
seconds by default, and bounds each Docker endpoint probe to 5 seconds when
`gtimeout`/`timeout` is available.

If mDNS is stale or intermittent, set `COMPANION_HOST_FALLBACKS` to one or more
direct IPs/hostnames. When `COMPANION_DOCKER_ENDPOINT` uses `COMPANION_HOST`,
the tunnel healer tries the original endpoint first and then equivalent
endpoints with each fallback host. When an SSH alias is configured, the healer
also tries `ssh://$COMPANION_SSH_ALIAS` as a transport fallback after TCP
endpoint candidates. Use `COMPANION_SSH_HOST` when the generated SSH alias
should point at a direct IP instead of the primary host name.
For endpoints that cannot be derived from the primary host, set full
space-separated `COMPANION_DOCKER_ENDPOINT_FALLBACKS`. Tune
`DEV_TUNNEL_DOCKER_PROBE_TIMEOUT_SECONDS` if a network needs longer probes.

Extra non-Docker forwards can be declared with `DEV_TUNNEL_FORWARDS`:

```sh
DEV_TUNNEL_FORWARDS="8080:127.0.0.1:8080 9000:service-name:9000"
```

Inspect:

```sh
lsof -nP -iTCP:<port> -sTCP:LISTEN
launchctl print gui/$(id -u)/com.arm-docker-companion.dev-tunnels
tail -n 100 ~/Library/Logs/com.arm-docker-companion.dev-tunnels.err.log
```

Failure pattern to recognize:

- The container is running and Docker shows a publish such as
  `127.0.0.1:<port>->6379/tcp` on the companion.
- The same port is refused on Mac `127.0.0.1` because no Mac-side SSH listener
  exists yet.
- The port may also be refused on the companion LAN IP when the container was
  intentionally published to companion loopback only.
- A service published as `0.0.0.0:<port>->...` may still work over the LAN,
  which proves the Docker host is up but does not fix loopback-only ports.

Do not fix this by changing the application repo to bind Redis or other
private development services to `0.0.0.0`. Repair the Mac tunnel instead:

```sh
./install.sh mac-dev-tunnels
launchctl kickstart -k gui/$(id -u)/com.arm-docker-companion.dev-tunnels
nc -vz 127.0.0.1 <port>
```

## Docker Data Is On The Wrong Disk

Check:

```sh
docker info --format '{{.DockerRootDir}}'
findmnt /mnt/companion-ssd
```

Update `.env`, rerun `companion-remote`, and restart Docker.

If the dangerous part is Docker silently falling back to rootfs when the SSD is
missing, turn on the storage guard:

```sh
ENABLE_DOCKER_STORAGE_GUARD=1
DOCKER_STORAGE_GUARD_INTERVAL_SECONDS=15
./install.sh companion-remote
```

Inspect:

```sh
systemctl status arm-companion-docker-storage-reconcile.timer
sudo /usr/local/bin/arm-companion-docker-storage-guard.sh status
findmnt -T "$COMPANION_DOCKER_DATA_ROOT"
```

## USB SSD Vanishes After A Power Event

First confirm whether Linux can see the storage at all:

```sh
lsusb
lsblk -f
ls -l /dev/disk/by-uuid
journalctl -k -b --no-pager | grep -Ei 'usb|uas|scsi|sd[a-z]|descriptor|enumerate|Cannot enable|not accepting'
```

If the expected UUID is missing and the kernel is repeatedly logging USB
descriptor or enumeration errors, the device is failing before the storage
guard can mount it. First enable the USB power policy so autosuspend does not
make the bridge easier to lose:

```sh
ENABLE_USB_STORAGE_POWER_POLICY=1
USB_STORAGE_BRIDGE_VENDOR_ID=<vendor-from-lsusb>
USB_STORAGE_BRIDGE_PRODUCT_ID=<product-from-lsusb>
./install.sh companion-remote
```

On USB-boot-independent boards, also enable the rate-limited reboot recovery
for the bridge-wedged state:

```sh
ENABLE_DOCKER_STORAGE_GUARD=1
ENABLE_USB_STORAGE_RECOVERY_REBOOT=1
USB_STORAGE_RECOVERY_MIN_UPTIME_SECONDS=180
USB_STORAGE_RECOVERY_REBOOT_COOLDOWN_SECONDS=21600
./install.sh companion-remote
```

This does not replace the hardware fix. Re-seat or replace the cable, enclosure,
hub, or power path when the errors keep returning. The recovery exists to handle
the common "bridge wedged until board reboot" state without letting Docker start
on the wrong filesystem.
