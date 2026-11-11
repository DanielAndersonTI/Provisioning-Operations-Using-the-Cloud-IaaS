# poi-cpu — CPU-bound backend

Container image for the CPU-bound application developed in Activity 2 of the
Provisioning and Operations course (UFCG) and containerized in Activity 4. It
runs on Python 3.12 with the standard library only and serves a small HTTP API
used in the load experiments.

Each request hashes a fixed 1 MiB block a number of times, so the work stays on
the processor and touches neither disk nor a meaningful amount of memory.

## Endpoints

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/health` | Liveness probe. Returns `{"status": "ok", "profile": "cpu"}` |
| `GET` | `/work?size=N` | `N` hashes of a 1 MiB block. Default `10`, maximum `300` |

## Run

```bash
docker run --rm -p 8000:8000 danielandersonss/poi-cpu:1.0.0
curl http://localhost:8000/health
curl "http://localhost:8000/work?size=10"
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
- Built from `apps/Dockerfile` with `--build-arg PROFILE=cpu`
