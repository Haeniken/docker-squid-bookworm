# Инструкции репозитория

Эти инструкции применяются ко всему репозиторию.

## Перед каждым коммитом

Запустите все проверки из корня репозитория. Не создавайте коммит, пока хотя
бы одна проверка завершается ошибкой.

1. Проверьте shell-скрипты, YAML, GitHub Actions, Dockerfile и документацию:

   ```bash
   shellcheck scripts/init.sh build/entrypoint.sh
   yamllint -d relaxed docker-compose.yml .github/workflows/*.yml
   actionlint
   hadolint build/Dockerfile
   markdownlint-cli2 README.md README.ru.md
   ```

2. Проверьте Compose и итоговый diff:

   ```bash
   docker compose config --quiet
   git diff --check
   ```

3. После автоматических или ручных исправлений повторите проверки.

Используйте те же инструменты и правила, которые указаны в
`.github/workflows/lint.yml`. Если нужных инструментов нет на хосте,
запускайте их во временных Docker-контейнерах.

При изменении `build/**`, `scripts/**`, `conf.d.example/**` или
`docker-compose.yml` дополнительно пересоберите image и проверьте обе
конфигурации Squid:

```bash
docker compose build --pull squid
docker run --rm \
  -v "$PWD/conf.d.example:/etc/squid/conf.d:ro" \
  --entrypoint /usr/sbin/squid \
  haeniken/squid:6.13 \
  -k parse -f /etc/squid/squid.conf
docker run --rm \
  -v "$PWD/conf.d:/etc/squid/conf.d:ro" \
  --entrypoint /usr/sbin/squid \
  haeniken/squid:6.13 \
  -k parse -f /etc/squid/squid.conf
```

При изменении зависимостей, `Dockerfile` или `docker-compose.yml` также
запустите Trivy до коммита:

```bash
trivy fs \
  --scanners vuln,misconfig,secret \
  --severity HIGH,CRITICAL \
  --ignore-unfixed \
  --skip-dirs .git \
  --skip-dirs logs \
  --skip-dirs data \
  .
trivy image \
  --scanners vuln,secret \
  --severity HIGH,CRITICAL \
  --ignore-unfixed \
  haeniken/squid:6.13
```

Для устранения уязвимостей разрешено и желательно обновлять базовый образ
Debian. По умолчанию используйте самый свежий поддерживаемый Debian stable с
последним point release; не оставайтесь на oldstable только ради сохранения
старой версии пакета. При выходе нового stable обновляйте codename базового
образа и совместимую версию Squid, затем повторяйте линтеры, сборку, parse
обеих конфигураций и Trivy. Не переходите на Debian testing или unstable без
явного требования задачи.

Считайте `conf.d.example/` версионируемым источником шаблонов. Не переносите в
него реальные адреса клиентов или другие данные из приватного `conf.d/`, если
это явно не требуется задачей.

Никогда не коммитьте `.env`, приватный `conf.d/`, учетные данные, токены,
runtime-логи, данные кеша, кеши Trivy и сгенерированные отчеты с чувствительными
данными.
