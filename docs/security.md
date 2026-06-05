# Security

## Prefer SSH

Docker over SSH is the recommended mode:

```sh
docker context create arm-companion --docker host=ssh://user@armbox.local
```

The remote user must be allowed to access the Docker socket. This is powerful: membership in the `docker` group is effectively root-equivalent on that host.

## Avoid Raw TCP Unless You Mean It

The optional LAN proxy exposes `/var/run/docker.sock` over TCP with `socat`. Anyone who can reach that port can control Docker, mount host paths, and usually gain root-level control of the companion.

Use the proxy only when all are true:

- the network is trusted
- the port is firewalled or VPN-restricted
- the host is not exposed to the internet
- you understand the operational risk

If you need network Docker access beyond a private LAN, use SSH or TLS-protected Docker daemon access instead.

## Public Repo Hygiene

- Keep `.env` private.
- Do not commit host IPs, usernames, API tokens, SSH private keys, Home Assistant tokens, or NFS paths with personal names.
- Publish examples with placeholders.

