# Relatório — Atividade 3: Usando Nuvem IaaS

**Disciplina:** Provisionamento e Operação de Infraestrutura
**Grupo:** Daniel Anderson de Souza Silva · Ranya Duran Greco
**Ambiente:** Nuvem IaaS do LSD — projeto `Provisionamento` (OpenStack)
**Data da execução:** 29 de outubro de 2026

---

## 1. Resumo

Esta atividade levou as três aplicações da Atividade 2 (perfis CPU-bound,
Memory-bound e IO-bound) de uma máquina virtual local para a **Nuvem IaaS do
LSD**, operada por linha de comando OpenStack a partir da VDI de provisionamento
do professor.

O que foi construído: um par de chaves, uma VM `general.small` com a imagem
`ubuntu-24.04`, um grupo de segurança, um volume de 1 GB montado e usado para os
logs das aplicações, três listeners no balanceador compartilhado `poi-atividades`
e o snapshot da VM já configurada. O acesso SSH à VM também passa pelo
balanceador, como o enunciado pede.

Depois do deploy, medimos as três aplicações sob carga: os nove cenários base
repetidos três vezes — **15.237 requisições e nenhum erro** — mais as matrizes de
tamanho do trabalho, de saturação e de provisionamento. São 72 execuções pela
VIP e seis dentro da VM. Os resultados mostram onde cada perfil satura os
recursos de 1 vCPU e 2 GB, e estão no capítulo 5 com tabela, gráficos e
discussão.

Todo o processo foi feito pela CLI do OpenStack. As fases automatizadas estão em
[`automation/`](automation/) e cada task tem um registro próprio em
[`docs/execucao/`](docs/execucao/), com a transcrição literal dos comandos em
`evidencias/`.

---

## 2. Ambiente e acesso

| Item | Valor |
| --- | --- |
| Nuvem | `cloud.lsd.ufcg.edu.br` |
| Projeto | `Provisionamento` (`2c593796f29e4b829b1b523775e2fa26`) |
| Máquina de acesso | VDI de provisionamento (`ubuntu_serve_2204_poi_openstack.vdi`), Ubuntu 22.04 |
| Cliente | `python3-openstackclient` 5.8.0 e `python3-octaviaclient` 2.5.0 |
| Autenticação | arquivo OpenStack RC (Identity API v3), domínio `external` |
| Serviços usados | Nova, Glance, Neutron, Cinder, Octavia, Keystone |

A VDI não é a VM da atividade: ela é a estação de onde os comandos OpenStack e
o gerador de carga rodam. A VM da atividade é criada pela nuvem e não tem IP
flutuante — todo acesso a ela passa pelo balanceador `poi-atividades`.

O arquivo RC foi carregado na VDI e as credenciais existiram apenas na sessão:
nenhuma senha, chave privada ou token foi versionado no repositório. A evidência
da criação da VM (`T3.2-server-create`) foi editada para substituir a senha
inicial da instância por `(omitido)`.

**Automação.** As fases foram escritas como scripts bash executados na VDI por um
driver Python ([`automation/run.py`](automation/run.py)), que envia os scripts
por SSH, executa cada fase em um PTY e traz de volta as evidências e os
resultados. Isso não substitui a CLI: cada fase é uma sequência de comandos
`openstack` idêntica à que seria digitada, e a transcrição completa fica em
`evidencias/`.

---

## 3. Arquitetura da solução

```
        Internet / VDI de provisionamento
                     |
                     |  150.165.85.77 (IP flutuante da VIP)
                     v
        +----------------------------------+
        |  balanceador poi-atividades      |
        |  VIP 10.5.8.242 (Octavia)        |
        |                                  |
        |  2222/TCP  -> pool ssh           |
        |  8100/HTTP -> pool cpu           |
        |  8101/HTTP -> pool memory        |
        |  8102/HTTP -> pool io            |
        +----------------------------------+
                     |
                     |  rede provider (10.5.8.0/22)
                     v
        +----------------------------------+
        |  vm-daniel-ranya  10.5.9.15      |
        |  Ubuntu 24.04 · general.small    |
        |  1 vCPU · 2 GB · disco 20 GB     |
        |                                  |
        |  sshd  :22                       |
        |  app-cpu    -> :8000             |
        |  app-memory -> :8001             |
        |  app-io     -> :8002             |
        |                                  |
        |  /dev/vdb (1 GB, ext4)           |
        |  /mnt/atividade3-logs            |
        |    cpu/ · memory/ · io/          |
        +----------------------------------+
```

| Recurso | Nome | Identificador / valor |
| --- | --- | --- |
| VM | `vm-daniel-ranya` | `bdc0447e-fb71-48c8-9ce2-04a8c5e20ee0` |
| Flavor | `general.small` | `7441c7d9-2648-4a33-907e-4d28c2270da3` — 1 vCPU, 2 GB, 20 GB |
| Imagem | `ubuntu-24.04` | `8ac7c385-d5d2-488a-82a4-4e1b57ffa6b1` |
| Chave | `atividade3-daniel-ranya` | RSA 2048, `SHA256:wtHrA6TDO3pWhlcwIwdZDyNUjd7cAVOO+70TqJGQLVE` |
| Grupo de segurança | `sg-daniel-ranya` | `d60a7836-d518-48c3-ba7b-ebd0085ed208` |
| Volume | `vol-daniel-ranya-logs` | `2271182d-ac0c-4dd9-bcf7-cc535379f532` — 1 GB, `/dev/vdb` |
| Balanceador | `poi-atividades` | `57c2b14a-b746-4f34-8719-d0627e409609`, VIP `10.5.8.242` |
| IP flutuante | — | `150.165.85.77` |
| Snapshot | `snap-vm-daniel-ranya` | `6034d4a8-45bb-40ea-abe2-867e659e8f53` — 3,43 GiB |
| Snapshot do volume | `snap-vol-daniel-ranya-logs` | `df5d86d9-f4d9-43d1-a805-7edf619355d0` — 1 GB |

