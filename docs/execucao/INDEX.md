# Registro de execução — Atividade 3

Um arquivo por task em `docs/execucao/`, no mesmo formato: objetivo, comandos
executados, o que aconteceu, saída, decisões e problemas. As evidências ficam em
`evidencias/` com o identificador da task — `.txt` com a transcrição literal e
`.png` com a mesma transcrição renderizada, que é o print usado no relatório.

Todas as execuções foram feitas a partir da VDI de provisionamento do professor,
com a CLI do OpenStack, e as fases automatizadas estão em
[`automation/`](../../automation/).

## Primeira parte — infraestrutura

| Task | Descrição | Evidência | Status |
| --- | --- | --- | --- |
| T0.1 | Identidade da máquina de acesso | `T0.1-host-info` | concluída |
| T0.2 | Conectividade com a nuvem | `T0.2-connectivity` | concluída |
| T0.3 | Localização do arquivo RC | `T0.3-openrc-files` | concluída |
| T0.4 | Instalação das ferramentas | `T0.4-install-tools`, `T0.4-installed-versions` | concluída |
| T0.5 | Cliente OpenStack | `T0.5-openstack-version` | concluída |
| T0.6 | Autenticação na nuvem | `T0.6-project-show`, `T0.6-token-issue` | concluída |
| T1.1 | Flavors, instâncias, imagens e snapshots | `T1.1-*` | concluída |
| T1.2 | Entidades de apoio (rede, quota, IPs, volumes) | `T1.2-*` | concluída |
| T1.3 | Flavor exigido e balanceador da disciplina | `T1.3-*` | concluída |
| T1.4 | Cliente do Octavia | `T1.4-install-octaviaclient` | concluída |
| T1.5 | Estado do `poi-atividades` | `T1.5-*` | concluída |
| T1.6 | Portas ocupadas na VIP | `T1.6-port-list` | concluída |
| T2.1 | Criação do par de chaves | `T2.1-*` | concluída |
| T3.1 | Grupo de segurança | `T3.1-*` | concluída |
| T3.2 | Criação da VM | `T3.2-*` | concluída |
| T4.1 | Listener, pool e membro de SSH | `T4.1-*` | concluída |
| T4.2 | Acesso SSH pela VIP | `T4.2-ssh-vip` | concluída |

## Segunda parte — deploy, armazenamento e snapshot

| Task | Descrição | Evidência | Status |
| --- | --- | --- | --- |
| T5.1 | Inventário da VM, usuário e diretórios | `T5.1-*` | concluída |
| T5.2 | Transferência das aplicações | `T5.2-*` | concluída |
| T5.3 | Unidades `systemd` e `a3-smoke` | `T5.3-*` | concluída |
| T5.4 | `enable --now` dos serviços | `T5.4-enable-start` | concluída |
| T5.5 | Verificação local das aplicações | `T5.5-health-local` | concluída |
| T5.6 | Logs iniciais | `T5.6-app-logs` | concluída |
| T6.1 | Criação e anexação do volume | `T6.1-*` | concluída |
| T6.2 | Formatação e montagem | `T6.2-*` | concluída |
| T6.3 | Montagem persistente (`fstab`) | `T6.3-*` | concluída |
| T6.4 | Persistência comprovada com reboot | `T6.4-*` | concluída |
| T7.1 | Diretórios de log no volume | `T7.1-volume-dirs` | concluída |
| T7.2 | Drop-ins redirecionando o log | `T7.2-*` | concluída |
| T7.3 | Prova de que o log está no volume | `T7.3-*` | concluída |
| T7.4 | Rotação com `logrotate` | `T7.4-*` | concluída |
| T8.1 | Estado do balanceador antes da publicação | `T8.1-listener-list` | concluída |
| T8.2 | Listeners, pools, monitores e membros | `T8.2-*` | concluída |
| T8.3 | Teste externo pela VIP | `T8.3-*` | concluída |
| T8.4 | Health check e comportamento em falha | `T8.4-*` | concluída |
| T9.1 | Estado da VM antes do snapshot | `T9.1-before` | concluída |
| T9.2 | Criação do snapshot | `T9.2-snapshot-create` | concluída |
| T9.3 | Conferência do snapshot | `T9.3-*` | concluída |

## Medições e entrega

| Task | Descrição | Evidência | Status |
| --- | --- | --- | --- |
| T10.1 | Dependência do monitor na VM | `T10.1-psutil` | concluída |
| T10.2 | Envio do monitor para a VM | `T10.2-monitor-upload` | concluída |
| T10.3 | 9 execuções de carga (3 perfis × 1/2/4) | `T10.3-*`, `results/summary.csv` | concluída |
| T10.4 | Consolidação das medições | `results/summary.csv`, `docs/graficos/` | concluída |
| T11.1 | Relatório | `RELATORIO.md` | concluída |
| T11.2 | Índice das evidências | `evidencias/manifest.csv` | concluída |
| T11.3 | Revisão de notas e limpeza | — | concluída |
