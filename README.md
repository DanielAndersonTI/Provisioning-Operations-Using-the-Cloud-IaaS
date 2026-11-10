# Provisioning and Operations Using the Cloud IaaS

This repository contains the two graded assignments of the Provisioning and Operations course that share the same three applications:

| Activity | Subject | Status | Detailed record |
| --- | --- | --- | --- |
| **3** | Deployment of the applications on the **LSD IaaS Cloud** (OpenStack) | Complete | [`RELATORIO.md`](RELATORIO.md) |
| **4** | **Containerization** of the applications with Docker and Docker Compose | Executed on branch `atividade4-docker`; PR pending | [`RELATORIO-ATIVIDADE4.md`](RELATORIO-ATIVIDADE4.md) |

The group is the same in both assignments, and so are the applications. Activity 3 built the cloud infrastructure and deployed the applications directly on the VM; Activity 4 keeps the same repository and the same VM, but changes the execution model to Docker containers.

This README documents what the group executed and the decisions behind it. Every value was recorded during the assignment, and each step links back to a command transcript in [`evidencias/`](evidencias/) and a record in [`docs/execucao/`](docs/execucao/) (Activity 3) or [`docs/execucao-atividade4/`](docs/execucao-atividade4/) (Activity 4). The full narrative, with the analysis of the load experiments, is in [`RELATORIO.md`](RELATORIO.md).

## Repository Structure

| Path | Contents |
| --- | --- |
| [`RELATORIO.md`](RELATORIO.md) | Activity 3 report: steps, screenshots, experiments, and analysis |
| [`RELATORIO-ATIVIDADE4.md`](RELATORIO-ATIVIDADE4.md) | Activity 4 report: containerization steps, evidence, and form data (filled in during execution) |
| [`apps/`](apps/) | The three applications from Activity 2, deployed in the cloud in Activity 3 and containerized in Activity 4 |
| [`apps/Dockerfile`](apps/Dockerfile) | Shared image definition, parameterized by build argument (Activity 4) |
| [`docker-compose.yml`](docker-compose.yml) | Compose definition of the three services (Activity 4) |
| `docker.env.example` | Template for the Docker Hub user, token, and image tag; the filled `docker.env` is never committed |
| [`evidencias/`](evidencias/) | Transcripts of each command (`.txt`), corresponding screenshots (`.png`), and the `manifest.csv` index |
| [`docs/execucao/`](docs/execucao/) | One Activity 3 execution record per task, documenting objectives, commands, decisions, and issues |
| [`docs/execucao-atividade4/`](docs/execucao-atividade4/) | One Activity 4 execution record per task, with the same structure as Activity 3 |
| [`docs/graficos/`](docs/graficos/) | Latency, throughput, and resource utilization charts |
| [`results/`](results/) | Raw experiment data and the consolidated summary |
| [`automation/`](automation/) | Automated phases executed on the VDI |
| [`scripts/`](scripts/) | Load generator, VM monitor, consolidation, chart and manifest generation scripts |

---

# Activity 3 — Deployment on the LSD IaaS Cloud

Activity 3 (third graded assignment) deploys the applications on a virtual machine in the **LSD IaaS Cloud**, under the **Provisioning** project, using OpenStack. The group is the same as in Activity 2, and the applications are the same ones developed for that assignment. The main difference is the environment: instead of a local virtual machine running in VirtualBox, deployment is performed on a cloud VM accessed through the `poi-atividades` load balancer.

## Objectives

- Operate the LSD Cloud through the **OpenStack CLI**, using the provisioning VDI available at `/local/uasc/provisionamento`.
- Create the infrastructure required for the assignment: a key pair, a VM, a security group, and a storage volume.
- Deploy the applications from Activity 2 on the VM and expose them through the `poi-atividades` load balancer.
- Persist application-generated data (e.g., logs) on a cloud volume mounted in the VM's operating system.
- Produce a document describing each step and providing evidence (screenshots) of the entire process.

## Cloud Access