### Por que as portas externas são diferentes das internas

O `poi-atividades` é **um balanceador só, compartilhado por toda a turma**. Antes
de criar qualquer recurso, listamos os listeners existentes
(`T1.6-port-list`) para não colidir com as portas de outro grupo. Como 8000-8002
e 2222 já estavam em uso, a VM foi publicada em **2222, 8100, 8101 e 8102**, com
o balanceador encaminhando para **22, 8000, 8001 e 8002** dentro da VM.

---

## 4. Execução, etapa por etapa

### 4.1 Reconhecimento da nuvem

Antes de criar a VM, listamos o que o projeto oferece: flavors, servidores,
imagens e snapshots (T1.1), e as entidades de apoio — redes, sub-redes, quotas,
grupos de segurança, IPs flutuantes, volumes e chaves (T1.2).

O flavor exigido pelo enunciado **existe com esse nome** no projeto, ao contrário
do que a documentação da disciplina sugeria:

| Flavor | vCPUs | RAM | Disco |
| --- | --- | --- | --- |
| `general.small` | 1 | 2048 MB | 20 GB |

![Flavors disponíveis](evidencias/T1.1-flavor-list.png)

Também conferimos a imagem `ubuntu-24.04` e o estado do balanceador antes de
tocá-lo (T1.5). O `poi-atividades` já existia, `ACTIVE/ONLINE`, com uma lista de
listeners de outros grupos — a razão de as nossas portas externas serem outras.

### 4.2 Par de chaves

A chave foi gerada pela nuvem (`openstack keypair create`), com a privada
gravada fora do repositório e permissão `600` na VDI:

```bash
openstack keypair create --private-key atividade3-daniel-ranya.pem atividade3-daniel-ranya
chmod 600 atividade3-daniel-ranya.pem
```

| Item | Valor |
| --- | --- |
| Nome | `atividade3-daniel-ranya` |
| Tipo | RSA 2048 |
| Impressão digital | `SHA256:wtHrA6TDO3pWhlcwIwdZDyNUjd7cAVOO+70TqJGQLVE` |
| Permissão da privada | `-rw-------` |

![Impressão digital da chave](evidencias/T2.1-key-fingerprint.png)

### 4.3 Criação da VM

```bash
openstack server create \
  --flavor general.small \
  --image ubuntu-24.04 \
  --key-name atividade3-daniel-ranya \
  --network provider \
  --security-group sg-daniel-ranya \
  vm-daniel-ranya
```

A VM subiu `ACTIVE`, com a rede `provider` e o endereço `10.5.9.15`. A imagem
`ubuntu-24.04` entrega Ubuntu 24.04.3 com Python 3.12, o que atende ao requisito
das aplicações (Python 3.10+).

![Servidor criado](evidencias/T3.2-server-show.png)

### 4.4 Grupo de segurança

O grupo `sg-daniel-ranya` abre **só o necessário**, e apenas para a rede de onde
o balanceador entrega o tráfego — não para a internet:

| Direção | Protocolo | Porta | Origem |
| --- | --- | --- | --- |
| ingress | TCP | 22 | `10.5.8.0/22` |
| ingress | TCP | 8000-8002 | `10.5.8.0/22` |
| ingress | ICMP | — | `10.5.8.0/22` |
| egress | IPv4/IPv6 | qualquer | — |

O ICMP foi incluído para permitir diagnóstico de rede (ping) a partir da VDI.

![Regras do grupo de segurança](evidencias/T3.1-sg-rules.png)

### 4.5 SSH pela VIP

O acesso SSH à VM passa pelo balanceador, como o item 6 da primeira parte pede:

| Objeto | Nome | Configuração |
| --- | --- | --- |
| Listener | `ssh-daniel-ranya` | TCP, porta **2222** |
| Pool | `pool-ssh-daniel-ranya` | balanceamento `SOURCE_IP_PORT` |
| Membro | `vm-daniel-ranya` | `10.5.9.15:22`, `ONLINE` |

O pool já vinha com um health monitor TCP do próprio balanceador compartilhado;
a tentativa de criar outro devolveu **HTTP 409 "This pool already has a health
monitor"**, registrada na evidência `T4.1-hm-create`. A decisão foi manter o
monitor existente, que faz exatamente a mesma checagem, em vez de removê-lo.

```bash
ssh -i ~/.ssh/atividade3-daniel-ranya -p 2222 ubuntu@150.165.85.77
# ubuntu@vm-daniel-ranya
```

![SSH pela VIP](evidencias/T4.2-ssh-vip.png)

### 4.6 Deploy das aplicações

As três aplicações são as da Atividade 2, sem alteração de lógica: Python 3 com
biblioteca padrão, `GET /health` e `GET /work?size=N`. Foram enviadas para
`/opt/atividade3/apps` e conferidas byte a byte — o **SHA-256 de cada arquivo na
VDI é igual ao da VM**:

```text
a1cf580a...  /home/osboxes/atividade3/apps/cpu/server.py
a1cf580a...  /opt/atividade3/apps/cpu/server.py
```

![Checksums iguais origem e destino](evidencias/T5.2-checksum.png)

Cada perfil roda como um serviço `systemd` independente (`app-cpu`,
`app-memory`, `app-io`), com unit própria e endurecimento:

```ini
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
ProtectSystem=full
ReadWritePaths=/var/log/atividade3/cpu /mnt/atividade3-logs/cpu
```

Os três foram habilitados no boot e iniciados com `systemctl enable --now`. O
script `a3-smoke`, instalado em `/usr/local/bin`, verifica `/health` e `/work`
nos três perfis e sai com código diferente de zero se algum falhar.

| Perfil | Porta interna | Porta externa | Trabalho por requisição | Concorrência máxima |
| --- | --- | --- | --- | --- |
| cpu | 8000 | 8100 | SHA-256 repetido sobre 1 MiB | 32 |
| memory | 8001 | 8101 | alocação e escrita de `size` MiB | 4 |
| io | 8002 | 8102 | escrita + `fsync` + releitura | 16 |

