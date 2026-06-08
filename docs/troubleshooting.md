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

## Docker Context Works But Localhost Ports Fail

Some local tools use `localhost` ports even when Docker itself runs on the
companion. A Docker context only points the Docker CLI at the companion; it does
not make published container ports on the companion automatically appear on Mac
`localhost`.

Use the Mac dev tunnel healer:

```sh
DOCKER_CONTEXT_NAME=radxa \
COMPANION_HOST=rock-5a.local \
COMPANION_HOST_FALLBACKS="192.0.2.10" \
COMPANION_USER=eduardo \
COMPANION_SSH_ALIAS=radxa \
COMPANION_DOCKER_ENDPOINT=tcp://rock-5a.local:23750 \
./install.sh mac-dev-tunnels
```

For a persistent self-healing background check:

```sh
./install.sh mac-dev-tunnels-agent-install
```

By default the healer reads `docker --context "$DOCKER_CONTEXT_NAME" ps`,
mirrors every published TCP host port onto Mac `127.0.0.1`, stops Colima only
when Colima owns one of those ports, and repairs broken SSH forwards on the next
watch pass. The launchd watcher starts retrying after 5 seconds, exponentially
backs off on failures, caps retries at 60 seconds by default, and bounds each
Docker endpoint probe to 5 seconds when `gtimeout`/`timeout` is available.

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

## Docker Data Is On The Wrong Disk

Check:

```sh
docker info --format '{{.DockerRootDir}}'
findmnt /mnt/companion-ssd
```

Update `.env`, rerun `companion-remote`, and restart Docker.
