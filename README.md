# Using IaaS Cloud

Third graded assignment for the Provisioning and Operations course. The group is the same as in Activity 2, and the applications are the same ones developed for that assignment. The main difference is the environment: instead of a local virtual machine running in VirtualBox, deployment is now performed on a virtual machine in the **LSD IaaS Cloud**, under the **Provisioning** project, using OpenStack.

This README documents the group's execution plan and decisions. It is updated throughout the assignment: values marked as *to be filled in* must only be replaced with actual results, never estimates.

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

Planned commands (to be adjusted according to the cloud's responses):

```bash
openstack flavor list
openstack server list
openstack image list
openstack snapshot list

openstack keypair create <key-name> > <key-name>.pem
chmod 600 <key-name>.pem

openstack server create \
  --flavor general.small \
  --image ubuntu-24.04 \
  --key-name <key-name> \
  <vm-name>

openstack security group rule create ...
```

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

## Repository Structure

| Path | Contents |
| --- | --- |
| [`RELATORIO.md`](RELATORIO.md) | Group report describing the steps, screenshots, experiments, and analysis |
| [`apps/`](apps/) | The three applications from Activity 2, now deployed in the cloud |
| [`evidencias/`](evidencias/) | Transcripts of each command (`.txt`), corresponding screenshots (`.png`), and the `manifest.csv` index |
| [`docs/execucao/`](docs/execucao/) | One execution record per task, documenting objectives, commands, decisions, and issues |
| [`docs/graficos/`](docs/graficos/) | Latency, throughput, and resource utilization charts |
| [`results/`](results/) | Raw experiment data and the consolidated summary |
| [`automation/`](automation/) | Automated phases executed on the VDI |
| [`scripts/`](scripts/) | Load generator, VM monitor, consolidation, chart and manifest generation scripts |

## Execution Record

Updated as the steps are completed.

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
| Volume | 1 GB — `vol-daniel-ranya-logs`, `/dev/vdb`, `/mnt/atividade3-logs` |
| Deployed applications and ports | CPU `8000`, memory `8001`, I/O `8002` (external ports `8100-8102`) |
| Snapshot name | `snap-vm-daniel-ranya` (`6034d4a8-45bb-40ea-abe2-867e659e8f53`, 3.43 GiB) |
| Volume snapshot | `snap-vol-daniel-ranya-logs` (`df5d86d9-f4d9-43d1-a805-7edf619355d0`, 1 GB) |

## Deliverables

- [x] SSH key pair created and used with the VM.
- [x] `general.small` VM created with `ubuntu-24.04` (one per group).
- [x] Security group configured.
- [x] `poi-atividades` load balancer configured for SSH and application traffic.
- [x] Applications running on the VM.
- [x] 1 GB volume created, attached, and mounted; applications writing to it.
- [x] Snapshot of the configured VM created.
- [x] Group report completed with screenshots and explanations of each step.
- [ ] Assignment submission form completed.

## Notes and Pending Items

- The three applications from Activity 2 did not write logs to files: the HTTP server's `log_message` method is deliberately silenced so that thousands of load-test requests do not add I/O overhead to the measurements. For this assignment, the applications were configured to write a startup message, and `systemd` redirects this output (`StandardOutput=append:`) to the mounted volume, with log rotation configured through `logrotate`.
- The required `general.small` flavor exists under that exact name in the project (`7441c7d9-2648-4a33-907e-4d28c2270da3`), contrary to what the instructor's materials suggested.
- The I/O-bound application writes its scratch file to the mounted volume during the experiments (`A3_WORK_DIR`), so the I/O measured is the I/O of the provisioned storage, not of the root disk.
- To show demand against provisioning, the same VM was resized to `general.medium` (2 vCPUs) for a short second matrix and then resized back. The VM is delivered on `general.small`, as the assignment requires, and the final flavor is recorded in the execution record.
- No credentials, private keys, or passwords are stored in this repository.
- The list of load balancers was checked before creating any resources. The `poi-atividades` load balancer already existed in the project and is shared by the class; therefore, the external ports are `2222` and `8100-8102`, which differ from the internal ports.

## Course Materials

- Cloud and OpenStack materials: [`Cloud Computing - OpenStack CLI.pptx`](Cloud%20Computing%20-%20OpenStack%20CLI.pptx).
- Provisioning VDI available at `/local/uasc/provisionamento`.
- Deployment guide for the `poi-atividades` load balancer — [Octavia: Basic Cookbook](https://docs.openstack.org/octavia/latest/user/guides/basic-cookbook.html).
- Assignment submission form.