![Instalação do a3-smoke](evidencias/T5.3-install-smoke.png)

![Health check local](evidencias/T5.5-health-local.png)

### 4.7 Volume de 1 GB e logs no volume

```bash
openstack volume create --size 1 vol-daniel-ranya-logs
openstack server add volume vm-daniel-ranya vol-daniel-ranya-logs --device /dev/vdb
# na VM
mkfs.ext4 -L a3logs /dev/vdb
mount LABEL=a3logs /mnt/atividade3-logs
```

O volume aparece como `/dev/vdb`, formatado em ext4 com o rótulo `a3logs` e
montado em `/mnt/atividade3-logs`:

```text
TARGET               SOURCE   FSTYPE OPTIONS
/mnt/atividade3-logs /dev/vdb ext4   rw,relatime

/dev/vdb        974M   24K  948M   1% /mnt/atividade3-logs
```

![Volume montado](evidencias/T6.2-mount.png)

A montagem foi gravada no `/etc/fstab` **pelo rótulo**, e não por `/dev/vdb`: o
nome do dispositivo pode mudar se o volume for desanexado e reanexado, o rótulo
não. A entrada usa `nofail`, para que a VM suba mesmo se o volume faltar.

A prova de persistência foi um `reboot` de verdade: depois de reiniciar, a
montagem voltou sozinha e um arquivo marcador criado antes continuava lá (T6.4).

![Montagem após reboot](evidencias/T6.4-after-reboot.png)

**Logs no volume.** Cada serviço recebeu um drop-in que redireciona a saída para
o volume:

```ini
[Service]
StandardOutput=append:/mnt/atividade3-logs/cpu/app.log
StandardError=append:/mnt/atividade3-logs/cpu/app.log
```

A prova de que o log está mesmo no volume foi feita pelo ponto de montagem de
cada arquivo, e não pela aparência do caminho:

```text
/mnt/atividade3-logs/cpu/app.log    -> montado em /mnt/atividade3-logs
/mnt/atividade3-logs/memory/app.log -> montado em /mnt/atividade3-logs
/mnt/atividade3-logs/io/app.log     -> montado em /mnt/atividade3-logs
```

![Logs gravados no volume](evidencias/T7.3-log-in-volume.png)

O que aparece no log: uma linha de inicialização por serviço e os *tracebacks*
que o `http.server` imprime no `stderr` quando um cliente fecha a conexão no
meio da resposta — o gerador de carga faz isso ao encerrar cada janela de 45 s.
São 137 ocorrências no perfil CPU e 158 no IO depois de todas as execuções. Não
são erros da aplicação: a requisição correspondente terminou 2xx; é o registro do
socket já fechado. O volume inteiro ficou em ~450 KB, dos quais 16 KB são o
`lost+found` do ext4.

O `logrotate` foi configurado com rotação diária, 7 cópias e `copytruncate` — a
aplicação mantém a saída aberta pelo `systemd`, então truncar o arquivo em vez de
renomeá-lo evita que ela continue escrevendo no arquivo renomeado. A rotação foi
forçada em teste e produziu `app.log.1`, visível na listagem acima.

![Rotação forçada](evidencias/T7.4-logrotate-force.png)

### 4.8 Aplicações pelo balanceador

Três listeners, três pools e três monitores HTTP, todos no balanceador
compartilhado:

| Listener | Porta | Pool | Monitor | Membro |
| --- | --- | --- | --- | --- |
| `app-cpu-daniel-ranya` | 8100 | `pool-app-cpu-daniel-ranya` | HTTP `/health`, 200 | `10.5.9.15:8000` |
| `app-memory-daniel-ranya` | 8101 | `pool-app-memory-daniel-ranya` | HTTP `/health`, 200 | `10.5.9.15:8001` |
| `app-io-daniel-ranya` | 8102 | `pool-app-io-daniel-ranya` | HTTP `/health`, 200 | `10.5.9.15:8002` |

O monitor usa `delay 5`, `timeout 4` e `max-retries 3`: um membro só sai de
rotação depois de três falhas seguidas, o que evita tirar a aplicação do ar por
um pico momentâneo.

![Estado final do balanceador](evidencias/T8.2-status.png)

O teste externo, feito da VDI, respondeu 200 nos três perfis, tanto em `/health`
quanto em `/work`:

![Teste pela VIP](evidencias/T8.3-health-vip.png)

**Teste de falha.** Para provar que o health check funciona de verdade, paramos o
`app-cpu` e esperamos. O membro foi para `ERROR` e a porta 8100 passou a
responder **503**; as portas 8101 e 8102 continuaram respondendo normalmente.
Com o serviço de volta, o membro voltou a `ONLINE` e a porta 8100 respondeu 200
de novo.

| Momento | `app-cpu` | Membro | `GET /health` em 8100 |
| --- | --- | --- | --- |
| 1 | parado | — | — |
| 2 | após ~40 s | `ERROR` | **503** |
| 3 | reiniciado | — | — |
| 4 | após ~45 s | `ONLINE` | **200** |

![Membro em ERROR e 503](evidencias/T8.4-member-degraded.png)

Isso mostra uma vantagem do desenho com três serviços separados: a falha de um
perfil não derruba os outros.

### 4.9 Snapshot da VM configurada

Com tudo no lugar — aplicações habilitadas, volume no `fstab`, logs no volume,
balanceador servindo os três perfis — tiramos o snapshot:

```bash
openstack server image create --name snap-vm-daniel-ranya vm-daniel-ranya
```

| Campo | Valor |
| --- | --- |
| ID | `7fb6d24c-583d-4f04-b843-5a1a35424816` (substituído — ver abaixo) |
| Status | `active` |
| Formato | `qcow2` |
| Tamanho | 1.983.840.256 bytes ≈ 1,85 GiB |
| `image_type` | `snapshot` |
| `instance_uuid` | `bdc0447e-...` (a VM) |
| Visibilidade | `private` |

![Criação do snapshot](evidencias/T9.2-snapshot-create.png)

