# Squid в Docker

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

Этот проект запускает forward-прокси Squid в Docker для исходящих API/web-запросов.

## Структура

- `docker-compose.yml` - описание контейнера, портов и томов.
- `build/Dockerfile` - сборка образа и установка пакетов Squid.
- `build/entrypoint.sh` - инициализация кэша и запуск Squid.
- `conf.d.example/*.conf` - публичные шаблоны.
- `conf.d/*.conf` - приватные runtime-конфиги (игнорируются Git, монтируются в контейнер).
- `scripts/init.sh` - единый скрипт для копирования шаблонов и выставления прав/ACL.
- `data/cache` - bind mount для `/var/spool/squid`.
- `logs` - bind mount для `/var/log/squid`.

Примечание: в образе оставлен только минимальный placeholder-конфиг; реальные runtime-правила должны приходить с хоста из `./conf.d`.

## Поток приватных конфигов

1. Реальные секреты/IP храните только в `./conf.d`.
2. Публичные примеры храните только в `./conf.d.example`.
3. `.gitignore` скрывает `./conf.d`.

## Скрипт инициализации

`./scripts/init.sh` поддерживает три режима:

- по умолчанию: копирует недостающие конфиги из `conf.d.example` в `conf.d` и выставляет права/ACL;
- `--copy-only`: только копирование шаблонов;
- `--perms-only`: только права/ACL.

Опции:

- `--user <name>`: пользователь хоста для чтения логов/кэша (по умолчанию `SUDO_USER`/`USER`)
- `--squid-uid <uid>`: UID Squid в контейнере (по умолчанию `13`)
- `--squid-gid <gid>`: GID Squid в контейнере (по умолчанию `13`)

Примеры:

```bash
chmod +x ./scripts/init.sh
./scripts/init.sh --copy-only
# отредактируйте ./conf.d/*.conf своими значениями
sudo ./scripts/init.sh --perms-only --user "$USER"
# или полный init одной командой
sudo ./scripts/init.sh --user "$USER"
```

## Сборка и запуск

```bash
dc up -d --build
docker exec squid squid -k parse
```

## SMP (2 воркера)

Эта сборка поддерживает реальный SMP-режим (больше одного воркера), если в `conf.d/20-performance.conf` задано `workers`.
Правило: значение `workers` не должно превышать количество доступных CPU-ядер контейнера/хоста.

Проверка ролей процессов:

```bash
docker logs squid | grep -E 'Process Roles|kid[0-9]+\\|'
docker exec squid sh -lc "ps -eo pid,ppid,user,cmd | grep '[s]quid'"
```

Ожидаемо при `workers 2`:
- два процесса с ролью `worker` (`kid1`, `kid2`);
- один процесс `coordinator`;
- в parse-логе видна строка `workers 2`.

## Логирование

Настроенные файлы:

- `/var/log/squid/access.log` - стандартный формат Squid.
- `/var/log/squid/denied.log` - отклоненные ответы (`4xx-5xx`) в подробном формате.
- `/var/log/squid/connect.log` - успешный CONNECT-трафик в подробном формате.
- `/var/log/squid/http.log` - успешный non-CONNECT HTTP-трафик в подробном формате.

Ротация задана прямо в `access_log ... rotate=7`, поэтому `logfile_rotate` из Debian это не перезапишет.

## Как узнать UID/GID Squid в контейнере

```bash
docker exec squid sh -lc 'id proxy; getent passwd proxy'
```

Если UID/GID отличаются, передайте их в `scripts/init.sh`.

## Пуш в репозиторий без утечки приватного `conf.d`

```bash
git status
git check-ignore -v conf.d/*
```

Если `conf.d` уже был в индексе:

```bash
git rm --cached -r conf.d
```

Далее пуш:

```bash
git add .
git commit -m "squid: private conf.d flow + unified init script"
git branch -M main
git remote add origin <URL_ВАШЕГО_РЕПО>
git push -u origin main
```

## Troubleshooting / Диагностика

`FATAL: Unable to find configuration file: /etc/squid/conf.d/*.conf`

- Причина: на хосте пустой или отсутствует `./conf.d`; bind mount скрывает дефолтные конфиги из образа.
- Решение:

```bash
./scripts/init.sh --copy-only
sudo ./scripts/init.sh --perms-only --user "$USER"
dc up -d --build
```
