# Отчёт: один контейнер

Дата проверки: 22 ноября 2026 года (Москва).
Среда: macOS, Apple Silicon, Docker Desktop 4.99.0, Docker Engine 29.9.3.

Образ успешно собран командой:

```sh
docker build -t counter-hw:basic .
```

Приложение запущено командой:

```sh
docker run -d --name counter-basic \
  -p 127.0.0.1:8080:8000 \
  -e GREETING='Привет, Артём!' \
  -e STORAGE=sqlite \
  counter-hw:basic
```

Проверка готовности:

```sh
curl --max-time 5 -fsS http://127.0.0.1:8080/readyz
```

Результат: HTTP 200, `{"status": "ready", "storage": "sqlite"}`.

Последовательно выполнены:

```sh
curl --max-time 5 -fsS http://127.0.0.1:8080/
curl --max-time 5 -fsS -X POST http://127.0.0.1:8080/increment
curl --max-time 5 -fsS -X POST http://127.0.0.1:8080/increment
curl --max-time 5 -fsS http://127.0.0.1:8080/
docker logs counter-basic
```

| Запрос | HTTP | Фактический count | Файл ответа |
| --- | --- | --- | --- |
| GET / | 200 | 0 | [01-initial.json](01-initial.json) |
| POST /increment | 200 | 1 | [02-increment.json](02-increment.json) |
| POST /increment | 200 | 2 | [03-increment.json](03-increment.json) |
| GET / | 200 | 2 | [04-final.json](04-final.json) |

Во всех ответах `greeting` равен `Привет, Артём!`, `storage` равен `sqlite`.
Подтверждено увеличение счётчика при POST и сохранение значения при GET.
Полный вывод `docker logs counter-basic`: [container.log](container.log).
Временные метки внутри контейнерных логов указаны в UTC.

Исходники приложения не изменялись. Проверены Git blob SHA-1 всех трёх
файлов относительно коммита шаблона `137f87b9774f7b71c123f0e2891f39716d4d8231`:

```text
app/app.py            85a3e5807ddf81705fdbbfbe4b0d9a896a7a02a6
app/requirements.txt  0cecdf573aaebc5f35cfe3a524815370f101c8f0
app/README.md         0a5840ee2b7d90d9eedbcbb298362b136748fd46
```
