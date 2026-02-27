# Squid Docker Setup

[![Docker](https://img.shields.io/badge/Docker-Ready-2496ED?style=flat-square&logo=docker)](https://www.docker.com/)
[![Debian](https://img.shields.io/badge/Debian-12%20Bookworm-A81D33?style=flat-square&logo=debian)](https://www.debian.org/)
[![Squid](https://img.shields.io/badge/Squid-5.7-2E8B57?style=flat-square)](http://www.squid-cache.org/)
[![OpenSSL](https://img.shields.io/badge/OpenSSL-enabled-721412?style=flat-square&logo=openssl)](https://www.openssl.org/)
[![Docker Compose](https://img.shields.io/badge/Compose-v2-2496ED?style=flat-square&logo=docker)](https://docs.docker.com/compose/)
[![Docker Image CI](https://github.com/Haeniken/docker-squid-bookworm/actions/workflows/docker-image.yml/badge.svg)](https://github.com/Haeniken/docker-squid-bookworm/actions/workflows/docker-image.yml)
[![Lint](https://github.com/Haeniken/docker-squid-bookworm/actions/workflows/lint.yml/badge.svg)](https://github.com/Haeniken/docker-squid-bookworm/actions/workflows/lint.yml)
[![Security Scan](https://github.com/Haeniken/docker-squid-bookworm/actions/workflows/security.yml/badge.svg)](https://github.com/Haeniken/docker-squid-bookworm/actions/workflows/security.yml)

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

Rotation is configured directly in `access_log ... rotate=7`, so Debian `logfile_rotate` does not override it.

## Verify Squid UID/GID in Container

```bash
docker exec squid sh -lc 'id proxy; getent passwd proxy'
```

If UID/GID differ, pass them to `scripts/init.sh`.

## Push Without Leaking Private Config

```bash
git status
git check-ignore -v conf.d/*
```

If `conf.d` was tracked before:

```bash
git rm --cached -r conf.d
```

Then push:

```bash
git add .
git commit -m "squid: private conf.d flow + unified init script"
git branch -M main
git remote add origin <YOUR_REPO_URL>
git push -u origin main
```

## Troubleshooting

`FATAL: Unable to find configuration file: /etc/squid/conf.d/*.conf`

- Cause: `./conf.d` is empty or missing on host; bind mount hides image defaults.
- Fix:

```bash
./scripts/init.sh --copy-only
sudo ./scripts/init.sh --perms-only --user "$USER"
dc up -d --build
```
