# Atividade 3 — Usando Nuvem IaaS

Terceira atividade avaliativa da disciplina de Provisionamento e Operação. O
grupo é o mesmo da Atividade 2 e as aplicações são as mesmas desenvolvidas
naquela atividade; o que muda é o ambiente: em vez de uma VM local no
VirtualBox, o deploy passa a ser feito em uma máquina virtual na **Nuvem IaaS do
LSD**, no projeto **Provisionamento**, usando o OpenStack.

Este README registra o plano de execução e as decisões do grupo. Ele é
preenchido ao longo do trabalho: os valores marcados como *a preencher* só
devem ser substituídos por dados realmente obtidos, nunca por estimativas.

## Objetivos

- Operar a Nuvem do LSD pela **CLI do OpenStack**, a partir da VDI de
  provisionamento disponível em `/local/uasc/provisionamento`.
- Criar a infraestrutura da atividade: par de chaves, VM, grupo de segurança e
  volume de armazenamento.
- Fazer o deploy das aplicações da Atividade 2 na VM e expô-las pelo balanceador
  de carga `poi-atividades`.
- Persistir os dados gerados pela aplicação (por exemplo, logs) em um volume da
  nuvem, montado no sistema operacional da VM.
- Produzir um documento com as etapas e evidências (prints) de todo o processo.

## Acesso à nuvem

| Item | Valor |
| --- | --- |
| Dashboard e API | `cloud.lsd.ufcg.edu.br` |
| Projeto | `provisionamento` |
| Credenciais | LDAP para usuários antigos; para contas novas, o username da planilha com a matrícula como senha |
| Cliente | `python3-openstackclient` (ou `python-openstackclient` em virtualenv) |
| Inicialização | arquivo **OpenStack RC (Identity API v3)**, baixado em *Projeto → Acesso à API* |

```bash
. provisionamento-openrc.sh
openstack flavor list
```

A VDI de acesso é a `ubuntu_serve_2204_poi_openstack.vdi`, disponibilizada pelo
professor; nos LCCs, a equivalente fica em `/local/uasc/provisionamento`. Ela é
a máquina de onde a CLI é executada — não é a VM da atividade.

Serviços do OpenStack usados: Nova (instâncias), Glance (imagens e snapshots),
Neutron (rede e grupos de segurança), Cinder (volumes), Octavia (balanceador de
carga) e Keystone (identidade).

## Aplicações

As três aplicações de backend da Atividade 2 estão em [`apps/`](apps/): os
perfis CPU-bound, Memory-bound e IO-bound, todos em Python 3 com apenas a
biblioteca padrão e o mesmo contrato HTTP.

| Perfil | Arquivo | Trabalho executado |
| --- | --- | --- |
| CPU-bound | [`apps/cpu/server.py`](apps/cpu/server.py) | SHA-256 repetido sobre um bloco de 1 MiB |
| Memory-bound | [`apps/memory/server.py`](apps/memory/server.py) | Alocação de `size` MiB com escrita em cada página de 4 KiB |
| IO-bound | [`apps/io/server.py`](apps/io/server.py) | Escrita de `size` KiB, `fsync` e releitura |

Pontos de entrada: `GET /health` identifica o perfil e `GET /work?size=N`
executa o trabalho. Cada aplicação roda como um processo independente:

```bash
python apps/cpu/server.py    --port 8000
python apps/memory/server.py --port 8000
python apps/io/server.py     --port 8000
```

Requisito: Python 3.10 ou superior.

## Etapas da atividade

### Primeira parte — infraestrutura

1. Acessar a Nuvem do LSD pela CLI do OpenStack, usando a VDI de
   provisionamento em `/local/uasc/provisionamento`.
2. Listar os recursos disponíveis: flavors, instâncias, imagens, snapshots.
3. Criar o par de chaves que será usado no acesso SSH às VMs.
4. Criar **uma única VM** por grupo, com o flavor `general.small` e a imagem
   `ubuntu-24.04`, informando o par de chaves criado.
5. Criar um grupo de segurança abrindo as portas necessárias ao acesso à VM.
6. Configurar o balanceador de carga `poi-atividades` para o acesso SSH à VM.

Comandos previstos (ajustados conforme a nuvem responder):

```bash
openstack flavor list
openstack server list
openstack image list
openstack snapshot list

openstack keypair create <nome-da-chave> > <nome-da-chave>.pem
chmod 600 <nome-da-chave>.pem

openstack server create \
  --flavor general.small \
  --image ubuntu-24.04 \
  --key-name <nome-da-chave> \
  <nome-da-vm>

openstack security group rule create ...
```

### Segunda parte — deploy e armazenamento

