# Squid в Docker

[![Docker](https://img.shields.io/badge/Docker-Ready-2496ED?style=flat-square&logo=docker)](https://www.docker.com/)
[![Docker Compose](https://img.shields.io/badge/Compose-v2-2496ED?style=flat-square&logo=docker)](https://docs.docker.com/compose/)
[![Debian](https://img.shields.io/badge/Debian-13%20Trixie-A81D33?style=flat-square&logo=debian)](https://www.debian.org/)
[![Squid](https://img.shields.io/badge/Squid-6.13-2E8B57?style=flat-square)](http://www.squid-cache.org/)
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

В этом репозитории `cache_dir` намеренно отключен при `workers 2`.
Причина: общий UFS `cache_dir` при `workers > 1` может вызывать assertion/restart loop воркеров (`Controller.cc:930`).
Если нужен дисковый кэш, переключитесь на `workers 1` и снова включите `cache_dir`.

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

В подробных логах используется читаемое поле времени (`ts=`) в стиле Nginx: `YYYY-MM-DD HH:MM:SS TZ` (настроено через `logformat detailed` в `conf.d/99-logging.conf`).

Логи Squid пишутся как обычные файлы (`access.log`, `denied.log`, `connect.log`, `http.log`) без ротации внутри контейнера. Ротацию делайте на хосте.

`./scripts/init.sh --perms-only` (или полный режим) создаёт/обновляет:

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

На практике скрипт подставляет фактический путь проекта и выбранные `--squid-uid/--squid-gid`.

## Как узнать UID/GID Squid в контейнере

```bash
docker exec squid sh -lc 'id proxy; getent passwd proxy'
```

Если UID/GID отличаются, передайте их в `scripts/init.sh`.

## Troubleshooting / Диагностика

Быстрый чек-лист из 5 команд:

```bash
dc ps
docker logs squid --tail=200
docker exec squid squid -k parse -f /etc/squid/squid.conf
docker exec squid sh -lc "grep -R --line-number '^workers\\|^cache_dir\\|^http_access' /etc/squid/conf.d/*.conf"
curl -x 172.20.6.4:3128 https://jsonplaceholder.typicode.com/todos/1
```

1. Быстрая проверка реального трафика

Позитивный тест (публичный API через прокси):

```bash
curl -x 172.20.6.4:3128 https://jsonplaceholder.typicode.com/todos/1
```

Ожидаемый ответ:

```json
{"userId":1,"id":1,"title":"delectus aut autem","completed":false}
```

Негативный тест (ACL-запрет небезопасного порта):

```bash
curl -x 172.20.6.4:3128 http://example.com:210/
```

Ожидаемый результат:

- клиент получает `403 Forbidden`;
- в access.log Squid есть запись `TCP_DENIED/403`.

1. `FATAL: Unable to find configuration file: /etc/squid/conf.d/*.conf`

Причина: на хосте пустой или отсутствует `./conf.d`; bind mount скрывает дефолтные конфиги из образа.

Решение:

```bash
./scripts/init.sh --copy-only
sudo ./scripts/init.sh --perms-only --user "$USER"
dc up -d --build
```

1. `curl: (7) Failed to connect ... Connection refused`

Причина: контейнер не запущен/падает, либо порт `3128` не опубликован/недоступен.

Решение:

```bash
dc ps
docker logs squid --tail=200
ss -ltn | grep 3128
```

1. Цикл рестартов с `assertion failed: Controller.cc:930`

Причина: `workers > 1` и общий UFS `cache_dir`.

Решение:

- оставить `workers 2` и отключить `cache_dir` (дефолт в этом репозитории), или
- поставить `workers 1`, если нужен дисковый кэш.

1. Неожиданный `TCP_DENIED/403` для разрешенных клиентов

Причина: исходный IP не попадает под `acl localnet` в `conf.d/10-access.conf`.

Решение:

- добавить реальный source IP/CIDR клиента в `acl localnet`;
- перепроверить конфиг и перезапустить контейнер.

1. Permission denied на файлах cache/logs

Причина: неверные права/ACL на хостовых `./data/cache` и `./logs`.

Решение:

```bash
sudo ./scripts/init.sh --perms-only --user "$USER"
```

1. `WARNING: no_suid: setuid(0): (1) Operation not permitted`

Это ожидаемое предупреждение для текущего hardened non-root запуска контейнера.