| Item | Value |
| --- | --- |
| Dashboard and API | `cloud.lsd.ufcg.edu.br` |
| Project | `provisionamento` |
| Credentials | LDAP for existing users; for new accounts, the username listed in the spreadsheet, with the student ID as the password |
| Client | `python3-openstackclient` (or `python-openstackclient` in a virtual environment) |
| Initialization | **OpenStack RC file (Identity API v3)**, downloaded from *Project → API Access* |

```bash
. provisionamento-openrc.sh
openstack flavor list
```

The access VDI is `ubuntu_serve_2204_poi_openstack.vdi`, provided by the instructor. In the LCC labs, the equivalent environment is available at `/local/uasc/provisionamento`. This is the machine from which the CLI is executed; it is not the VM created for the assignment.

The OpenStack services used are Nova (instances), Glance (images and snapshots), Neutron (networking and security groups), Cinder (volumes), Octavia (load balancing), and Keystone (identity).

## Applications

The three backend applications from Activity 2 are located in [`apps/`](apps/): CPU-bound, memory-bound, and I/O-bound workloads. All are implemented in Python 3 using only the standard library and follow the same HTTP interface.

| Profile | File | Workload |
| --- | --- | --- |
| CPU-bound | [`apps/cpu/server.py`](apps/cpu/server.py) | Repeated SHA-256 hashing of a 1 MiB block |
| Memory-bound | [`apps/memory/server.py`](apps/memory/server.py) | Allocation of `size` MiB, writing to every 4 KiB page |
| I/O-bound | [`apps/io/server.py`](apps/io/server.py) | Writing `size` KiB, calling `fsync`, and reading the data back |

Endpoints: `GET /health` identifies the workload profile, `GET /work?size=N` executes the workload, and `GET /metrics` returns the counters kept inside the process (requests, rejections, queue wait and work time). The counters are what the client-side generator cannot see. Each application runs as an independent process:

```bash
python apps/cpu/server.py    --port 8000
python apps/memory/server.py --port 8000
python apps/io/server.py     --port 8000
```

Requirement: Python 3.10 or later.

## Assignment Steps

### Part One — Infrastructure

1. Access the LSD Cloud through the OpenStack CLI using the provisioning VDI at `/local/uasc/provisionamento`.
2. List the available resources: flavors, instances, images, and snapshots.
3. Create the key pair that will be used to access the VMs via SSH.
4. Create **a single VM per group**, using the `general.small` flavor and the `ubuntu-24.04` image, and specify the newly created key pair.
5. Create a security group allowing the ports required to access the VM.
6. Configure the `poi-atividades` load balancer to provide SSH access to the VM.

The commands below are the ones actually executed, in this order. The public key was generated on the VDI and registered in the project; the private half never left the VDI.

```bash
openstack flavor list
openstack server list
openstack image list
openstack snapshot list

openstack keypair create --public-key ~/.ssh/atividade3-daniel-ranya.pub \
  atividade3-daniel-ranya

openstack security group create sg-daniel-ranya \
  --description 'Acesso do balanceador a VM - Atividade 3 POI'
openstack security group rule create --protocol tcp --dst-port 22:22 \
  --remote-ip 10.5.8.0/22 sg-daniel-ranya
openstack security group rule create --protocol tcp --dst-port 8000:8002 \
  --remote-ip 10.5.8.0/22 sg-daniel-ranya
openstack security group rule create --protocol icmp \
  --remote-ip 10.5.8.0/22 sg-daniel-ranya

openstack server create \
  --flavor general.small \
  --image ubuntu-24.04 \
  --key-name atividade3-daniel-ranya \
  --network provider \
  --security-group sg-daniel-ranya \
  vm-daniel-ranya --wait
```

The VM is created on the project's `provider` network and receives a private address only. External access is through the shared `poi-atividades` load balancer, never through a floating IP on the VM itself.

### Part Two — Deployment and Storage

1. Access the group's VM via SSH.
2. Deploy the applications on the VM.
3. Create a **1 GB** volume, attach it to the VM, and mount it in the operating system.
4. Configure the applications to use the mounted volume (e.g., for log files).
5. Configure the `poi-atividades` load balancer to route traffic to the applications running on the VM.
6. Create a snapshot of the configured VM.
7. Produce the group's report describing each step and including screenshots.
8. Complete the assignment submission form.

> **Important:** Only the answers submitted through the form will be considered for grading.

