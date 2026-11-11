# poi-memory — Memory-bound backend

Container image for the memory-bound application developed in Activity 2 of the
Provisioning and Operations course (UFCG) and containerized in Activity 4. It
runs on Python 3.12 with the standard library only and serves a small HTTP API
used in the load experiments.

Every request allocates a buffer and touches one byte per 4 KiB page, so the
cost is dominated by allocating and faulting in memory rather than by the
processor or by disk.

## Endpoints

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/health` | Liveness probe. Returns `{"status": "ok", "profile": "memory"}` |
| `GET` | `/work?size=N` | Allocates and touches `N` MiB. Default `32`, maximum `256` |

The per-request ceiling is 256 MiB and the default admission limit is 4
concurrent work units, so the profile cannot allocate more than about 1 GiB in
total.

## Run

```bash
docker run --rm -p 8000:8000 danielandersonss/poi-memory:1.0.0
curl http://localhost:8000/health
curl "http://localhost:8000/work?size=32"
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
- Built from `apps/Dockerfile` with `--build-arg PROFILE=memory`
