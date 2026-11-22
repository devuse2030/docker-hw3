# Отчёт: Compose и данные (6 баллов)

Проверка выполнена 22 ноября 2026 года. Docker Compose v5.7.0.
Код приложения не изменялся.

Настройки `.env`: `HOST_PORT=8081`, `GREETING='Привет, Артём!'`.
Compose-проект: `hw_3_solution`; именованный volume:
`hw_3_solution_counter_data`, подключён к `/data`.

Команды выполнялись из папки решения:

```sh
docker compose config
docker compose up -d --build
curl --max-time 5 -fsS http://127.0.0.1:8081/readyz
curl --max-time 5 -fsS http://127.0.0.1:8081/
curl --max-time 5 -fsS -X POST http://127.0.0.1:8081/increment
curl --max-time 5 -fsS -X POST http://127.0.0.1:8081/increment
curl --max-time 5 -fsS http://127.0.0.1:8081/
docker compose ps -q app
docker compose logs --no-color app
docker compose down
docker compose up -d
```

После пересоздания первый запрос попал в момент запуска HTTP-сервера:
`curl: (52) Empty reply from server`. После ожидания готовности проверка
успешно продолжилась. Счётчик дополнительно не увеличивался.

```sh
curl --max-time 2 --retry 15 --retry-all-errors --retry-delay 1 \
  --retry-max-time 30 -fsS http://127.0.0.1:8081/readyz
curl --max-time 5 -fsS http://127.0.0.1:8081/
docker compose ps -q app
docker compose logs --no-color app
```

| Запрос | count | Фактический ответ |
| --- | --- | --- |
| Начальный GET / | 0 | [01-initial.json](01-initial.json) |
| Первый POST /increment | 1 | [02-increment.json](02-increment.json) |
| Второй POST /increment | 2 | [03-increment.json](03-increment.json) |
| GET / перед удалением | 2 | [04-before.json](04-before.json) |
| GET / после повторного создания | 2 | [05-after.json](05-after.json) |

Все перечисленные запросы вернули HTTP 200. Приветствие во всех ответах —
`Привет, Артём!`, тип хранилища — `sqlite`. Проверка `/readyz` также вернула
HTTP 200 до и после пересоздания.

Контейнер до удаления: `7b1d616a1a5b`.
Новый контейнер: `d5128dcb9113`.
Полные ID: [до](container-before.txt), [после](container-after.txt).
Контейнер действительно пересоздан; счётчик сохранился в именованном volume.

Логи: [приложение до удаления](logs-before.txt),
[удаление контейнера и сети](down.log), [повторный запуск](up-after.log),
[новый контейнер](logs-after.txt).
Команда `down` выполнялась без `-v`, volume не удалялся.