Depois do snapshot, conferimos que a VM continuou `ACTIVE` e o volume continuou
`in-use` em `/dev/vdb` — a operação não interrompeu o serviço.

![Snapshot ativo](evidencias/T9.3-snapshot-show.png)

#### Snapshot final, depois das medições

Esse snapshot é o do instante em que os serviços ficaram prontos. Depois dele
vieram as medições complementares — os scripts de carga instalados em
`/opt/atividade3/scripts`, os cenários de saturação e a matriz de tamanhos — e o
teste de resize. Para a entrega valer o estado final, o snapshot foi refeito ao
fim de tudo, já de volta ao `general.small`:

```bash
openstack server image create --name snap-vm-daniel-ranya-final vm-daniel-ranya
# conferido como active
openstack image delete snap-vm-daniel-ranya
openstack image set --name snap-vm-daniel-ranya snap-vm-daniel-ranya-final
```

| Campo | Valor |
| --- | --- |
| ID | `6034d4a8-45bb-40ea-abe2-867e659e8f53` |
| Status | `active` |
| Formato | `qcow2` |
| Tamanho | 3.682.992.128 bytes ≈ 3,43 GiB |
| `min_disk` | 20 GB |

O nome final é o mesmo de antes, para quem procurar pela entrega encontrar
`snap-vm-daniel-ranya`. O snapshot antigo foi apagado **depois** de o novo estar
`active`, então nunca existiu um intervalo sem snapshot válido.

#### Snapshot do volume de logs

O snapshot da VM copia só o disco raiz. O volume de 1 GB é um disco separado e
**não** entra nele, então a parte do sistema que guarda os logs ficaria sem
cópia. O Cinder desta nuvem recusa snapshot de volume em uso
(`status must be available, but current status is: in-use`, HTTP 400), então a
operação foi feita por um ciclo curto: parar as três unidades, desmontar,
desanexar, fotografar, reanexar e montar por rótulo.

| Campo | Valor |
| --- | --- |
| Nome | `snap-vol-daniel-ranya-logs` |
| ID | `df5d86d9-f4d9-43d1-a805-7edf619355d0` |
| Status | `available` |
| Tamanho | 1 GB |

![Snapshot do volume](evidencias/T14.10-volume-snapshot-show.png)

Na volta, os `app.log` no volume voltaram a ser escritos **depois** do reanexo
(`mtime` 17:25:33, 17:27:11 e 17:29:01), o que mostra que o `fstab` e os drop-ins
continuaram apontando para o volume e não para uma cópia local.

![Escrita no volume depois do reanexo](evidencias/T14.11-log-write.png)

---

## 5. Experimentos de carga

Foram cinco blocos de medição, todos com o mesmo protocolo e a mesma forma de
coletar: cenários base, efeito do tamanho do trabalho, saturação, comparação de
provisionamento e carga local. Juntos somam 72 execuções pela VIP — 27 base, 27
de tamanho, 6 de saturação e 12 no flavor maior — mais seis feitas dentro da VM.

### 5.1 Como foi medido

- **Gerador na VDI, fora da VM.** O cliente é fechado: cada cliente espera a
  resposta antes de enviar a próxima requisição, de modo que a concorrência é
  exatamente o número de clientes. A latência registrada é a que o cliente vê e
  inclui TCP, fila no balanceador, fila no servidor e a volta.
- **Janela fixa por duração.** 5 s de aquecimento, descartados em arquivo
  separado, antes de 45 s medidos nos cenários base e 30 s nas matrizes. O que
  entra na conta é só a janela medida.
- **Monitor dentro da VM.** Um processo lê CPU, memória e swap a cada 0,5 s
  (biblioteca `psutil`), porque só o sistema operacional de dentro vê o que a
  nuvem realmente entregou.
- **Contadores dentro da aplicação.** Cada servidor expõe `GET /metrics` com
  requisições recebidas, aceitas, recusadas (503), requisições em voo, tempo de
  espera por vaga e tempo de trabalho. A leitura antes e depois de cada execução
  dá exatamente o que aconteceu naquela janela.
- **Contador de disco do sistema.** No perfil de IO o `iostat -dx 1` roda dentro
  da VM durante a execução, o que permite separar o que é espera de disco do
  volume do que é espera de CPU.
- **Repetições contemporâneas.** Os nove cenários base foram medidos três vezes
  no mesmo período, e a tabela do relatório traz média e desvio padrão. A
  primeira medição, feita de manhã, fica no repositório como histórico e não
  entra na média: o caminho até a nuvem muda ao longo do dia e misturar horários
  colocaria duas condições na mesma conta.

### 5.2 Cenários base

Cada perfil com 1, 2 e 4 clientes, sempre pela VIP — o mesmo caminho de acesso
criado na etapa 4.8. Valores como média ± desvio padrão das três repetições.

| Cenário | Conc. | Req. | rps | média (ms) | p50 (ms) | p95 (ms) | CPU VM (%) | RAM VM (%) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| cpu-c1 | 1 | 1.161 | 8,58 ± 0,58 | 116,8 ± 7,7 | 113,2 | 149,3 | 50,7 | 23,1 |
| cpu-c2 | 2 | 1.769 | 13,08 ± 0,78 | 153,2 ± 8,9 | 148,7 | 211,3 | 62,3 | 23,1 |
| cpu-c4 | 4 | 2.686 | 19,83 ± 0,85 | 201,7 ± 8,5 | 194,2 | 274,2 | 84,7 | 23,2 |
| memory-c1 | 1 | 1.335 | 9,88 ± 0,71 | 101,6 ± 7,6 | 94,6 | 130,2 | 43,8 | 24,4 |
| memory-c2 | 2 | 2.192 | 16,22 ± 1,12 | 123,6 ± 8,8 | 119,9 | 155,9 | 54,6 | 25,8 |
| memory-c4 | 4 | 3.937 | 29,10 ± 0,84 | 137,4 ± 3,9 | 133,5 | 188,7 | 81,4 | 27,0 |
| io-c1 | 1 | 534 | 3,94 ± 0,15 | 253,9 ± 9,7 | 192,2 | 556,7 | 2,3 | 23,0 |
| io-c2 | 2 | 729 | 5,38 ± 0,38 | 372,9 ± 26,3 | 308,0 | 743,6 | 2,9 | 23,0 |
| io-c4 | 4 | 894 | 6,57 ± 0,30 | 609,6 ± 27,7 | 528,7 | 1.034,9 | 3,3 | 23,0 |

