# Squid Docker Setup

[![Docker](https://img.shields.io/badge/Docker-Ready-2496ED?style=flat-square&logo=docker)](https://www.docker.com/)
[![Docker Compose](https://img.shields.io/badge/Compose-v2-2496ED?style=flat-square&logo=docker)](https://docs.docker.com/compose/)
[![Debian](https://img.shields.io/badge/Debian-12%20Bookworm-A81D33?style=flat-square&logo=debian)](https://www.debian.org/)
[![Squid](https://img.shields.io/badge/Squid-5.7-2E8B57?style=flat-square)](http://www.squid-cache.org/)
[![OpenSSL](https://img.shields.io/badge/OpenSSL-enabled-721412?style=flat-square&logo=openssl)](https://www.openssl.org/)<br/>
[![Docker Image CI](https://github.com/Haeniken/docker-squid-bookworm/actions/workflows/docker-image.yml/badge.svg)](https://github.com/Haeniken/docker-squid-bookworm/actions/workflows/docker-image.yml)
[![Lint](https://github.com/Haeniken/docker-squid-bookworm/actions/workflows/lint.yml/badge.svg)](https://github.com/Haeniken/docker-squid-bookworm/actions/workflows/lint.yml)
[![Security Scan](https://github.com/Haeniken/docker-squid-bookworm/actions/workflows/security.yml/badge.svg)](https://github.com/Haeniken/docker-squid-bookworm/actions/workflows/security.yml)
[![Publish](https://github.com/Haeniken/docker-squid-bookworm/actions/workflows/publish.yml/badge.svg)](https://github.com/Haeniken/docker-squid-bookworm/actions/workflows/publish.yml)

[🇺🇸 English](README.md) | [🇷🇺 Русский](README.ru.md)

This project runs a forward Squid proxy in Docker for outbound API/web requests.

## Layout

- `docker-compose.yml` - container definition, port mapping, volumes.
- `build/Dockerfile` - image build and base Squid package installation.
- `build/entrypoint.sh` - cache initialization and Squid startup.
- `conf.d.example/*.conf` - public templates.
- `conf.d/*.conf` - private runtime configs (ignored by Git, mounted into container).
- `scripts/init.sh` - one script for template copy + permissions/ACL.
- `data/cache` - bind mount for `/var/spool/squid`.
- `logs` - bind mount for `/var/log/squid`.

Note: the image now includes only a minimal placeholder conf file; real runtime policy must come from host `./conf.d`.

## Private Config Flow

1. Keep real secrets/IPs only in `./conf.d`.
2. Keep shareable examples only in `./conf.d.example`.
3. `.gitignore` hides `./conf.d`.

## Init Script

`./scripts/init.sh` supports three modes:

- default: copy missing configs from `conf.d.example` to `conf.d` and apply permissions/ACL;
- `--copy-only`: only copy templates;
- `--perms-only`: only apply permissions/ACL.

Options:

- `--user <name>`: host user for read access (default: `SUDO_USER`/`USER`)
- `--squid-uid <uid>`: Squid UID in container (default: `13`)
- `--squid-gid <gid>`: Squid GID in container (default: `13`)

Examples:

```bash
chmod +x ./scripts/init.sh
./scripts/init.sh --copy-only
# edit ./conf.d/*.conf
sudo ./scripts/init.sh --perms-only --user "$USER"
# or run full init in one shot
sudo ./scripts/init.sh --user "$USER"
```

## Build and Run

```bash
dc up -d --build
docker exec squid squid -k parse
```

## SMP (2 Workers)

This setup supports real SMP mode (more than one worker) when `workers` is set in `conf.d/20-performance.conf`.
Rule of thumb: `workers` should not exceed the number of CPU cores available to the container/host.

In this repository, `cache_dir` is intentionally disabled when using `workers 2`.
Reason: shared UFS `cache_dir` with `workers > 1` may trigger worker assertion/restart loops (`Controller.cc:930`).
If you need on-disk cache, switch to `workers 1` and re-enable `cache_dir`.

Check process roles:

```bash
docker logs squid | grep -E 'Process Roles|kid[0-9]+\\|'
docker exec squid sh -lc "ps -eo pid,ppid,user,cmd | grep '[s]quid'"
```

Expected with `workers 2`:
- two processes with role `worker` (`kid1`, `kid2`);
- one `coordinator` process;
- `workers 2` appears during config parse.

## Logging

Configured files:

- `/var/log/squid/access.log` - default Squid format.
- `/var/log/squid/denied.log` - denied responses (`4xx-5xx`) in detailed format.
- `/var/log/squid/connect.log` - successful CONNECT traffic in detailed format.
- `/var/log/squid/http.log` - non-CONNECT successful HTTP traffic in detailed format.

Detailed logs use a human-readable timestamp field (`ts=`) in Nginx-like style: `YYYY-MM-DD HH:MM:SS TZ` (configured via `logformat detailed` in `conf.d/99-logging.conf`).

Squid file logs are written as plain files (`access.log`, `denied.log`, `connect.log`, `http.log`) without in-container rotation. Rotate them on the host.

`./scripts/init.sh --perms-only` (or full mode) creates/updates:

```conf
/home/container/docker/squid/logs/*.log {
    su root root
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0660 13 13
    copytruncate
}
```

At runtime, the script uses your actual project path and selected `--squid-uid/--squid-gid`.

## Verify Squid UID/GID in Container

```bash
docker exec squid sh -lc 'id proxy; getent passwd proxy'
```

If UID/GID differ, pass them to `scripts/init.sh`.

## Troubleshooting

Quick 5-command checklist:

```bash
dc ps
docker logs squid --tail=200
docker exec squid squid -k parse -f /etc/squid/squid.conf
docker exec squid sh -lc "grep -R --line-number '^workers\\|^cache_dir\\|^http_access' /etc/squid/conf.d/*.conf"
curl -x 172.20.6.4:3128 https://jsonplaceholder.typicode.com/todos/1
```

1. Real traffic smoke tests

Positive test (public API via proxy):

```bash
curl -x 172.20.6.4:3128 https://jsonplaceholder.typicode.com/todos/1
```

Expected response:

```json
{"userId":1,"id":1,"title":"delectus aut autem","completed":false}
```

Negative test (ACL deny on unsafe port):

```bash
curl -x 172.20.6.4:3128 http://example.com:210/
```

Expected result:
- client receives `403 Forbidden`;
- Squid access log contains `TCP_DENIED/403`.

2. `FATAL: Unable to find configuration file: /etc/squid/conf.d/*.conf`

Cause: `./conf.d` is empty or missing on host; bind mount hides image defaults.

Fix:

```bash
./scripts/init.sh --copy-only
sudo ./scripts/init.sh --perms-only --user "$USER"
dc up -d --build
```

3. `curl: (7) Failed to connect ... Connection refused`

Cause: container is down/crashing, or port `3128` is not published/reachable.

Fix:

```bash
dc ps
docker logs squid --tail=200
ss -ltn | grep 3128
```

4. Restart loop with `assertion failed: Controller.cc:930`

Cause: `workers > 1` with shared UFS `cache_dir`.

Fix:
- keep `workers 2` and disable `cache_dir` (current default in this repo), or
- set `workers 1` if you need on-disk cache.

5. Unexpected `TCP_DENIED/403` for allowed clients

Cause: source IP is not matched by `acl localnet` in `conf.d/10-access.conf`.

Fix:
- add the real client source IP/CIDR to `acl localnet`;
- re-parse config and restart container.

6. Permission denied on cache/log files

Cause: host ownership/ACL mismatch for mounted `./data/cache` and `./logs`.

Fix:

```bash
sudo ./scripts/init.sh --perms-only --user "$USER"
```

7. `WARNING: no_suid: setuid(0): (1) Operation not permitted`

This warning is expected in this hardened non-root container setup.