## Execution Record — Activity 3

| Item | Value |
| --- | --- |
| Group | Daniel Anderson de Souza Silva · Ranya Duran Greco |
| OpenStack project | `Provisionamento` |
| VM flavor | `general.small` |
| VM image | `ubuntu-24.04` |
| VM name | `vm-daniel-ranya` (`bdc0447e-fb71-48c8-9ce2-04a8c5e20ee0`) |
| SSH key name | `atividade3-daniel-ranya` |
| SSH access address (load balancer) | `150.165.85.77:2222` → `10.5.9.15:22` |
| Security group rules | `tcp/22`, `tcp/8000-8002`, `icmp` — source: `10.5.8.0/22` |
| Volume | 1 GB — `vol-daniel-ranya-logs` (`2271182d-ac0c-4dd9-bcf7-cc535379f532`), `/dev/vdb`, `/mnt/atividade3-logs` |
| Deployed applications and ports | CPU `8000`, memory `8001`, I/O `8002` (external ports `8100-8102`) |
| Application URLs | CPU `http://150.165.85.77:8100`, memory `http://150.165.85.77:8101`, I/O `http://150.165.85.77:8102` |
| Snapshot name | `snap-vm-daniel-ranya` (`6034d4a8-45bb-40ea-abe2-867e659e8f53`, 3.43 GiB) |
| Volume snapshot | `snap-vol-daniel-ranya-logs` (`df5d86d9-f4d9-43d1-a805-7edf619355d0`, 1 GB) |

## Deliverables — Activity 3

- [x] SSH key pair created and used with the VM.
- [x] `general.small` VM created with `ubuntu-24.04` (one per group).
- [x] Security group configured.
- [x] `poi-atividades` load balancer configured for SSH and application traffic.
- [x] Applications running on the VM.
- [x] 1 GB volume created, attached, and mounted; applications writing to it.
- [x] Snapshot of the configured VM created.
- [x] Group report completed with screenshots and explanations of each step.
- [ ] Assignment submission form completed.

## Notes — Activity 3

- The three applications from Activity 2 did not write logs to files: the HTTP server's `log_message` method is deliberately silenced so that thousands of load-test requests do not add I/O overhead to the measurements. For this assignment, the applications were configured to write a startup message, and `systemd` redirects this output (`StandardOutput=append:`) to the mounted volume, with log rotation configured through `logrotate`.
- The required `general.small` flavor exists under that exact name in the project (`7441c7d9-2648-4a33-907e-4d28c2270da3`), contrary to what the instructor's materials suggested.
- The I/O-bound application writes its scratch file to the mounted volume during the experiments (`A3_WORK_DIR`), so the I/O measured is the I/O of the provisioned storage, not of the root disk.
- To show demand against provisioning, the same VM was resized to `general.medium` (2 vCPUs) for a short second matrix and then resized back. The VM is delivered on `general.small`, as the assignment requires, and the final flavor is recorded in the execution record.
- The number of work slots is a parameter, not a constant: `--max-concurrency` was varied (1, 4, 32 for CPU; 4, 8, 16 for I/O) against a copy of the application listening outside the load balancer, with the load generator running inside the VM. The result is in `results/summary-vagas.csv`.
- Request sizes are not always uniform: one phase draws a size per request from a list whose mean equals the profile's standard size, so the effect of a mixed workload is measured instead of assumed (`results/summary-misto.csv`).
- Some size cells were measured twice. The first pass left cells whose p95 was inconsistent with the same work measured in the baseline scenarios; those blocks were re-measured, and a cell is only accepted if its p95 stays below a plausibility ceiling computed from the baseline (`docs/execucao/T17.md`, `docs/execucao/T19.md`).
- No credentials, private keys, or passwords are stored in this repository.
- The listeners of the `poi-atividades` load balancer were listed before creating any resources. It already existed in the project and is shared by the class, and several of its ports already belong to other groups (`8001`, `22`, `2201`, `22022`, `14001-14003`). The external ports for this group are therefore `2222` and `8100-8102`, which differ from the internal ports.

## Course Materials — Activity 3