**Total: 15.237 requisições nas nove células, todas 2xx, nenhum erro.** O swap
ficou em 0 MiB em todas as amostras. Nenhum cenário chegou ao limite de vagas de
trabalho dos servidores (32, 4 e 16) — o que cresceu foi a latência, não a
recusa.

![Latência por concorrência](docs/graficos/latencia.png)

![Vazão por concorrência](docs/graficos/vazao.png)

### 5.3 Análise dos cenários base

**Coerência da medição.** Com clientes fechados, vazão × latência tem de dar o
número de clientes em voo (lei de Little). Nas nove linhas o produto ficou entre
0,998 e 2,006 para 1 e 2 clientes e em 4,00 para quatro — dentro de 0,4 % do
esperado. Vazão e latência foram medidas em lados diferentes; se uma estivesse
errada, o produto não daria a concorrência.

**O caminho custa ~55 ms fixos.** Comparando a latência do cliente com o tempo de
trabalho medido no servidor, sobra um valor praticamente constante com um
cliente: 52,9 ms (CPU), 54,0 ms (memória) e 55,2 ms (IO). É o trecho
VDI → balanceador → VM, e ele não interfere na comparação entre perfis — só
precisa ser descontado quando se comparam números absolutos com os da carga local
(5.5), que não passa pelo balanceador.

| Cenário | latência do cliente | trabalho no servidor | caminho |
| --- | --- | --- | --- |
| cpu-c1 | 116,8 ms | 63,9 ms | 52,9 ms |
| cpu-c4 | 201,7 ms | 145,8 ms | 55,9 ms |
| memory-c1 | 101,6 ms | 47,6 ms | 54,0 ms |
| memory-c4 | 137,4 ms | 46,5 ms | 90,9 ms |
| io-c1 | 253,9 ms | 198,7 ms | 55,2 ms |
| io-c4 | 609,6 ms | 545,7 ms | 63,8 ms |

**CPU-bound é o perfil que mais sente o único núcleo.** A vazão vai de 8,6 para
19,8 rps, mas a latência média quase dobra (117 → 202 ms), o trabalho por
requisição sai de 64 para 146 ms e a CPU da VM chega a 84,7 % de média, com picos
de 100 %. Ganhar mais vazão aqui exige mais núcleos, não mais clientes.

**Memory-bound escala melhor até quatro clientes.** A vazão triplica (9,9 →
29,1 rps) com a latência entre 102 e 137 ms. A memória fica em 24 % a 27 %,
porque cada requisição aloca 32 MiB e libera em seguida; o **swap ficou em 0 MiB
em todas as amostras**, ou seja, 2 GB bastaram e não houve pressão de memória.

**IO-bound usa pouca CPU e satura por espera de disco.** A CPU fica entre 2,3 % e
3,3 %, porque a thread passa a maior parte do tempo bloqueada na escrita. A vazão
sobe de 3,9 para 6,6 rps, enquanto a média vai de 254 para 610 ms e o p95 passa
de 1 s. O `iostat` confirma: durante essas execuções o volume `vdb` fica entre
71 % e 85 % de ocupação, contra menos de 0,1 % do disco raiz `vda`.

![Uso dos recursos da VM](docs/graficos/uso-vm.png)

### 5.4 Efeito do tamanho do trabalho

Vinte e sete execuções — três tamanhos por perfil com 1, 2 e 4 clientes — para
separar "mais clientes" de "pedido maior".

| Perfil | Tamanho | 1 cliente | 2 clientes | 4 clientes |
| --- | --- | --- | --- | --- |
| CPU | 5 | 2,97 | 7,67 | 16,68 |
| CPU | 10 | 5,47 | 12,48 | 19,19 |
| CPU | 20 | 6,24 | 8,57 | 9,28 |
| Memory | 16 | 13,07 | 31,47 | 33,21 |
| Memory | 32 | 8,72 | 12,11 | 25,50 |
| Memory | 64 | 7,22 | 9,74 | 14,14 |
| IO | 512 KiB | 5,46 | 8,16 | 10,54 |
| IO | 1024 KiB | 4,63 | 2,48 | 2,02 |
| IO | 4096 KiB | 2,09 | 2,11 | 2,49 |

(valores em requisições por segundo de sucesso)

O trabalho medido **dentro** do servidor cresce com o tamanho, como esperado:
41,9 → 67,9 → 102,3 ms no perfil de CPU para tamanhos 5/10/20 com um cliente, e
123 → 160 → 438 ms no perfil de IO para 512/1024/4096 KiB. O que muda entre os
perfis é o quanto isso pesa na vazão:

- **CPU** ganha pouco com clientes quando o pedido é grande: com tamanho 20, ir de
  um para quatro clientes aumenta a vazão de 6,2 para 9,3 rps, porque o trabalho
  quadruplica e o núcleo é o mesmo.
- **Memória** tem um degrau entre 16 e 32 (5,4 ms contra 46 ms de trabalho): a
  alocação de 16 MiB cabe numa faixa pequena, a de 32 já entra na faixa seguinte.
  Por isso o pedido menor é o mais barato dos três.
- **IO** é o perfil em que o tamanho mais pesa: com 1024 KiB o trabalho por
  requisição chega a 2 s com quatro clientes, e a vazão despenca de 10,5 para 2,0
  rps. O `iostat` mostra o volume em 76 % (512 KiB), 90 % (1024 KiB) e 89 %
  (4096 KiB) de ocupação — o limite é a taxa de operações do disco, não a CPU,
  que fica entre 1 % e 4 %.

