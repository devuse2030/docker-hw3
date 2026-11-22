#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
for tool in docker curl; do
    command -v "$tool" >/dev/null 2>&1 || {
        printf 'ERROR [requirements]: missing %s\n' "$tool" >&2
        exit 1
    }
done
if ! docker compose version >/dev/null; then
    printf 'ERROR [requirements]: Docker Compose unavailable\n' >&2
    exit 1
fi
if ! docker info >/dev/null; then
    printf 'ERROR [requirements]: Docker engine unavailable\n' >&2
    exit 1
fi

WORK=$(mktemp -d "${TMPDIR:-/tmp}/countercheck.XXXXXXXX")
PROJECT=$(basename "$WORK" | tr '[:upper:].' '[:lower:]-')
RESTORE_PROJECT="${PROJECT}-restore"
HELPER="${PROJECT}-helper"
ACTIVE_PROJECT=$PROJECT
STAGE=initialization
HOST_PORT=0
GREETING='Recovery check'
export HOST_PORT GREETING
: > "$WORK/empty.env"

compose_for() {
    target_project=$1
    shift
    docker compose --project-directory "$ROOT" --env-file "$WORK/empty.env" \
        -f "$ROOT/compose.yaml" -p "$target_project" "$@"
}

dc() { compose_for "$ACTIVE_PROJECT" "$@"; }

cleanup() {
    result=$?
    trap - 0 HUP INT TERM
    set +e
    if [ "$result" -ne 0 ]; then
        printf 'ERROR [%s]: check failed (exit %s)\n' "$STAGE" "$result" >&2
        compose_for "$PROJECT" logs --no-color --tail 50 >&2
        compose_for "$RESTORE_PROJECT" logs --no-color --tail 50 >&2
    fi
    docker rm -f "$HELPER" >/dev/null 2>&1
    if ! compose_for "$PROJECT" down -v --rmi local --remove-orphans; then
        printf 'ERROR [cleanup]: could not clean %s\n' "$PROJECT" >&2
        result=1
    fi
    if ! compose_for "$RESTORE_PROJECT" down -v --rmi local --remove-orphans; then
        printf 'ERROR [cleanup]: could not clean %s\n' "$RESTORE_PROJECT" >&2
        result=1
    fi
    rm -rf -- "$WORK"
    if [ "$result" -eq 0 ]; then
        printf 'SUCCESS: recovery verified; test resources removed\n'
    fi
    exit "$result"
}
trap cleanup 0
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

stage() {
    STAGE=$1
    printf '\nSTAGE: %s\n' "$STAGE"
}

set_url() {
    mapping=$(dc port app 8000)
    BASE_URL="http://127.0.0.1:${mapping##*:}"
    printf 'URL: %s\n' "$BASE_URL"
}

expect_http() {
    method=$1
    endpoint=$2
    expected_status=$3
    actual_status=$(curl --connect-timeout 2 --max-time 5 -sS \
        -X "$method" -o "$WORK/response.json" -w '%{http_code}' \
        "$BASE_URL$endpoint")
    if [ "$actual_status" != "$expected_status" ]; then
        printf 'ERROR [%s]: %s %s expected HTTP %s, got %s\n' \
            "$STAGE" "$method" "$endpoint" "$expected_status" "$actual_status" >&2
        cat "$WORK/response.json" >&2
        return 1
    fi
    printf '%s %s -> HTTP %s\n' "$method" "$endpoint" "$actual_status"
}

expect_count() {
    dc exec -T app python -c '
import json, sys
data = json.load(sys.stdin)
expected = int(sys.argv[1])
assert data["count"] == expected, data
assert data["storage"] == "redis", data
assert data["greeting"] == "Recovery check", data
print("count =", data["count"])
' "$1" < "$WORK/response.json"
}

wait_ready() {
    attempt=0
    while [ "$attempt" -lt 30 ]; do
        if curl --connect-timeout 1 --max-time 2 -fsS \
            "$BASE_URL/readyz" > "$WORK/ready.json" 2>/dev/null; then
            printf 'Application ready\n'
            return 0
        fi
        attempt=$((attempt + 1))
        sleep 1
    done
    printf 'ERROR [%s]: readiness timeout\n' "$STAGE" >&2
    return 1
}

