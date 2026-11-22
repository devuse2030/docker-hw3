# Отчёт: отдельное хранилище Redis (8 баллов)

Дата проверки: 22 ноября 2026 года (Москва).
Среда: Docker Engine 29.9.3, Docker Compose v5.7.0, Apple Silicon.
Код приложения не изменялся; хеши исходных файлов совпадают с шаблоном.

## Запуск и данные

```sh
docker compose config
docker compose up -d --build --wait --wait-timeout 90
docker compose ps
curl --max-time 5 -fsS http://127.0.0.1:8081/
curl --max-time 5 -fsS -X POST http://127.0.0.1:8081/increment
curl --max-time 5 -fsS -X POST http://127.0.0.1:8081/increment
curl --max-time 5 -fsS -X POST http://127.0.0.1:8081/increment
curl --max-time 5 -fsS http://127.0.0.1:8081/
docker compose ps -q app
docker compose logs --no-color app redis
docker compose down
docker compose up -d --wait --wait-timeout 90
curl --max-time 5 -fsS http://127.0.0.1:8081/
```

Начальное значение: 0. Три POST вернули последовательно 1, 2 и 3.
Перед удалением проекта N = 3, после повторного создания GET вернул N = 3.
Идентификаторы приложения до и после `down` различаются.
Использовался `down` без `-v`; volume `hw_3_solution_redis_data` сохранился.

| Проверка | Фактический ответ |
| --- | --- |
| Начальный GET, count = 0 | [01-initial.json](01-initial.json) |
| Три POST, count = 1, 2, 3 | [первый](increment-1.json), [второй](increment-2.json), [третий](increment-3.json) |
| GET перед удалением, count = 3 | [02-before-down.json](02-before-down.json) |
| GET после пересоздания, count = 3 | [03-after-down.json](03-after-down.json) |

Логи: [первый запуск](start.log), [статус сервисов](ps-initial.txt),
[приложение и Redis перед удалением](logs-before-down.txt),
[down](down.log), [повторный up](up-after.log).
ID приложения: [до down](app-before-down.txt), [после down](app-before-outage.txt).

## Отключение Redis

```sh
docker compose stop redis
curl --max-time 5 -sS -w '\nHTTP %{http_code}\n' http://127.0.0.1:8081/healthz
curl --max-time 5 -sS -w '\nHTTP %{http_code}\n' http://127.0.0.1:8081/readyz
curl --max-time 5 -sS -X POST -w '\nHTTP %{http_code}\n' http://127.0.0.1:8081/increment
```

При выполнении ответы и HTTP-коды сохранялись отдельно через `-o` и `-w`.

| Запрос | HTTP | Ответ |
| --- | --- | --- |
| GET /healthz | 200 | [healthz-stopped.json](healthz-stopped.json) |
| GET /readyz | 503 | [readyz-stopped.json](readyz-stopped.json) |
| POST /increment | 503 | [increment-stopped.json](increment-stopped.json) |

Файлы фактических кодов: [healthz](healthz-stopped.status),
[readyz](readyz-stopped.status), [increment](increment-stopped.status).
Приложение продолжало обслуживать HTTP, а запросы к недоступному хранилищу
вернули `{"error": "storage_unavailable"}`.

## Восстановление

```sh
docker compose start --wait --wait-timeout 90 redis
curl --max-time 2 --retry 15 --retry-all-errors --retry-delay 1 \
  --retry-max-time 30 -fsS http://127.0.0.1:8081/readyz
curl --max-time 5 -fsS http://127.0.0.1:8081/
curl --max-time 5 -fsS -X POST http://127.0.0.1:8081/increment
docker compose ps -q app
docker compose ps
docker compose logs --no-color app redis
docker compose exec -T redis redis-cli CONFIG GET appendonly appendfsync
```

После запуска Redis `/readyz` вернул HTTP 200.
GET вернул N = 3: [04-restored.json](04-restored.json).
Следующий POST вернул N + 1 = 4: [05-next-increment.json](05-next-increment.json).
Неуспешный POST во время сбоя счётчик не увеличил.

Приложение не перезапускалось: его ID, время запуска и RestartCount
совпали до и после сбоя Redis. RestartCount = 0.
ID: [до](app-before-outage.txt), [после](app-after-outage.txt).
StartedAt и RestartCount: [до](process-before-outage.txt), [после](process-after-outage.txt).
Эти данные получены командой `docker inspect --format
'{{.State.StartedAt}} {{.RestartCount}}' ID_КОНТЕЙНЕРА`.

Оба сервиса в конце имеют статус `healthy`:
[ps-final.txt](ps-final.txt). Опубликован только порт приложения 8081;
запись `6379/tcp` у Redis описывает внутренний порт без публикации на хост.
Настройки Redis: `appendonly=yes`, `appendfsync=everysec`:
[persistence-config.txt](persistence-config.txt).
Том Redis подключён к `/data` в `compose.yaml`.

Дополнительные логи: [stop Redis](stop-redis.log),
[start Redis](start-redis.log), [логи восстановления](logs-recovery.txt).
Временные метки внутри логов контейнеров указаны в UTC.