![Efeito do tamanho do trabalho](docs/graficos/tamanho.png)

![Ocupação do disco do volume](docs/graficos/volume.png)

### 5.5 Saturação e admissão

Oito e dezesseis clientes no tamanho padrão de cada perfil, para achar o ponto em
que a vazão para de crescer:

| Perfil | 1 | 2 | 4 | 8 | 16 |
| --- | --- | --- | --- | --- | --- |
| CPU — vazão (rps) | 8,58 | 13,08 | 19,83 | 21,52 | 21,78 |
| CPU — p95 (ms) | 149 | 211 | 274 | 396 | 786 |
| Memory — vazão (rps) | 9,88 | 16,22 | 29,10 | 33,21 | 31,28 |
| Memory — p95 (ms) | 130 | 156 | 189 | 277 | 1.335 |
| IO — vazão (rps) | 3,94 | 5,38 | 6,57 | 9,23 | 9,65 |
| IO — p95 (ms) | 557 | 744 | 1.035 | 1.119 | 2.053 |

**A vazão achatou, a latência não.** De quatro para dezesseis clientes a vazão
do perfil de CPU sobe 10 %, a de memória fica praticamente parada (29,1 → 33,2 →
31,3) e a de IO cresce 47 %, mas com o p95 quase quadruplicando (1.035 → 2.053
ms). Quadruplicar os clientes não quadruplica a vazão.

**Nenhuma requisição foi recusada.** Os seis cenários terminaram com zero erros e
o contador `rejected_503` da aplicação ficou em zero. A explicação está na espera
medida dentro da aplicação: `mean_wait_ms` ficou em 0,006 ms em todos os cenários,
mesmo com 16 clientes. Quando a requisição chega ao servidor, uma vaga está livre
na hora — **a fila está antes dele, no caminho compartilhado**.

**O limite da aplicação existe e foi medido à parte.** Para exercitar as vagas e
a recusa explícita, a carga foi executada **dentro da VM**, contra `127.0.0.1`,
sem o balanceador no meio:

| Execução | Clientes | Requisições | Sucessos | 503 | rps (sucesso) | média (ms) |
| --- | --- | --- | --- | --- | --- | --- |
| local-cpu-c8 | 8 | 424 | 424 | 0 | 20,9 | 381 |
| local-cpu-c32 | 32 | 417 | 417 | 0 | 20,0 | 1.568 |
| local-memory-c8 | 8 | 658 | 658 | 0 | 32,0 | 245 |
| local-memory-c32 | 32 | 638 | 638 | 0 | 21,5 | 1.069 |
| local-io-c8 | 8 | 82 | 82 | 0 | 4,1 | 1.956 |
| local-io-c32 | 32 | 13.244 | 127 | **13.117** | 5,6 | 52 |

- **IO:** cada escrita fica bloqueada por cerca de dois segundos, o que libera o
  interpretador e permite que as 16 vagas fiquem realmente ocupadas. A 17ª
  requisição simultânea em diante é recusada na hora: 99,04 % das tentativas
  receberam 503, com mediana de 7,2 ms. O contador do `/metrics` marcou
  exatamente 13.117 recusas — o mesmo número visto pelo cliente.
- **CPU:** as 32 vagas foram ocupadas até o limite (pico de 32 requisições em
  voo), sem recusa, porque o limite coincide com o número de clientes. O que muda
  é o trabalho: 365 ms com 8 clientes e 1.346 ms com 32, para a mesma vazão de
  ~20 rps.
- **Memória:** o trabalho leva ~50 ms, curto demais para ocupar as quatro vagas
  quando cliente e servidor dividem o mesmo vCPU; não houve recusa, só fila
  (média de 1,07 s e p95 de 4,0 s com 32 clientes).

A recusa rápida é deliberada: em vez de enfileirar sem limite, o servidor devolve
503 quando todas as vagas estão ocupadas, o que mantém memória e tempo de
resposta sob controle. Os números absolutos desta carga não são comparáveis aos
da VIP — cliente e servidor disputam o mesmo vCPU —, mas o comportamento de
admissão é o mesmo que vale na nuvem.

![Saturação](docs/graficos/saturacao.png)

### 5.6 Demanda × provisionamento

A mesma VM foi redimensionada para `general.medium` (2 vCPU, 4 GB), medida com a
mesma carga e devolvida para `general.small`. Disco, IP, serviços e volume são os
mesmos; a única variável é o provisionamento.

| Perfil | Clientes | general.small | general.medium | Variação |
| --- | --- | --- | --- | --- |
| CPU | 1 | 8,58 | 8,53 | −1 % |
| CPU | 2 | 13,08 | 18,95 | +45 % |
| CPU | 4 | 19,83 | 37,65 | +90 % |
| CPU | 8 | — | 34,40 | |
| Memory | 1 | 9,88 | 10,46 | +6 % |
| Memory | 2 | 16,22 | 25,30 | +56 % |
| Memory | 4 | 29,10 | 28,34 | −3 % |
| Memory | 8 | — | 26,69 | |
| IO | 1 | 3,94 | 7,33 | +86 % |
| IO | 2 | 5,38 | 8,00 | +49 % |
| IO | 4 | 6,57 | 15,18 | +131 % |
| IO | 8 | — | 15,06 | |

(valores em requisições por segundo de sucesso)

- **Com um cliente não há ganho nenhum.** O trabalho de uma requisição é
  sequencial; um segundo núcleo não acelera uma única thread. É a demonstração de
  que, com um cliente, o gargalo é o trabalho em si e não o provisionamento.
- **De dois clientes em diante o flavor maior se paga.** No perfil de CPU a
  vazão dobra com quatro clientes (19,83 → 37,65 rps) e o trabalho por requisição
  cai de 97 para 59 ms.
- **A memória ganha menos e satura antes.** O medium com dois clientes (25,3 rps)
  quase alcança o small com quatro (29,1 rps) e daí em diante os dois empatam: o
  limite passa a ser a alocação dos 32 MiB por requisição.
