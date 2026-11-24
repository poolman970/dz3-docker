#!/usr/bin/env bash
set -euo pipefail

P="hw_test_$(date +%s)"
PORT=18080
N=3
BACKUP="$(pwd)/backup_$P"

trap 'docker compose -p "$P" down -v --remove-orphans >/dev/null 2>&1 || true; [ -d "$BACKUP" ] && rm -rf "$BACKUP"' EXIT

log() { echo "[$1] $2"; }
fail() { log "ERROR" "$1"; exit 1; }
get() { curl -fsS --max-time 5 "$1" | sed -n 's/.*"count": *\([0-9]*\).*/\1/p' || fail "GET $1 failed"; }
post() { curl -fsS -X POST --max-time 5 "$1" | sed -n 's/.*"count": *\([0-9]*\).*/\1/p' || fail "POST $1 failed"; }
status() { curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$@" || echo "000"; }

log "1" "Start project"
export APP_PORT=$PORT GREETING="Test"
docker compose -p "$P" up -d --wait >/dev/null 2>&1 || fail "Compose up failed"

log "2" "Check initial count"
[ "$(get "http://localhost:$PORT/")" -eq 0 ] || fail "Initial count not 0"

log "3" "Increment x$N"
for i in $(seq 1 $N); do post "http://localhost:$PORT/increment" > /dev/null; done
[ "$(get "http://localhost:$PORT/")" -eq "$N" ] || fail "Count not $N"

log "4" "Recreate app"
docker compose -p "$P" up -d --force-recreate app >/dev/null 2>&1 || fail "Recreate failed"
sleep 3
[ "$(get "http://localhost:$PORT/")" -eq "$N" ] || fail "Count lost after recreate"

log "5" "Stop redis"
docker compose -p "$P" stop redis >/dev/null 2>&1
[ "$(status "http://localhost:$PORT/healthz")" -eq 200 ] || fail "healthz not 200"
[ "$(status "http://localhost:$PORT/readyz")" -eq 503 ] || fail "readyz not 503"
[ "$(status -X POST "http://localhost:$PORT/increment")" -eq 503 ] || fail "POST not 503"

log "6" "Start redis"
docker compose -p "$P" start redis >/dev/null 2>&1
for i in {1..30}; do docker compose -p "$P" exec -T redis redis-cli ping 2>/dev/null | grep -q PONG && break; sleep 1; done
[ "$(get "http://localhost:$PORT/")" -eq "$N" ] || fail "Count lost after restart"
[ "$(post "http://localhost:$PORT/increment")" -eq $((N+1)) ] || fail "Increment failed"

log "7" "Backup"
mkdir -p "$BACKUP"
docker compose -p "$P" stop >/dev/null 2>&1
docker run --rm -v "${P}_redis_data:/data" -v "$BACKUP:/backup" alpine tar czf /backup/redis.tar.gz -C /data . || fail "Backup failed"
[ -f "$BACKUP/redis.tar.gz" ] || fail "Backup missing"

log "DONE" "All tests passed!"