- Cloud and OpenStack materials: [`Cloud Computing - OpenStack CLI.pptx`](Cloud%20Computing%20-%20OpenStack%20CLI.pptx).
- Provisioning VDI available at `/local/uasc/provisionamento`.
- Deployment guide for the `poi-atividades` load balancer — [Octavia: Basic Cookbook](https://docs.openstack.org/octavia/latest/user/guides/basic-cookbook.html).
- Assignment submission form.

---

# Activity 4 — Containerization of the Applications

> **Status:** execution complete on branch `atividade4-docker`; pending commit, pull request, and form. The container files, the automation phases, and [`RELATORIO-ATIVIDADE4.md`](RELATORIO-ATIVIDADE4.md) live on that branch; `main` keeps the Activity 3 deployment until the pull request is merged.

## Objective

Evolve the three applications developed in Activity 2 — already deployed on the cloud VM in Activity 3 — so that each one runs in a **Docker container**. The code stays in the **same repository**, versioned in a **new branch**, with a **pull request to the main branch**. One Docker image is built per application and published on **Docker Hub**; the three containers are deployed together with **Docker Compose** on the **same VM created in Activity 3**, behind the existing `poi-atividades` load balancer. The three applications are then accessed remotely to verify they work, and the submission form is answered.

## What the Assignment Requires

| # | Requirement | How it is addressed |
| --- | --- | --- |
| 1 | Containerize the three applications from the previous activity | One Dockerfile per image (shared definition parameterized by profile), one container per application |
| 2 | Keep each application's code in a new branch of the same repository and open a pull request to the main branch | Branch `atividade4-docker` in this repository; pull request to `main` |
| 3 | Create a Docker image for each application | `poi-cpu`, `poi-memory`, `poi-io` images built from the same Dockerfile with different build arguments |
| 4 | Publish the images on Docker Hub | Public repositories in the group's Docker Hub account, tags `1.0.0` and `latest` |
| 5 | Write a `docker-compose.yml` that configures the three applications | [`docker-compose.yml`](docker-compose.yml) at the repository root |
| 6 | Deploy the three applications with Docker Compose on the VM from Activity 3 | `docker compose pull` followed by `docker compose up -d` on `vm-daniel-ranya` |
| 7 | Configure the `poi-atividades` load balancer to reach the containers | Same listeners `8100-8102` → host ports `8000-8002`; no new LB resources needed |
| 8 | Access the three applications remotely and verify they work | `GET /health` and `GET /work?size=N` through the VIP, plus container health and logs |
| 9 | Answer the submission form | Execution record below feeds the form |

> **Important:** Only the answers submitted through the form will be considered for grading.

## Architecture

The containerized deployment keeps the same network path built in Activity 3. The only change is what runs inside the VM: three containers managed by Docker Compose instead of three `systemd` services.

```text
                     LSD Cloud — project Provisionamento
 ┌──────────────────────────────────────────────────────────────────────┐
 │  poi-atividades (Octavia, shared by the class)                       │
 │  VIP 150.165.85.77 / 10.5.8.242                                      │
 │                                                                      │
 │    :2222 ───────────────► 10.5.9.15:22   (SSH, management)           │
 │    :8100 ───────────────► 10.5.9.15:8000 ─┐                          │
 │    :8101 ───────────────► 10.5.9.15:8001 ─┼─► Docker Compose         │
 │    :8102 ───────────────► 10.5.9.15:8002 ─┘   ├─ cpu     (container) │
 │                                                ├─ memory  (container) │
 │  VM vm-daniel-ranya                            └─ io      (container) │
 │  general.small · ubuntu-24.04                                        │
 │  /mnt/atividade3-logs (1 GB Cinder volume) mounted into the containers│
 └──────────────────────────────────────────────────────────────────────┘
          images pulled from Docker Hub at deploy time
```

Because the host ports remain `8000-8002` and the external ports remain `8100-8102`, the load balancer configuration from Activity 3 is reused unchanged. The containers are the new members behind the same listeners.

## Branch and Pull Request

| Item | Value |
| --- | --- |
| Repository | `Provisioning-Operations-Using-the-Cloud-IaaS` (same repository as Activity 3) |
| Base branch | `main` |
| Working branch | `atividade4-docker` (created locally; not pushed yet) |
| Pull request | `atividade4-docker` → `main`, describing the images and the Compose deployment (to be opened) |
| Report | [`RELATORIO-ATIVIDADE4.md`](RELATORIO-ATIVIDADE4.md) (Portuguese, on the branch) |

The repository hosts all three applications, so one branch and one pull request cover the containerization of the three. The changes are additive: the Activity 3 deployment files remain in the repository, and the container files are added alongside them.

## Container Images

| Application | Build argument | Image on Docker Hub | Container port | Host port |
| --- | --- | --- | --- | --- |
| CPU-bound | `PROFILE=cpu` | `danielandersonss/poi-cpu:1.0.0` | `8000` | `8000` |
| Memory-bound | `PROFILE=memory` | `danielandersonss/poi-memory:1.0.0` | `8000` | `8001` |
| I/O-bound | `PROFILE=io` | `danielandersonss/poi-io:1.0.0` | `8000` | `8002` |

All containers listen on port `8000` internally; only the published host port differs. This keeps the load balancer members from Activity 3 (`10.5.9.15:8000`, `:8001`, `:8002`) exactly as they were.

The images are built from a single [`apps/Dockerfile`](apps/Dockerfile), with the profile passed as a build argument. The build context is the repository root, so the image contains both the shared module (`apps/server.py`) and the selected entry point (`apps/<profile>/server.py`). The image:

- starts from `python:3.12-slim`;
- runs the application as an **unprivileged user** (no root inside the container);
- exposes only the application port;
- declares an HTTP `HEALTHCHECK` against `/health`;
- keeps Python output unbuffered so logs are not delayed.

## Docker Compose

The [`docker-compose.yml`](docker-compose.yml) file declares the three services with the published image names, the host port mapping, the mounted log volume, a restart policy, a health check, and log rotation. The service definition follows this pattern:

```yaml
services:
  cpu:
    image: ${DOCKERHUB_USER}/poi-cpu:${IMAGE_TAG:-1.0.0}
    pull_policy: always
    ports:
      - "8000:8000"
    volumes:
      - /mnt/atividade3-logs:/var/log/poi
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=2)"]
      interval: 15s
      timeout: 3s
      retries: 3
      start_period: 5s
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "5"
```

Deployment uses the published images (`docker compose pull` followed by `docker compose up -d --no-build`), so the VM never needs the source code or a build toolchain: it pulls exactly the artifacts published on Docker Hub.

## Deployment Steps

1. **Branch and files.** Create `atividade4-docker` and add the Dockerfile, `.dockerignore`, `docker-compose.yml`, documentation, and automation phases.
2. **Build on the VDI.** Build the three images with the profile build argument and record `docker images`, image sizes, and digests.
3. **Publish to Docker Hub.** Authenticate with a token from a file outside the repository, tag `1.0.0` and `latest`, push, and verify the public repositories.
4. **Prepare the VM.** Install Docker Engine and the Compose plugin, and confirm that the 1 GB volume is still attached and mounted.
5. **Cut over.** Stop and disable the three `systemd` units from Activity 3 (they hold ports `8000-8002`), then `docker compose pull` and `docker compose up -d --no-build`.
6. **Verify locally.** `docker compose ps`, container health, `GET /health` and `GET /work` on each host port, and logs written to the mounted volume.
7. **Verify remotely.** The same requests through `http://150.165.85.77:8100`, `:8101`, and `:8102`, plus a failover check: stop one container, observe the load balancer member go `ERROR` and the VIP return `503`, restart it, and confirm recovery.
8. **Snapshot.** Create a new snapshot of the VM in its containerized state (the Activity 3 snapshot remains as the previous state).
9. **Report and evidence.** Write `RELATORIO-ATIVIDADE4.md` and the per-task records under `docs/execucao-atividade4/`.
10. **Pull request and form.** Open the pull request to `main` and answer the submission form.

## Automation

Activity 4 reuses the host → VDI → cloud pipeline built in Activity 3, so the same evidence rules apply: every command is recorded as a `.txt` transcript and rendered as a `.png` screenshot, and every task gets a Markdown record.

| Phase | Script | What it does |
| --- | --- | --- |
| 24 | `automation/remote/200-docker-bootstrap.sh` | Installs Docker Engine and the Compose plugin on the VDI and the VM, records versions and daemon configuration |
| 25 | `automation/remote/210-images.sh` | Builds the three images on the VDI, tags and pushes them to Docker Hub, records image IDs, sizes, and digests |
| 26 | `automation/remote/220-compose-deploy.sh` | On the VM: stops/disables the `systemd` units, pulls the images, runs `docker compose up -d`, records `ps`, health, logs, and the volume proof |
| 27 | `automation/remote/230-lb-verify.sh` | Verifies the three applications through the VIP and performs the failover test |
| 28 | `automation/remote/240-snapshot.sh` | Creates and verifies the snapshot of the containerized VM |

The scripts are executed with `python automation/run.py remote/<phase>.sh --pull`, and the results are pulled back into `evidencias/`, `results/`, and `logs/`. `run.py` reads `docker.env` from the repository root — a gitignored file filled from `docker.env.example` — and forwards the Docker Hub user, token, and image tag to the VDI session file with mode `0600`. They are never committed and never printed in evidence: the push script receives the token through `--password-stdin`.

## Execution Record — Activity 4

| Item | Value |
| --- | --- |
| Group | Daniel Anderson de Souza Silva · Ranya Duran Greco |
| Repository | `Provisioning-Operations-Using-the-Cloud-IaaS` |
| Branch / pull request | `atividade4-docker` (created) / to be opened |
| Docker Engine / Compose versions | VDI: `24.0.5` / `v2.20.2` — VM: `29.1.3` / `2.40.3` |
| Docker Hub account | `danielandersonss` (public repositories) |
| Images | `poi-cpu`, `poi-memory`, `poi-io` — tags `1.0.0` and `latest`, 114 MB each |
| VM | `vm-daniel-ranya` (`bdc0447e-fb71-48c8-9ce2-04a8c5e20ee0`), `general.small` |
| Host ports | `8000` (CPU), `8001` (memory), `8002` (I/O) |
| External ports | `8100`, `8101`, `8102` |
| Application URLs | `http://150.165.85.77:8100`, `:8101`, `:8102` |
| Log volume | `vol-daniel-ranya-logs` (`2271182d-ac0c-4dd9-bcf7-cc535379f532`) at `/mnt/atividade3-logs` |
| Snapshot after containerization | `snap-vm-daniel-ranya-atividade4` (`aa534820-acce-4597-969d-3740d3be4221`), `active`, 7.98 GB qcow2 |
| Submission form | pending |

## Deliverables — Activity 4

- [x] Three applications containerized.
- [ ] Changes committed to the `atividade4-docker` branch.
- [ ] Pull request opened to `main`.
- [x] One Docker image built for each application.
- [x] Three images published on Docker Hub.
- [x] `docker-compose.yml` created.
- [x] Three applications deployed with Docker Compose on the Activity 3 VM.
- [x] `poi-atividades` load balancer reaching the containers.
- [x] Three applications accessed remotely and verified.
- [x] Activity 4 report completed with screenshots.
- [ ] Assignment submission form completed.

## Notes — Activity 4

- No credentials, private keys, passwords, or Docker Hub tokens are stored in this repository. They live on the operator's machine, outside version control, and are injected into the VDI session file with mode `0600`.
- The images are **public** on Docker Hub so that the instructor and the VM can pull them without credentials.
- The 1 GB Cinder volume from Activity 3 remains attached and is bind-mounted into the containers, keeping application data on cloud storage instead of the container's writable layer.
- The `systemd` units from Activity 3 are stopped and disabled, not deleted: rolling back consists of `docker compose down` followed by `systemctl enable --now app-cpu app-memory app-io`.
- The Activity 3 snapshot remains valid. A second snapshot after Activity 4 captures the containerized state and is recommended before any further experiments.
- Container logs are written to the mounted volume. Docker's `json-file` driver keeps a bounded copy for `docker logs`, with size and file-count limits so that logs do not grow without bound.

## Course Materials — Activity 4

- Containerization materials provided by the instructor.
- [Docker documentation](https://docs.docker.com/).
- [Docker Compose documentation](https://docs.docker.com/compose/).
- Assignment submission form.