- **O IO é o mais beneficiado (2,3×).** Com dois vCPU, mais threads ficam
  bloqueadas na escrita ao mesmo tempo e a preparação dos dados deixa de competir
  com o núcleo único.
- **O medium também satura.** Com oito clientes o perfil de CPU cai para 34,4 rps,
  o trabalho por requisição dobra para 100 ms e o p95 vai a 1.115 ms.

![Mesma VM, dois provisionamentos](docs/graficos/flavor.png)

Depois das medições a VM voltou para `general.small` (`ACTIVE`, `nproc` = 1,
1.967 MiB, três serviços ativos, volume montado, três portas respondendo 200).
O snapshot final foi tirado depois da volta.

### 5.7 Série temporal

As amostras de 0,5 s mostram o formato da carga dentro da janela, com quatro
clientes em um cenário de cada perfil:

| Perfil | CPU da VM (mín / mediana / máx) | Memória da VM (mín / mediana / máx) |
| --- | --- | --- |
| CPU-bound | 0 % / 84 % / 100 % | 22,8 % / 23,2 % / 23,7 % |
| Memory-bound | 0 % / 80 % / 100 % | 23,8 % / 26,9 % / 28,5 % |
| IO-bound | 0 % / 3,3 % / 11,8 % | 22,8 % / 23,0 % / 23,2 % |

O mínimo 0 % vem do começo da coleta, antes de o gerador começar. Duas leituras
importam:

- **CPU e memória se comportam de forma diferente.** O perfil de CPU usa o núcleo
  de forma quase contínua, com picos de 100 %; o de memória sobe com degraus,
  porque a alocação de 32 MiB aparece nas amostras e some na seguinte; o de IO
  fica baixo e serrilhado, do tamanho do trabalho de preparar o tampão antes de
  bloquear na escrita.
- **A média esconde o pico.** A memória tem média de 23 % a 27 %, mas o pico
  chega a 28,5 %; é esse número que importa para dimensionar RAM, como mostram os
  0 MiB de swap.

![Série temporal](docs/graficos/serie-temporal.png)

### 5.8 Leitura de provisionamento

Para esta carga, `general.small` (1 vCPU, 2 GB) atende com folga até dois clientes
concorrentes nos três perfis. A partir daí:

- **CPU-bound** é o único perfil limitado pelo núcleo: a CPU da VM chega a 100 % e
  a vazão para em ~20 rps. O `general.medium` dobra a vazão com quatro clientes,
  e o ganho aparece a partir do segundo cliente.
- **Memory-bound** é o perfil mais confortável: 2 GB bastaram, sem uma única
  amostra de swap, e apenas uma requisição de cada vez aloca 32 MiB.
- **IO-bound** é limitado pelo disco do volume, não pela VM: a CPU fica em 3 %, o
  `vdb` fica acima de 76 % de ocupação e o `w_await` chega a centenas de
  milissegundos. Mais vCPU ajuda (a vazão mais que dobra no medium), mas o teto
  continua sendo a taxa de operações do volume de 1 GB.
- **O volume de 1 GB é folgado para logs:** depois de todas as execuções e de uma
  rotação forçada, o uso ficou em 1 % (620 KiB). O que limita o perfil de IO é a
  taxa de escrita, não o espaço.

O gargalo dominante nas medições pela VIP não foi nenhum dos três: foi o caminho
compartilhado VDI → balanceador → VM, que fixa ~55 ms de custo por requisição e
limita a taxa de chegada antes da aplicação. As vagas internas só foram
exercitadas quando a carga passou a rodar dentro da VM (5.5).

---

## 6. Cobertura dos requisitos do enunciado

A tabela abaixo liga cada item pedido ao que foi feito e à evidência que
permite conferir. Todas as evidências estão em `evidencias/` no formato `.txt`
(transcrição literal) e `.png` (o print correspondente).

| # | Requisito | Como foi atendido | Evidência |
| --- | --- | --- | --- |
| 1 | Acesso à nuvem pela VDI, com a CLI | Login no projeto `Provisionamento` com escopo por ID, a partir da VDI do professor | `T0.1`, `T0.2`, `T0.5`, `T0.6` |
| 2 | Listar flavors, instâncias, imagens e snapshots | Listagens feitas antes de criar qualquer recurso | `T1.1-flavor-list`, `T1.1-server-list`, `T1.1-image-list`, `T1.1-snapshot-list` |
| 3 | Criar o par de chaves | `openstack keypair create`, chave privada só na VDI, com `chmod 600` | `T2.1-keypair-list`, `T2.1-key-fingerprint` |
| 4 | Uma VM por grupo, `general.small`, `ubuntu-24.04`, com a chave | Criação com flavor, imagem, chave, rede e grupo de segurança nomeados | `T3.2-server-create`, `T3.2-server-show` |
| 5 | Grupo de segurança com as portas necessárias | `tcp/22`, `tcp/8000-8002` e `icmp`, origem `10.5.8.0/22` | `T3.1-sg-create`, `T3.1-sg-rules`, `T3.1-rule-ssh` |
| 6 | `poi-atividades` dando acesso SSH à VM | Listener `2222` → pool → membro `10.5.9.15:22` | `T4.1-*`, `T4.2-ssh-vip` |
| 7 | Acesso SSH à VM | Sessão aberta pela VIP, com a chave do grupo | `T4.2-ssh-vip` |
| 8 | Deploy das aplicações na VM | Código enviado por `tar` pelo túnel SSH, três serviços `systemd` | `T5.2-*`, `T5.3-*`, `T5.5-health-local` |
| 9 | Volume de 1 GB criado, anexado e montado | `vol-daniel-ranya-logs` em `/dev/vdb`, ext4 por rótulo, `fstab` com `nofail`, persistência provada com reboot | `T6.1-*`, `T6.2-*`, `T6.3-*`, `T6.4-*` |
| 10 | Aplicações usando o volume | `StandardOutput=append:` para o volume, `logrotate` com `copytruncate`, prova de escrita no volume | `T7.1-*`, `T7.2-*`, `T7.3-*`, `T7.4-*` |
| 11 | `poi-atividades` roteando para as aplicações | Três listeners (`8100-8102`), pools com health check e membros | `T8.2-*`, `T8.3-health-vip`, `T8.3-work-vip` |
| 12 | Snapshot da VM configurada | Snapshot tirado com a VM pronta, refeito ao fim das medições e conferido como `active`; o volume de logs ganhou snapshot próprio | `T9.2-snapshot-create`, `T9.3-*`, `T14.4-snapshot-created`, `T14.10-volume-snapshot-show` |
| 13 | Relatório com prints de cada etapa | Este documento, com os prints das evidências e as tabelas e gráficos das medições | `evidencias/manifest.csv` |
| 14 | Formulário de entrega | Preenchido pelo grupo, fora do repositório | — |