1. Acessar a VM do grupo via SSH.
2. Fazer o deploy das aplicações na VM.
3. Criar um volume de **1 GB**, anexá-lo à VM e montá-lo no sistema operacional.
4. Configurar as aplicações para usarem o volume montado (por exemplo, os
   arquivos de log).
5. Configurar o balanceador de carga `poi-atividades` para as aplicações em
   execução na VM.
6. Fazer o snapshot da VM já configurada.
7. Produzir o documento do grupo com a descrição e os prints de cada etapa.
8. Responder o formulário de entrega.

> **Atenção:** apenas as respostas do formulário são consideradas na correção.

## Estrutura do repositório

| Caminho | Conteúdo |
| --- | --- |
| [`RELATORIO.md`](RELATORIO.md) | documento do grupo: descrição das etapas, prints, experimentos e análise |
| [`apps/`](apps/) | as três aplicações da Atividade 2, agora implantadas na nuvem |
| [`evidencias/`](evidencias/) | transcrição de cada comando (`.txt`), o print correspondente (`.png`) e o índice `manifest.csv` |
| [`docs/execucao/`](docs/execucao/) | um registro por task: objetivo, comandos, decisões e problemas |
| [`docs/graficos/`](docs/graficos/) | gráficos de latência, vazão e uso dos recursos |
| [`results/`](results/) | dados brutos dos experimentos e o resumo consolidado |
| [`automation/`](automation/) | fases automatizadas executadas na VDI |
| [`scripts/`](scripts/) | gerador de carga, monitor da VM e geradores de gráficos e manifesto |

## Registro de execução

Preenchido conforme as etapas forem concluídas.

| Item | Valor |
| --- | --- |
| Grupo | Daniel Anderson de Souza Silva · Ranya Duran Greco |
| Projeto no OpenStack | `Provisionamento` |
| Flavor da VM | `general.small` |
| Imagem da VM | `ubuntu-24.04` |
| Nome da VM | `vm-daniel-ranya` (`bdc0447e-fb71-48c8-9ce2-04a8c5e20ee0`) |
| Nome da chave SSH | `atividade3-daniel-ranya` |
| Endereço de acesso SSH (balanceador) | `150.165.85.77:2222` → `10.5.9.15:22` |
| Portas abertas no grupo de segurança | `tcp/22`, `tcp/8000-8002`, `icmp` — origem `10.5.8.0/22` |
| Volume | 1 GB — `vol-daniel-ranya-logs`, `/dev/vdb`, `/mnt/atividade3-logs` |
| Aplicações implantadas e portas | cpu `8000`, memory `8001`, io `8002` (externas `8100-8102`) |
| Nome do snapshot | `snap-vm-daniel-ranya` (`7fb6d24c-583d-4f04-b843-5a1a35424816`) |

## Entregáveis

- [x] Par de chaves SSH criado e usado na VM.
- [x] VM `general.small` com `ubuntu-24.04` criada (uma por grupo).
- [x] Grupo de segurança configurado.
- [x] Balanceador `poi-atividades` configurado para SSH e para as aplicações.
- [x] Aplicações em execução na VM.
- [x] Volume de 1 GB criado, anexado e montado; aplicações gravando nele.
- [x] Snapshot da VM configurada.
- [x] Documento do grupo com prints e explicação de cada etapa.
- [ ] Formulário de entrega respondido.

## Observações e pendências

- As três aplicações da Atividade 2 não gravavam log em arquivo: o
  `log_message` do servidor HTTP é silenciado de propósito, para que milhares de
  requisições de carga não acrescentem I/O ao que está sendo medido. Para a
  atividade, as aplicações passaram a escrever uma linha de inicialização e o
  `systemd` direciona essa saída (`StandardOutput=append:`) para o volume
  montado, com rotação configurada no `logrotate`.
- O flavor `general.small` exigido existe com esse nome no projeto
  (`7441c7d9-2648-4a33-907e-4d28c2270da3`), ao contrário do que o material do
  professor sugeria.
- Nenhuma credencial, chave privada ou senha é versionada neste repositório.
- A lista de balanceadores foi conferida antes de criar qualquer recurso: o
  `poi-atividades` já existia no projeto e é compartilhado com a turma, por isso
  as portas externas são 2222 e 8100-8102, diferentes das internas.

## Materiais da disciplina

- Material sobre Cloud e OpenStack: [`Cloud Computing - OpenStack CLI.pptx`](Cloud%20Computing%20-%20OpenStack%20CLI.pptx).
- VDI de provisionamento em `/local/uasc/provisionamento`.
- Guia de deploy do balanceador de carga `poi-atividades` — [Octavia, basic
  cookbook](https://docs.openstack.org/octavia/latest/user/guides/basic-cookbook.html).
- Formulário de entrega da atividade.
