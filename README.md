# ДЗ 3: Docker, Redis и восстановление (10 баллов)

Приложение со счётчиком упаковано в Docker. Исходники в `app/` взяты без
изменений из [шаблона](https://github.com/null-ref-exc/hw_3_template/tree/137f87b9774f7b71c123f0e2891f39716d4d8231/app).
Условия: [ДЗ по Docker](https://github.com/Nikfilk2030/missing_semester_hse_cs/tree/main/2026/amcs/year_1/hw_3).

## Требования

Нужны установленный и запущенный Docker и команда `curl`.
Все команды ниже выполняются из папки с этим README и Dockerfile.

На Mac, если терминал не находит команду `docker`, перед выполнением команд
добавьте инструменты установленного Docker Desktop в PATH текущего терминала:

```sh
export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
```

## Сборка

```sh
docker build -t counter-hw:basic .
```

`-t` задаёт имя и тег образа. Точка указывает контекст сборки — текущую папку.

## Запуск

```sh
docker run -d --name counter-basic \
  -p 127.0.0.1:8080:8000 \
  -e GREETING='Привет, Артём!' \
  -e STORAGE=sqlite \
  counter-hw:basic
```

- `-d`: контейнер работает в фоне.
- `--name`: имя контейнера для команд просмотра логов и остановки.
- `-p`: порт 8080 компьютера перенаправляется на порт 8000 контейнера;
  доступ открыт через локальный адрес компьютера.
- `-e`: передаёт переменные окружения приложению.

На этом уровне используется SQLite: приложение создаёт `/data/counter.db`
внутри контейнера. После удаления контейнера эти данные пропадут.

## Проверка и сохранение результатов

Дождаться готовности (не более 30 попыток, каждая с тайм-аутом 2 секунды):

```sh
for attempt in $(seq 1 30); do
  if curl --max-time 2 -fsS http://127.0.0.1:8080/readyz; then
    break
  fi
  sleep 1
done
curl --max-time 2 -fsS http://127.0.0.1:8080/readyz
```

Если последняя команда завершилась с ошибкой, сначала посмотрите
`docker logs counter-basic` и устраните причину.

Выполнить запросы и сохранить ответы:

```sh
mkdir -p reports
curl --max-time 5 -fsS http://127.0.0.1:8080/ > reports/01-initial.json
curl --max-time 5 -fsS -X POST http://127.0.0.1:8080/increment > reports/02-increment.json
curl --max-time 5 -fsS -X POST http://127.0.0.1:8080/increment > reports/03-increment.json
curl --max-time 5 -fsS http://127.0.0.1:8080/ > reports/04-final.json
cat reports/*.json
docker logs counter-basic > reports/container.log 2>&1
cat reports/container.log
```

Для нового контейнера ожидаются значения `count`: **0, 1, 2, 2**.
Во всех четырёх ответах поле `greeting` должно содержать `Привет, Артём!`,
а поле `storage` — `sqlite`. GET не меняет счётчик, POST увеличивает на 1.
В логах должны быть сообщение о запуске и записи HTTP-запросов.

Сборка и запуск проверены 22 ноября 2026 года на Mac с Apple Silicon:
Docker Engine 29.9.3, Docker Desktop 4.99.0. Фактические значения счётчика:
**0, 1, 2, 2**; приветствие и тип хранилища совпали с ожидаемыми.
Ответы и настоящие логи сохранены в `reports/`.
Краткий отчёт: [reports/README.md](reports/README.md).

## Остановка и удаление

После сохранения логов:

```sh
docker stop counter-basic
docker rm counter-basic
```

Для нового запуска повторите команду `docker run`. У нового контейнера
счётчик снова начинается с нуля.

## Как устроен Dockerfile

1. `FROM` выбирает базовый образ с Python 3.13.
2. `WORKDIR` задаёт рабочую папку внутри образа.
3. Сначала копируется `requirements.txt` и устанавливаются зависимости.
   Этот слой можно использовать повторно, пока зависимости не менялись.
4. `COPY app/app.py .` копирует код приложения.
5. `PYTHONUNBUFFERED=1` отключает буферизацию вывода Python.
6. `EXPOSE 8000` описывает порт приложения. Публикацию порта выполняет
   параметр `-p` в `docker run`.
7. `CMD` задаёт команду запуска приложения.

`.dockerignore` исключает ненужные локальные файлы из контекста сборки.

## Compose: запуск с сохранением данных (6 баллов)

Проверено: после `docker compose -f compose.sqlite.yaml down` и `docker compose -f compose.sqlite.yaml up -d` контейнер
получил новый ID, а счётчик сохранил значение 2.
Фактические ответы и логи: [отчёт Compose](reports/compose/README.md).

`compose.sqlite.yaml` описывает сервис `app`: сборку образа, порты, переменные
окружения и подключение именованного volume `counter_data` к `/data`.
SQLite записывает счётчик в `/data/counter.db`. Volume существует отдельно
от контейнера, поэтому данные сохраняются после удаления контейнера.
У volume нет фиксированного глобального имени: Compose добавляет имя проекта.

Подготовьте настройки и запустите приложение:

```sh
cp .env.example .env
docker compose -f compose.sqlite.yaml up -d --build
```

В `.env` настраиваются:

| Переменная | Пример | Назначение |
| --- | --- | --- |
| `HOST_PORT` | `8081` | Порт на компьютере |
| `GREETING` | `'Привет, Артём!'` | Приветствие в JSON-ответах |

Порт 8081 выбран, чтобы Compose мог работать одновременно с контейнером
базового уровня на порту 8080. Внутри контейнера приложение слушает 8000.
После изменения `.env` выполните `docker compose -f compose.sqlite.yaml up -d`, чтобы применить настройки.
`.env` исключён из Git; для сдачи добавлен `.env.example`.

Для команд проверки задайте адрес с выбранным в `.env` портом:

```sh
BASE_URL=http://127.0.0.1:8081
```

Если выбрали другой порт, замените 8081 в этой строке.
Перед запросами дождитесь готовности:

```sh
for attempt in $(seq 1 30); do
  if curl --max-time 2 -fsS "$BASE_URL/readyz"; then
    break
  fi
  sleep 1
done
curl --max-time 2 -fsS "$BASE_URL/readyz"
```

Продолжайте проверку, только если последняя команда успешна.
На пустом volume начальный счётчик равен 0; следующие два запроса дадут 1 и 2:

```sh
curl --max-time 5 -fsS "$BASE_URL/"
curl --max-time 5 -fsS -X POST "$BASE_URL/increment"
curl --max-time 5 -fsS -X POST "$BASE_URL/increment"
curl --max-time 5 -fsS "$BASE_URL/"
```

Запомните последнее значение `count`. Удалите контейнер и создайте заново:

```sh
docker compose -f compose.sqlite.yaml ps -q app
docker compose -f compose.sqlite.yaml down
docker compose -f compose.sqlite.yaml up -d
```

Повторите ожидание готовности из блока выше, затем выполните:

```sh
docker compose -f compose.sqlite.yaml ps -q app
curl --max-time 5 -fsS "$BASE_URL/"
docker compose -f compose.sqlite.yaml logs --no-color app
```

Идентификатор контейнера должен измениться, а `count` — остаться прежним.
Важно выполнять команды из той же папки и с тем же именем Compose-проекта:
другой проект получит отдельный volume.

`docker compose -f compose.sqlite.yaml down` удаляет контейнер и сеть, сохраняя именованный volume.
В проверке не используйте `docker compose -f compose.sqlite.yaml down -v`: эта команда удаляет
также volume со счётчиком.

## Redis: отдельное хранилище (8 баллов)

Все проверки уровня 8 выполнены успешно: после пересоздания проекта
сохранился счётчик 3, во время отключения Redis получены коды 200/503/503,
после возвращения Redis — значения 3 и 4 без перезапуска приложения.
Фактические ответы и логи: [отчёт Redis](reports/redis/README.md).

Основной `compose.yaml` теперь запускает два сервиса: `app` и `redis`.
Приложение использует `STORAGE=redis` и `REDIS_URL=redis://redis:6379/0`.
Имя `redis` разрешается во внутренней сети Compose. Порт Redis на компьютер
не публикуется; снаружи доступен только порт приложения.

Сервис Redis сохраняет данные в AOF (`--appendonly yes`) с синхронизацией
на диск каждую секунду (`--appendfsync everysec`). Именованный volume
`redis_data` подключён к `/data`. При штатной остановке Redis сбрасывает
оставшиеся записи на диск. SQLite из уровня 6 хранится в отдельном volume;
перенос счётчика между SQLite и Redis заданием не требуется.

Проверка готовности Redis выполняет `redis-cli ping`, проверка приложения
обращается к `/readyz`. Приложение запускается после готовности Redis
благодаря `depends_on` с `condition: service_healthy`.
`/healthz` проверяет, что HTTP-сервер жив; `/readyz` — что доступно хранилище.
При остановке Redis healthcheck приложения может показать `unhealthy`,
но HTTP-сервер продолжает работать. Healthcheck сам по себе контейнер
не перезапускает.

Запуск с теми же настройками `.env`:

```sh
# Если .env ещё не создан:
cp .env.example .env
docker compose up -d --build --wait --wait-timeout 90
docker compose ps
BASE_URL=http://127.0.0.1:8081
```

Не копируйте `.env.example` повторно поверх собственных настроек.
Для уровня 6 сохранён `compose.sqlite.yaml`. Оба варианта используют одно
имя проекта и порт, поэтому переключайтесь между ними последовательно:
выполните `down` с текущим файлом, затем `up` с нужным.

### Сохранность данных

```sh
curl --max-time 5 -fsS -X POST "$BASE_URL/increment"
curl --max-time 5 -fsS -X POST "$BASE_URL/increment"
curl --max-time 5 -fsS -X POST "$BASE_URL/increment"
curl --max-time 5 -fsS "$BASE_URL/"
# Запишите полученное count как N.
docker compose down
docker compose up -d --wait --wait-timeout 90
curl --max-time 5 -fsS "$BASE_URL/"
```

Последний GET должен вернуть N. Не добавляйте `-v` к `down`.

### Отключение и возвращение Redis

```sh
docker compose ps -q app
docker compose stop redis
curl --max-time 5 -sS -w '\nHTTP %{http_code}\n' "$BASE_URL/healthz"
curl --max-time 5 -sS -w '\nHTTP %{http_code}\n' "$BASE_URL/readyz"
curl --max-time 5 -sS -X POST -w '\nHTTP %{http_code}\n' "$BASE_URL/increment"
```

Ожидаются коды 200, 503 и 503 соответственно. В этой проверке у curl
нет `-f`, чтобы вывести тело ответа и для ожидаемой ошибки HTTP 503.

```sh
docker compose start --wait --wait-timeout 90 redis
# Дождитесь готовности приложения без его перезапуска:
for attempt in $(seq 1 30); do
  if curl --max-time 2 -fsS "$BASE_URL/readyz"; then
    break
  fi
  sleep 1
done
curl --max-time 2 -fsS "$BASE_URL/readyz"
# Продолжайте, только если последняя команда успешна.
curl --max-time 5 -fsS "$BASE_URL/"
curl --max-time 5 -fsS -X POST "$BASE_URL/increment"
docker compose ps -q app
docker compose ps
docker compose logs --no-color app redis
```

GET должен вернуть N, следующий POST — N + 1. ID контейнера приложения
должен совпасть с ID перед остановкой Redis.

## Автоматическая проверка восстановления (10 баллов)

Два последовательных запуска финальной версии скрипта завершились
с кодом 0. Выводы: [первый](reports/check/run-1.log),
[второй](reports/check/run-2.log). [Итоговый отчёт](reports/check/README.md)
содержит результаты, параметры ограничений и подтверждение очистки.

В основном `compose.yaml` приложение работает с UID/GID `10001:10001`,
корневая файловая система доступна только для чтения (`read_only: true`),
лимит памяти — 256 MiB (`mem_limit: 256m`), CPU — 1 (`cpus: 1.0`).
В режиме Redis приложение не требует локальной записи данных.
Ограничения заданы только для `app`; Redis должен писать в свой volume.

Запуск проверки из корня решения:

```sh
./scripts/check.sh
```

Нужны Docker с Compose и curl, а также обычная Unix-оболочка и стандартные
системные утилиты. Python, Redis и tar на компьютере устанавливать не нужно:
скрипт запускает их внутри контейнеров. На Mac при необходимости сначала
добавьте Docker в PATH командой из раздела «Требования».

Скрипт не использует работающий основной проект и его данные. Он создаёт
уникальное имя проекта и получает свободный порт от Docker (`HOST_PORT=0`).
Проверки JSON и ограничений процесса выполняет Python внутри `app`.

Последовательность проверки:

1. Создать отдельный проект с новым volume; дождаться готовности сервисов.
2. Проверить ненулевой UID, read-only rootfs, лимиты RAM и CPU.
3. Проверить исходный счётчик 0 и три POST, дающие 1, 2, 3.
4. Пересоздать только `app`; проверить новое ID приложения, прежнее ID Redis
   и прежний счётчик 3.
5. Выполнить `down` без `-v` и повторный `up`; проверить прежний счётчик 3.
6. Остановить Redis; проверить `/healthz` = 200, `/readyz` = 503,
   `POST /increment` = 503.
7. Запустить только Redis; получить GET = 3, следующий POST = 4.
   Убедиться, что ID, время старта и RestartCount приложения не изменились.
8. Штатно остановить приложение и Redis. Скопировать весь `/data` в tar-архив
   на компьютере, сохраняя структуру, владельцев и права файлов.
9. Удалить исходный тестовый проект вместе с volumes через `down -v`.
10. Создать другой пустой проект, распаковать архив в его volume до запуска
    Redis. Проверить восстановленный счётчик 4 и следующий POST = 5.
11. Через `trap` удалить оба тестовых проекта, их volumes, сети, локальные
    образы приложения и вспомогательный контейнер. Внешний архив сохранить.

Внешние резервные копии создаются в `backups/`. Эта папка исключена из Git
и контекста Docker; сами архивы доступны локально после запуска скрипта.
Архив создаётся из остановленного Redis, поэтому файлы AOF не изменяются
во время копирования. Восстановление проверяется после удаления исходного
volume: результат не может опираться на старое хранилище.

У HTTP-запросов есть тайм-ауты соединения и ответа. Ожидание healthcheck
ограничено 90 секундами; дополнительное ожидание `/readyz` — 30 попытками,
каждая с тайм-аутом 2 секунды и паузой 1 секунду. POST не повторяются
автоматически, чтобы не увеличить счётчик дважды при сетевом сбое.

При ошибке скрипт печатает `ERROR` с названием этапа, выводит последние
логи и завершается с ненулевым кодом. Очистка выполняется и при ошибках,
и при сигналах HUP/INT/TERM. SIGKILL и аварийное выключение компьютера
не позволяют оболочке выполнить trap.
Фиксированных `container_name` и общего volume между проектами нет.

Для сохранения вывода двух запусков:

```sh
mkdir -p reports/check
./scripts/check.sh > reports/check/run-1.log 2>&1
# Проверьте код завершения предыдущей команды: должен быть 0.
cat reports/check/run-1.log
./scripts/check.sh > reports/check/run-2.log 2>&1
# Проверьте код завершения предыдущей команды: должен быть 0.
cat reports/check/run-2.log
```

Успешный прогон заканчивается строкой:
`SUCCESS: recovery verified; test resources removed`.