stage 'fresh project'
printf 'PROJECT: %s\nRESTORE_PROJECT: %s\n' "$PROJECT" "$RESTORE_PROJECT"
dc up -d --build --wait --wait-timeout 90
set_url

stage 'process restrictions'
app_id=$(dc ps -q app)
docker inspect "$app_id" > "$WORK/inspect.json"
dc exec -T app python -c '
import json, os, sys
assert os.getuid() != 0, "app runs as root"
config = json.load(sys.stdin)[0]["HostConfig"]
assert config["ReadonlyRootfs"], "writable root filesystem"
assert 0 < config["Memory"] <= 256 * 1024 * 1024, config["Memory"]
assert 0 < config["NanoCpus"] <= 1000000000, config["NanoCpus"]
print("UID =", os.getuid(), "; readonly =", config["ReadonlyRootfs"],
      "; memory =", config["Memory"], "; NanoCpus =", config["NanoCpus"])
' < "$WORK/inspect.json"

stage 'initial count and increments'
expect_http GET / 200
expect_count 0
N=3
i=1
while [ "$i" -le "$N" ]; do
    expect_http POST /increment 200
    expect_count "$i"
    i=$((i + 1))
done

stage 'recreate app only'
redis_id=$(dc ps -q redis)
dc up -d --no-deps --force-recreate --wait --wait-timeout 90 app
test "$(dc ps -q app)" != "$app_id"
test "$(dc ps -q redis)" = "$redis_id"
set_url
expect_http GET / 200
expect_count "$N"

stage 'compose down and up without deleting data'
dc down
dc up -d --wait --wait-timeout 90
set_url
expect_http GET / 200
expect_count "$N"

stage 'Redis outage'
app_id=$(dc ps -q app)
docker inspect --format '{{.State.StartedAt}} {{.RestartCount}}' "$app_id" > "$WORK/process-before"
dc stop redis
expect_http GET /healthz 200
expect_http GET /readyz 503
expect_http POST /increment 503

stage 'Redis recovery without app restart'
dc start --wait --wait-timeout 90 redis
wait_ready
expect_http GET / 200
expect_count "$N"
expect_http POST /increment 200
N=$((N + 1))
expect_count "$N"
test "$(dc ps -q app)" = "$app_id"
docker inspect --format '{{.State.StartedAt}} {{.RestartCount}}' "$app_id" > "$WORK/process-after"
test "$(cat "$WORK/process-before")" = "$(cat "$WORK/process-after")"
printf 'App ID, StartedAt and RestartCount unchanged\n'

stage 'consistent external backup'
dc stop app redis
redis_id=$(dc ps -a -q redis)
mkdir -p "$ROOT/backups"
ARCHIVE="$ROOT/backups/${PROJECT}.tar"
docker run --rm --name "$HELPER" --volumes-from "$redis_id:ro" \
    redis:7.4-alpine tar -C /data -cpf - . > "${ARCHIVE}.tmp"
test -s "${ARCHIVE}.tmp"
mv "${ARCHIVE}.tmp" "$ARCHIVE"
printf 'BACKUP: %s\n' "$ARCHIVE"

stage 'delete original project including volumes'
dc down -v --rmi local
test -z "$(docker ps -aq --filter "label=com.docker.compose.project=$PROJECT")"
test -z "$(docker volume ls -q --filter "label=com.docker.compose.project=$PROJECT")"
printf 'Original containers and volumes removed\n'

stage 'restore backup into another empty project'
ACTIVE_PROJECT=$RESTORE_PROJECT
dc create redis
redis_id=$(dc ps -a -q redis)
docker run --rm -i --name "$HELPER" --volumes-from "$redis_id" \
    redis:7.4-alpine tar -C /data -xpf - < "$ARCHIVE"
dc up -d --build --wait --wait-timeout 90
set_url
expect_http GET / 200
expect_count "$N"
expect_http POST /increment 200
expect_count "$((N + 1))"
printf 'Backup restored: count %s, next increment %s\n' "$N" "$((N + 1))"

stage 'cleanup'
