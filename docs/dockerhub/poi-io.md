# poi-io — I/O-bound backend

Container image for the I/O-bound application developed in Activity 2 of the
Provisioning and Operations course (UFCG) and containerized in Activity 4. It
runs on Python 3.12 with the standard library only and serves a small HTTP API
used in the load experiments.

Every request writes a temporary file, flushes it to the storage device with
`fsync`, then reads it back, so the cost is dominated by disk latency rather
than by the processor or by memory.

## Endpoints

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/health` | Liveness probe. Returns `{"status": "ok", "profile": "io"}` |
| `GET` | `/work?size=N` | Writes, syncs and reads back `N` KiB. Default `1024`, maximum `32768` |

The environment variable `A3_WORK_DIR` chooses the directory where the scratch
file is created, so the workload can be pointed at an attached volume instead of
the container writable layer.

## Run

```bash
docker run --rm -p 8000:8000 danielandersonss/poi-io:1.0.0
curl http://localhost:8000/health
curl "http://localhost:8000/work?size=1024"
```

The container listens on port `8000`, runs as the unprivileged user `appsvc`
(UID/GID `10001`) and declares a `HEALTHCHECK` against `/health`.

## Docker Compose

The three profiles ship from a single definition parameterized by build
argument (`PROFILE=cpu|memory|io`). The deployment file, report and automation
live in the repository:

<https://github.com/DanielAndersonTI/Provisioning-Operations-Using-the-Cloud-IaaS>

```bash
docker compose pull
docker compose up -d --no-build
```

## Image

- Tags: `1.0.0`, `latest`
- Base: `python:3.12-slim`
- Port: `8000`
- Built from `apps/Dockerfile` with `--build-arg PROFILE=io`
