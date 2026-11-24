# HW 3: Docker

## Как запустить

Создать `.env` из примера:
```bash
cp .env.example .env
```

Поднять приложение с Redis (уровни 8-10):
```bash
docker compose up -d
```

Приложение будет доступно на `http://127.0.0.1:8080/` (порт и приветствие меняются в `.env`).
Остановить: `docker compose down`.

Для 6-го уровня (SQLite) используется `compose.sqlite.yaml`:
```bash
docker compose -f compose.sqlite.yaml up -d
```

## Про compose и безопасность (уровни 6-10)

* В `compose.sqlite.yaml` данные хранятся в volume `counter_data`.
* В `compose.yaml` поднимается два сервиса: `app` и `redis`. У приложения переменные `STORAGE=redis` и `REDIS_URL=redis://redis:6379/0`. У Redis включен `appendonly yes` и volume `redis_data`. Порт наружу отдается только у `app`.
* Для обоих сервисов в `compose.yaml` прописаны healthcheck'и.
* В 10-м уровне для `app` сделано: `user: "1000:1000"`, `read_only: true`, `tmpfs: /tmp`, лимиты 256m и 1 CPU.

## Отчет по проверкам

### Уровень 4. Один контейнер
```bash
docker build -t counter-app .
docker run -d --name counter -p 8080:8000 -e GREETING="Привет!" counter-app
```

Логи (docker logs counter):
```text
2026-11-24 20:24:29,973 listening port=8000 storage=sqlite
2026-11-24 20:25:04,912 http 172.17.0.1 "GET / HTTP/1.1" 200 -
```

### Уровень 6. SQLite и volume
Запуск и проверка:
```bash
docker compose -f compose.sqlite.yaml up -d
curl http://127.0.0.1:8080/
```
Вывод:
```json
{"greeting": "Hello, Docker!", "count": 2, "hostname": "ca14da53baa9", "storage": "sqlite"}
```

Удаляем и поднимаем заново (данные сохранились):
```bash
docker compose -f compose.sqlite.yaml down
docker compose -f compose.sqlite.yaml up -d
curl http://127.0.0.1:8080/
```
Вывод:
```json
{"greeting": "Hello, Docker!", "count": 2, "hostname": "664ecd17b9cf", "storage": "sqlite"}
```

### Уровень 8. Redis и отказоустойчивость
Проверка сохранения после down/up:
```bash
docker compose up -d
curl -X POST http://127.0.0.1:8080/increment
docker compose down
docker compose up -d
curl http://127.0.0.1:8080/
```
Вывод:
```json
{"greeting": "Hello, Docker!", "count": 1, "hostname": "cfeb529c02fa", "storage": "redis"}
```

Имитация падения Redis:
```bash
docker compose stop redis
curl -i http://127.0.0.1:8080/healthz
curl -i http://127.0.0.1:8080/readyz
curl -i -X POST http://127.0.0.1:8080/increment
```
Вывод (200, 503, 503):
```text
HTTP/1.0 200 OK
{"status": "alive"}

HTTP/1.0 503 Service Unavailable
{"error": "storage_unavailable"}

HTTP/1.0 503 Service Unavailable
{"error": "storage_unavailable"}
```

Запускаем Redis обратно, приложение само восстанавливается:
```bash
docker compose start redis
curl http://127.0.0.1:8080/
curl -X POST http://127.0.0.1:8080/increment
```
Вывод:
```json
{"greeting": "Hello, Docker!", "count": 1, "hostname": "86e50d3a795a", "storage": "redis"}
{"greeting": "Hello, Docker!", "count": 2, "hostname": "86e50d3a795a", "storage": "redis"}
```

### Уровень 10. Автотесты
Скрипт `scripts/check.sh` запускался два раза подряд.

Первый запуск:
```text
[1] Start project
[2] Check initial count
[3] Increment x3
[4] Recreate app
[5] Stop redis
[6] Start redis
[7] Backup
Status: Downloaded newer image for alpine:latest
[DONE] All tests passed!
```

Второй запуск:
```text
[1] Start project
[2] Check initial count
[3] Increment x3
[4] Recreate app
[5] Stop redis
[6] Start redis
[7] Backup
[DONE] All tests passed!
```