O item 14 é o único que não tem evidência aqui: o enunciado avisa que só o que
for enviado pelo formulário é corrigido, então ele é o último passo da entrega.

## 7. Dificuldades encontradas

1. **Balanceador compartilhado e imutável.** Enquanto outro grupo aplicava uma
   mudança, o `poi-atividades` respondia **HTTP 409 "is immutable"**. As fases de
   criação passaram a tentar de novo com pausa, e a parar quando o erro é
   definitivo (recurso já existe), para não gastar minutos repetindo o que nunca
   vai passar.
2. **Health monitor já existente no pool de SSH.** A criação de um monitor TCP
   retornou 409 porque o pool já tinha um. Optamos por manter o existente.
3. **Portas ocupadas na VIP.** A lista de listeners mostrou 8000-8002 e 2222 em
   uso por outros grupos. A solução foi publicar em 2222 e 8100-8102.
4. **VM sem IP flutuante.** Não havia endereço público para a VM; todo acesso
   (SSH e aplicações) teve de passar pelo balanceador, o que na prática virou uma
   vantagem: o caminho testado é o caminho real.
5. **Log em arquivo em uma aplicação que silencia o log.** As aplicações da
   Atividade 2 não gravavam nada. O `systemd` passou a redirecionar a saída para o
   volume, e o `log_message` continua silenciado de propósito, para não somar I/O
   às medições.
6. **Rotação com arquivo aberto.** O `logrotate` precisou de `copytruncate`,
   porque o `systemd` mantém a saída aberta e o arquivo renomeado continuaria
   recebendo escrita.
7. **Falha transitória da nuvem.** Uma checagem do plugin do Octavia falhou uma
   vez logo após o login e passou nas seguintes. A checagem passou a tentar três
   vezes com pausa.
8. **Primeira matriz de carga perdida.** Uma execução foi interrompida antes do
   fim; a matriz foi repetida inteira e só os dados da execução completa ficaram
   registrados.
9. **Snapshot de volume com o volume em uso é recusado.** O Cinder respondia
   `HTTP 400 — status must be available, but current status is: in-use`. A saída
   foi parar as três unidades, desmontar e desanexar o volume, tirar o snapshot e
   reanexar, conferindo depois que os logs continuavam sendo escritos no volume.
10. **Resize demora e reinicia a VM.** O `RESIZE` levou cerca de três minutos e
    meio até `VERIFY_RESIZE`, e a confirmação reinicia a máquina. O script passou
    a esperar o SSH e as três portas responderem antes de medir ou de tirar
    snapshot.

---

## 8. Conclusão

A atividade mostrou a diferença entre **provisionar** e **operar**. Provisionar
foi criar chave, VM, grupo de segurança, volume e listeners — cada passo com um
comando de CLI e uma evidência. Operar foi o que veio depois: descobrir que o
balanceador é compartilhado e imutável, que a VM não tem IP público, que um
serviço com log aberto precisa de `copytruncate`, e que um health check só vale
se for testado derrubando o serviço de propósito.

Os números dos experimentos fecham com o que a infraestrutura oferece: 1 vCPU
satura o perfil CPU-bound em torno de 20 rps com 4 clientes, o perfil de memória
cresce sem tocar o swap, e o de I/O para perto de 10 rps por contenção de escrita
no disco do volume. O volume de 1 GB, usado para os logs, ficou com cerca de
630 KB ocupados após todas as execuções e uma rotação — a escolha de tamanho se
mostrou adequada, e a rotação funciona.

Todos os itens pedidos foram entregues: par de chaves, uma VM `general.small`
com `ubuntu-24.04`, grupo de segurança, SSH pela VIP, aplicações pela VIP, volume
de 1 GB montado e usado para logs, e snapshot da VM configurada. O repositório
guarda a transcrição de cada comando (`evidencias/`), um registro por task
(`docs/execucao/`) e os dados brutos dos experimentos (`results/`).

---

## 9. Apêndice — onde está cada evidência

| Conteúdo | Onde |
| --- | --- |
| Transcrição literal de cada comando | `evidencias/T<fase>.<n>-*.txt` |
| Print de cada transcrição | `evidencias/T<fase>.<n>-*.png` |
| Índice das evidências (task, arquivo, tamanho, sha256, dimensões) | `evidencias/manifest.csv` |
| Registro por task (objetivo, comandos, decisões, problemas) | `docs/execucao/T*.md` |
| Índice dos registros | `docs/execucao/INDEX.md` |
| Dados brutos dos experimentos | `results/measurements.csv`, `results/warmup.csv`, `results/resources-*.csv` |
| Resumo consolidado dos experimentos | `results/summary.csv` |
| Gráficos | `docs/graficos/*.png` |
| Scripts das fases automatizadas | `automation/remote/*.sh` |
| Gerador de carga e monitor | `scripts/load_test.py`, `scripts/monitor.py` |
| Geração dos gráficos e do manifesto | `scripts/make_charts.py`, `scripts/make_manifest.py` |

**Cobertura das evidências:** 123 transcrições, 123 prints, 41 tasks — todas com
print; nenhuma evidência textual ficou sem imagem.
