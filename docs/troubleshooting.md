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

## Docker Data Is On The Wrong Disk

Check:

```sh
docker info --format '{{.DockerRootDir}}'
findmnt /mnt/companion-ssd
```

Update `.env`, rerun `companion-remote`, and restart Docker.

