# Atividade 4 — Conteinerização das Aplicações

| Campo | Valor |
| --- | --- |
| Grupo | Daniel Anderson de Souza Silva · Ranya Duran Greco |
| Disciplina | Provisionamento e Operação de Infraestrutura |
| Entrega | 11/11/2026 |
| Repositório | `Provisioning-Operations-Using-the-Cloud-IaaS` |
| Branch | `atividade4-docker` |
| Pull request | [#1](https://github.com/DanielAndersonTI/Provisioning-Operations-Using-the-Cloud-IaaS/pull/1) para `main` |

> **Estado.** Execução concluída e verificada em 09/11/2026 e reverificada em 10/11/2026, depois do endurecimento dos containers; branch `atividade4-docker` e PR #1 abertos. Os resultados das verificações citam o ID da evidência correspondente em `evidencias/`. Falta apenas a resposta do formulário de entrega.

## 1. Objetivo

Evoluir as três aplicações da Atividade 2 — já implantadas na VM da nuvem do LSD na Atividade 3 — para execução em **containers Docker**. O código permanece no mesmo repositório, versionado em uma **nova branch**, com **pull request para a `main`**. Cada aplicação ganha uma **imagem Docker** publicada no **Docker Hub**, e as três são implantadas em conjunto com **Docker Compose** na mesma VM da Atividade 3, atrás do balanceador `poi-atividades`.

## 2. O que a atividade pede

| # | Requisito do enunciado | Como foi atendido |
| --- | --- | --- |
| 1 | Conteinerizar as três aplicações | Um container por aplicação, a partir de uma definição de imagem parametrizada por perfil |
| 2 | Nova branch no repositório da atividade anterior e pull request para a principal | Branch `atividade4-docker` neste repositório; PR para `main` |
| 3 | Criar uma imagem Docker para cada aplicação | `poi-cpu`, `poi-memory`, `poi-io` |
| 4 | Publicar as imagens no Docker Hub | Repositórios públicos, tags `1.0.0` e `latest` |
| 5 | Criar o `docker-compose.yml` | Arquivo na raiz do repositório, com os três serviços |
| 6 | Fazer o deploy com Docker Compose na VM da Atividade 3 | `docker compose pull` + `docker compose up -d --no-build` na `vm-daniel-ranya` |
| 7 | Configurar o `poi-atividades` para acessar os containers | Mesmos listeners `8100-8102` → portas do host `8000-8002` |
| 8 | Acessar remotamente e verificar o funcionamento | `/health` e `/work` pela VIP, healthchecks e failover |
| 9 | Responder o formulário | Dados consolidados no Apêndice A |

## 3. Arquitetura da solução

```text
                     LSD Cloud — projeto Provisionamento
 ┌──────────────────────────────────────────────────────────────────────┐
 │  poi-atividades (Octavia, compartilhado pela turma)                  │
 │  VIP 150.165.85.77 / 10.5.8.242                                      │
 │                                                                      │
 │    :2222 ───────────────► 10.5.9.15:22   (SSH, administração)        │
 │    :8100 ───────────────► 10.5.9.15:8000 ─┐                          │
 │    :8101 ───────────────► 10.5.9.15:8001 ─┼─► Docker Compose         │
 │    :8102 ───────────────► 10.5.9.15:8002 ─┘   ├─ cpu     (container) │
 │                                                ├─ memory  (container) │
 │  VM vm-daniel-ranya                            └─ io      (container) │
 │  general.small · ubuntu-24.04                                        │
 │  /mnt/atividade3-logs (volume Cinder de 1 GB) montado nos containers │
 └──────────────────────────────────────────────────────────────────────┘
          imagens baixadas do Docker Hub no momento do deploy
```

O caminho de rede é o mesmo da Atividade 3. O que muda é o que roda dentro da VM: três containers gerenciados pelo Docker Compose no lugar de três serviços `systemd`.

## 4. Branch e pull request

| Item | Valor |
| --- | --- |
| Repositório | `Provisioning-Operations-Using-the-Cloud-IaaS` |
| Branch base | `main` |
| Branch de trabalho | `atividade4-docker` |
| Pull request | [#1](https://github.com/DanielAndersonTI/Provisioning-Operations-Using-the-Cloud-IaaS/pull/1) para `main` |
| Commit(s) | `7d6b60f` — conteinerização; `01b1ab6` — registro do commit e do PR; o endurecimento e esta revisão seguem em um commit posterior na mesma branch |
| URL do PR | <https://github.com/DanielAndersonTI/Provisioning-Operations-Using-the-Cloud-IaaS/pull/1> |

O repositório hospeda as três aplicações, portanto uma branch e um pull request cobrem a conteinerização das três. A `main` permanece com a implantação da Atividade 3 até o merge.

## 5. Imagens Docker

| Aplicação | Build | Imagem | Porta no container | Porta no host |
| --- | --- | --- | --- | --- |
| CPU-bound | `--build-arg PROFILE=cpu` | `danielandersonss/poi-cpu:1.0.0` | `8000` | `8000` |
| Memory-bound | `--build-arg PROFILE=memory` | `danielandersonss/poi-memory:1.0.0` | `8000` | `8001` |
| I/O-bound | `--build-arg PROFILE=io` | `danielandersonss/poi-io:1.0.0` | `8000` | `8002` |

A definição é única (`apps/Dockerfile`) e recebe o perfil como argumento de build. O contexto é a raiz do repositório, o que disponibiliza `apps/server.py` e o entrypoint do perfil. A imagem roda como usuário sem privilégios, expõe apenas a porta da aplicação e declara um `HEALTHCHECK` HTTP contra `/health`.

As três imagens foram construídas sobre `python:3.12-slim` a partir do mesmo contexto; o primeiro build enviou 15,32 kB ao builder e os dois seguintes cerca de 2 kB, porque as camadas comuns vieram do cache. Todas ocupam 114 MB no disco local; no Hub cada uma ocupa ~44 MB, porque as camadas são comprimidas no push:

| Imagem | ID | Digest |
| --- | --- | --- |
| `poi-cpu:1.0.0` | `443fa9abcd54` | `sha256:7279dc1e69d44e4ae1d8a257831b2ac74b8f4f0661d1e4b142d547f0f3572097` |
| `poi-memory:1.0.0` | `f50ee3166072` | `sha256:859c282e77a398228c9f1d4e2f9a5fdb3e8656b0ba5b78891359fcf4722a427e` |
| `poi-io:1.0.0` | `f019ca3425f6` | `sha256:44324001836800a8fa7b0fb26a3cb8c73927f97584153256491d222007a199d6` |

Cada repositório tem as tags `1.0.0` e `latest`, confirmadas pela API do Docker Hub:

- <https://hub.docker.com/r/danielandersonss/poi-cpu> — 44.294.756 bytes comprimidos
- <https://hub.docker.com/r/danielandersonss/poi-memory> — 44.294.458 bytes comprimidos
- <https://hub.docker.com/r/danielandersonss/poi-io> — 44.294.427 bytes comprimidos

Evidências: `T25.2-*`, `T25.3-report` (IDs e digests) e `T25.3-hub` (tamanhos e tags no Hub).

## 6. Docker Compose

O `docker-compose.yml` declara os três serviços com a imagem publicada, o mapeamento de portas, o volume de logs, política de reinício, healthcheck, limite do log do driver e o bloco de endurecimento. Os containers escutam sempre na porta `8000` internamente; o que muda é a porta publicada no host (`8000`, `8001`, `8002`), preservando os membros já configurados no balanceador.

Decisões:

- **Imagens publicadas, não build na VM.** A VM só faz `pull`; não precisa de código-fonte nem de toolchain.
- **Volume de 1 GB montado em `/var/log/poi`.** Os logs e o arquivo de trabalho do perfil I/O ficam no armazenamento em nuvem, como na Atividade 3.
- **`systemd` desabilitado, não removido.** O rollback é `docker compose down` + `systemctl enable --now app-cpu app-memory app-io`.
- **Endurecimento igual ao da Atividade 3.** O bloco `x-hardening` aplica aos três serviços `read_only: true` (só o volume é gravável), `tmpfs: /tmp`, `no-new-privileges:true`, `cap_drop: [ALL]` e `stop_grace_period: 5s`. É o equivalente no Docker do `NoNewPrivileges`, `PrivateTmp`, `ProtectSystem` e `TimeoutStopSec=5` das units `systemd`.
- **Log no arquivo, não no `docker logs`.** O `command` do compose redireciona a saída da aplicação para `/var/log/poi/<perfil>/app.log`, no volume; por isso `docker logs` só mostra erro de shell. O arquivo continua rotacionado pelo `logrotate` da Atividade 3 (`copytruncate`, diário, 7 rotações, teto de 10 MB) e o `json-file` 10m × 5 só limita o que os containers escrevem em stdout.

## 7. Implantação na VM

| Item | Valor |
| --- | --- |
| VM | `vm-daniel-ranya` (`bdc0447e-fb71-48c8-9ce2-04a8c5e20ee0`) |
| Flavor / imagem | `general.small` / `ubuntu-24.04` |
| Acesso | `150.165.85.77:2222` → `10.5.9.15:22` |
| Docker Engine | `29.1.3` (pacote `docker.io` da distribuição, driver `overlayfs`) |
| Docker Compose | `2.40.3` (pacote `docker-compose-v2` da distribuição) |
| Diretório do compose | `/opt/atividade4/docker-compose.yml` (`0644`, sha256 `bc96cf22…c62dbfcb`) |
| Arquivo de ambiente | `/etc/poi-atividade4/docker.env` (`0600`, apenas usuário e tag) |
| Volume | `vol-daniel-ranya-logs` (`2271182d-ac0c-4dd9-bcf7-cc535379f532`) em `/mnt/atividade3-logs` |
| Snapshot pós-conteinerização | `snap-vm-daniel-ranya-atividade4` (`aa534820-acce-4597-969d-3740d3be4221`), `active`, 7,98 GB em qcow2 (criado antes do endurecimento; o estado atual dos containers está nas evidências `T26.3-*`) |

Passos executados:

1. Instalação do Docker Engine e do plugin Compose na VDI e na VM.
2. Build das três imagens na VDI e publicação no Docker Hub.
3. Na VM: `docker compose pull`, parada e desabilitação das units `systemd`, `docker compose up -d --no-build`.
4. Conferência de `docker compose ps`, healthchecks, logs e escrita no volume.
5. Snapshot da VM no estado conteinerizado.
6. Em 10/11, o compose recebeu o endurecimento e os containers foram recriados; healthchecks, VIP e failover foram reverificados (`T26.3-hardening`, `T27.3-*`, `T27.4-*`).

## 8. Balanceador `poi-atividades`

Nenhum recurso novo é criado: os listeners `8100`, `8101` e `8102` da VIP `150.165.85.77` continuam nas mesmas portas e os pools continuam apontando para `10.5.9.15:8000`, `:8001` e `:8002`, agora atendidos pelos containers. O monitor HTTP continua consultando `/health` e esperando `200`.

| Listener | Porta externa | Pool | Membro | Container |
| --- | --- | --- | --- | --- |
| `app-cpu-daniel-ranya` | `8100` | `pool-app-cpu-daniel-ranya` | `10.5.9.15:8000` | `cpu` |
| `app-memory-daniel-ranya` | `8101` | `pool-app-memory-daniel-ranya` | `10.5.9.15:8001` | `memory` |
| `app-io-daniel-ranya` | `8102` | `pool-app-io-daniel-ranya` | `10.5.9.15:8002` | `io` |

Os nomes acima correspondem aos recursos criados na Atividade 3 e confirmados na execução. Os três membros (`vm-daniel-ranya`, `10.5.9.15`, portas `8000`, `8001` e `8002`) estavam `ONLINE` no momento da verificação (evidência `T27.2-member-status`). Nenhum recurso do balanceador foi criado, alterado ou removido nesta atividade.

A configuração foi lida do próprio OpenStack, não apenas inferida do resultado: `T27.4-listeners` mostra cada listener com o seu `default_pool_id`, `T27.4-pools` mostra o pool `HTTP`/`ROUND_ROBIN` e o `healthmonitor_id`, `T27.4-healthmonitors` mostra o monitor em `/health` (`delay` 5 s, `timeout` 4 s, `max_retries` 3) e `T27.4-members` mostra o membro `10.5.9.15` nas portas `8000-8002` como `ACTIVE`/`ONLINE`.

## 9. Verificação de funcionamento

| Verificação | Resultado | Evidência |
| --- | --- | --- |
| `GET /health` em cada container | `200` com o perfil correto nas portas `8000-8002` | `T27.1-health-json` |
| `GET /work?size=N` em cada container | `200` em 0,05 s (cpu), 0,04 s (memory) e 0,22 s (io) | `T27.1-smoke-local` |
| `GET /health` pela VIP, portas `8100-8102` | `200` em ~0,05 s nos três listeners | `T27.2-health-vip` |
| `GET /work` pela VIP | `200` em 0,32 s / 0,33 s / 0,56 s | `T27.2-work-vip` |
| Containers e healthchecks | três containers `Up (healthy)`; portas por `docker-proxy` | `T26.3-ps`, `T26.3-health`, `T26.3-ports` |
| Failover: parar o container `cpu` | membro `ERROR` e VIP `503` em ~53 s; depois `ONLINE` e `200` em 0,049 s | `T27.3-stop`, `T27.3-member-degraded`, `T27.3-member-restored` |
| Logs no volume | `app.log` em `10001:10001` sob `/mnt/atividade3-logs/<perfil>/` | `T26.3-volume-logs` |
| Política de reinício e log | `unless-stopped`; log em `app.log` no volume, rotacionado pelo `logrotate` da A3; `json-file` 10m × 5 para stdout | `T26.3-restart-policy`, `T26.3-volume-logs` |
| Endurecimento dos containers | `readonly=true`, `capdrop=[ALL]`, `no-new-privileges:true`, `StopTimeout=5` nos três | `T26.3-hardening` |
| Configuração do balanceador | listener → pool → monitor `/health` → membro `10.5.9.15:8000-8002`, tudo `ONLINE` | `T27.4-listeners`, `T27.4-pools`, `T27.4-healthmonitors`, `T27.4-members` |

## 10. Evidências

O índice por tarefa está em [`docs/execucao-atividade4/INDEX.md`](docs/execucao-atividade4/INDEX.md). Cada comando é registrado como transcrição `.txt` e renderizado como `.png`; o `evidencias/manifest.csv` é regenerado ao final.

| Fase | Evidências | Status |
| --- | --- | --- |
| T24 — Docker na VDI e na VM | 7 pares (`T24.1-*`, `T24.2-*`) | concluída |
| T25 — imagens e Docker Hub | 8 pares (`T25.1-*` a `T25.3-hub`) | concluída |
| T26 — deploy com Compose | 14 pares (`T26.1-*` a `T26.3-hardening`) | concluída |
| T27 — verificação, failover e balanceador | 14 pares (`T27.1-*` a `T27.4-members`) | concluída |
| T28 — snapshot final | 8 pares (`T28.1-*`) | concluída |
| T29 — relatório e formulário | `manifest.csv` regenerado e contagem final | concluída |

Somando T24 a T28, são 51 pares de evidência (`.txt` + `.png`) só nesta atividade, além do `evidencias/manifest.csv` regenerado ao final. Os registros por tarefa estão em `docs/execucao-atividade4/`.

## 11. Dificuldades e decisões

**A VDI estava desligada.** A máquina `Atividade3-Cloud` foi iniciada em modo headless (`VBoxManage startvm --type headless`) e o encaminhamento NAT `ssh,tcp,127.0.0.1,2222,,22` foi usado para toda a automação. Nenhuma configuração da VDI mudou além da instalação do Docker.

**O grupo `docker` travava a fase.** Na primeira execução da fase 24, a VDI já tinha Docker e o instalador saía antes de incluir `osboxes` no grupo; o `sg docker` seguinte pedia senha e a automação, que não encaminha stdin, ficava parada. Correções: o caminho "já instalado" passou a aplicar o grupo, e a fase ganhou um `usermod` explícito antes de qualquer `sg`.

**O token do Docker Hub estava só com leitura.** O login passava, mas o push era recusado com `unauthorized: access token has insufficient scopes`. O token foi reemitido com **Read & Write** e a fase foi repetida. Junto veio uma correção importante: a fase terminava com exit 0 mesmo quando o push falhava; agora o push e a conferência no Hub derrubam a fase.

**A ordem do cutover foi invertida de propósito.** Na primeira versão, o `systemd` era parado antes do `pull` e os diretórios de log eram alterados antes da parada. As duas coisas podiam deixar a VM sem serviço: se o pull falhasse, nada subiria; e o `chown` para 10001 enquanto a instância antiga (outro UID) ainda escrevia poderia quebrá-la. A ordem final é **pull → stop → chown → up**, com rollback automático para o `systemd` se o `up` falhar. O rollback não foi necessário.

**O snapshot demorou mais que a janela da fase.** `openstack server image create` retorna com status `queued` e o Glance leva vários minutos para gravar o disco de 19 GB em qcow2. A fase 28 espera 4 minutos; como o status ainda era `saving`, uma fase de continuação (241) retomou a espera sem criar nada de novo.

**A VM tinha 16 GB livres** (`T24.2-vm-versions`). Foi o motivo de não construir imagens nela: o deploy só faz `pull` das três imagens de 44 MB comprimidas, e os diretórios de log continuam no volume Cinder, não no disco raiz.

## 12. Conclusão

As três aplicações da Atividade 2 passaram a rodar em containers Docker na mesma VM da Atividade 3, com uma imagem por aplicação publicada no Docker Hub e o conjunto orquestrado por Docker Compose. O balanceador `poi-atividades` não precisou de nenhuma alteração: os listeners `8100-8102` continuam entregando `/health` e `/work` com `200`, agora a partir dos containers.

A troca de modelo de execução preservou o comportamento observado na Atividade 3: os containers sobem com `unless-stopped`, respondem ao healthcheck, gravam no mesmo volume de logs e, quando um deles é parado, o membro do pool vai a `ERROR` e a VIP devolve `503`, voltando a `ONLINE` quando o container retorna. O `systemd` foi desabilitado, não removido, e o rollback é uma linha de comando.

O que ficou fora do escopo, deliberadamente: não há orquestrador (Kubernetes), não há registro privado e não há pipeline de CI. A atividade pede imagens no Docker Hub e deploy com Compose, e é isso que está implantado e verificado.

## Apêndice A — Dados para o formulário

A tabela segue a ordem exata das perguntas do formulário de entrega. O formulário não pede prints, link do relatório nem link do PR: pede identificação, VM e, para cada aplicação, repositório, URL em execução e URL da imagem; no fim, o YAML do Compose.

| # | Campo do formulário | Resposta |
| --- | --- | --- |
| 1 | E-mail | `danielanderson.silva@copin.ufcg.edu.br` |
| 2 | Nome completo | Daniel Anderson de Souza Silva |
| 3 | Matrícula | (preenchida pelo autor no formulário) |
| 4 | Grupo | daniel-ranya — Daniel Anderson de Souza Silva e Ranya Duran Greco |
| 5 | ID da VM criada | `bdc0447e-fb71-48c8-9ce2-04a8c5e20ee0` |
| 6 | IP da VM criada | `10.5.9.15` |
| 7 | Repositório da aplicação 1 conteinerizada | <https://github.com/DanielAndersonTI/Provisioning-Operations-Using-the-Cloud-IaaS/tree/atividade4-docker/apps/cpu> |
| 8 | URL da aplicação 1 em execução | <http://150.165.85.77:8100/health> |
| 9 | URL da imagem publicada da aplicação 1 | <https://hub.docker.com/r/danielandersonss/poi-cpu> |
| 10 | Repositório da aplicação 2 conteinerizada | <https://github.com/DanielAndersonTI/Provisioning-Operations-Using-the-Cloud-IaaS/tree/atividade4-docker/apps/memory> |
| 11 | URL da aplicação 2 em execução | <http://150.165.85.77:8101/health> |
| 12 | URL da imagem publicada da aplicação 2 | <https://hub.docker.com/r/danielandersonss/poi-memory> |
| 13 | Repositório da aplicação 3 conteinerizada | <https://github.com/DanielAndersonTI/Provisioning-Operations-Using-the-Cloud-IaaS/tree/atividade4-docker/apps/io> |
| 14 | URL da aplicação 3 em execução | <http://150.165.85.77:8102/health> |
| 15 | URL da imagem publicada da aplicação 3 | <https://hub.docker.com/r/danielandersonss/poi-io> |
| 16 | URL do arquivo yaml do docker compose | <https://github.com/DanielAndersonTI/Provisioning-Operations-Using-the-Cloud-IaaS/blob/atividade4-docker/docker-compose.yml> |

Cada integrante responde o formulário com a própria matrícula; os outros campos são iguais para o grupo.

As URLs das linhas 8, 11 e 14 terminam em `/health` de propósito. A raiz (`/`) das aplicações devolve `404` com a mensagem `Use /health or /work?size=N`, e quem abrir o link veria um erro; `GET /health` devolve `200` com o perfil (`cpu`, `memory` ou `io`), provando de imediato que o container certo está respondendo pelo listener. Os endpoints completos são `/health`, `/work?size=N` e `/metrics`.

O formulário pede "repositório da aplicação" no singular, três vezes. As três aplicações vivem no mesmo repositório, então cada linha aponta para a pasta da aplicação dentro da branch `atividade4-docker`; a raiz do repositório é <https://github.com/DanielAndersonTI/Provisioning-Operations-Using-the-Cloud-IaaS/tree/atividade4-docker>. O Docker Hub mostra apenas o texto do *Overview*, não arquivos do repositório: o `docker-compose.yml` está no link da linha 16.

Dados complementares, úteis se o formulário ou o professor pedirem: portas externas `8100`, `8101` e `8102` (SSH em `2222`); volume `2271182d-ac0c-4dd9-bcf7-cc535379f532` em `/mnt/atividade3-logs`; branch `atividade4-docker` com PR #1 para `main` (<https://github.com/DanielAndersonTI/Provisioning-Operations-Using-the-Cloud-IaaS/pull/1>); relatório <https://github.com/DanielAndersonTI/Provisioning-Operations-Using-the-Cloud-IaaS/blob/atividade4-docker/RELATORIO-ATIVIDADE4.md>.

## Apêndice B — Comandos principais

```bash
# build (na VDI, a partir da raiz do repositório)
docker build --build-arg PROFILE=cpu    -t "$DOCKERHUB_USER/poi-cpu:1.0.0"    .
docker build --build-arg PROFILE=memory -t "$DOCKERHUB_USER/poi-memory:1.0.0" .
docker build --build-arg PROFILE=io     -t "$DOCKERHUB_USER/poi-io:1.0.0"     .

# publicação (o token vem do docker.env e entra por --password-stdin)
printf '%s' "$DOCKERHUB_TOKEN" | docker login -u "$DOCKERHUB_USER" --password-stdin
docker push "$DOCKERHUB_USER/poi-cpu:1.0.0"
docker push "$DOCKERHUB_USER/poi-memory:1.0.0"
docker push "$DOCKERHUB_USER/poi-io:1.0.0"
docker logout

# deploy (na VM, com o arquivo de ambiente fora do repositório)
sudo docker compose --env-file /etc/poi-atividade4/docker.env pull
sudo docker compose --env-file /etc/poi-atividade4/docker.env up -d --no-build
sudo docker compose --env-file /etc/poi-atividade4/docker.env ps
```

## Referências

- DOCKER INC. **Compose file reference**. Disponível em: <https://docs.docker.com/reference/compose-file/>. Acesso em: 10 nov. 2026.
- DOCKER INC. **Docker Hub: repositórios e informações do repositório**. Disponível em: <https://docs.docker.com/docker-hub/repos/manage/information/>. Acesso em: 10 nov. 2026.
- DOCKER INC. **Docker Hub release notes**. Disponível em: <https://docs.docker.com/docker-hub/release-notes/>. Acesso em: 10 nov. 2026.
- DOCKER INC. **Dockerfile reference**. Disponível em: <https://docs.docker.com/reference/dockerfile/>. Acesso em: 10 nov. 2026.
- OPENSTACK FOUNDATION. **Octavia: Basic Cookbook**. Disponível em: <https://docs.openstack.org/octavia/latest/user/guides/basic-cookbook.html>. Acesso em: 10 nov. 2026.
- OPENSTACK FOUNDATION. **OpenStack Command-Line Interface Reference**. Disponível em: <https://docs.openstack.org/python-openstackclient/latest/>. Acesso em: 10 nov. 2026.
