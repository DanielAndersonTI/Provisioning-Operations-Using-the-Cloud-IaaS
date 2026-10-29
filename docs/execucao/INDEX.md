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

## Medições complementares

| Task | Descrição | Evidência | Status |
| --- | --- | --- | --- |
| T12.1 | Redeploy conferido por checksum e reinício dos serviços | `T12.1-*` | concluída |
| T12.2 | Diretório de trabalho do perfil IO no volume | `T12.2-*` | concluída |
| T12.3 | Prova de que o IO ocorre no volume (`iostat`) | `T12.3-*` | concluída |
| T12.4 | Matriz tamanho do trabalho × concorrência (27 execuções) | `T12.4-*`, `results/summary-size.csv` | concluída |
| T12.5 | Saturação com 8 e 16 clientes | `T12.5-*`, `results/summary-saturation.csv` | concluída |
| T12.6 | Três repetições contemporâneas dos cenários base | `T12.6-*`, `results/summary.csv` | concluída |
| T12.7 | Consolidação final das medições | `T12.7-summary` | concluída |
| T12.8 | Carga local dentro da VM e recusa por vagas | `T12.8-*`, `results/measurements-local.csv` | concluída |

## Provisionamento e entrega final

| Task | Descrição | Evidência | Status |
| --- | --- | --- | --- |
| T13.1 | Estado da VM antes do resize | `T13.1-*` | concluída |
| T13.2 | Pedido de resize para `general.medium` | `T13.2-*` | concluída |
| T13.3 | Confirmação do resize | `T13.3-resize-confirm` | concluída |
| T13.4 | Recursos dentro da VM em `general.medium` | `T13.4-medium-resources` | concluída |
| T13.5 | 12 execuções em `general.medium` (3 perfis × 1/2/4/8) | `T13.5-*`, `results/summary-medium.csv` | concluída |
| T13.6 | Pedido de resize de volta para `general.small` | `T13.6-*` | concluída |
| T13.7 | Confirmação da volta | `T13.7-resize-back-confirm` | concluída |
| T13.8 | Recursos após a volta, flavor final | `T13.8-*` | concluída |
| T13.9 | Comparação `small` × `medium` | `T13.9-summary` | concluída |
| T14.1 | Volume antes do snapshot | `T14.1-volume-before` | concluída |
| T14.2 | Snapshot do volume com o volume anexado (recusado) | `T14.2-*` | concluída |
| T14.3 | Imagens existentes antes do snapshot novo | `T14.3-snapshot-before` | concluída |
| T14.4 | Criação e conferência do snapshot novo da VM | `T14.4-*` | concluída |
| T14.5 | Remoção do snapshot antigo | `T14.5-snapshot-delete-old` | concluída |
| T14.6 | Troca de nome do snapshot | `T14.6-*` | concluída |
| T14.7 | Estado dos recursos ao fim da fase | `T14.7-final-state` | concluída |
| T14.8 | Volume antes do ciclo e parada das aplicações | `T14.8-*` | concluída |
| T14.9 | Desmontagem e desanexação do volume | `T14.9-*` | concluída |
| T14.10 | Snapshot do volume | `T14.10-*` | concluída |
| T14.11 | Reanexo, montagem, serviços e escrita no volume | `T14.11-*` | concluída |
| T14.12 | Estado final dos recursos | `T14.12-final-state` | concluída |

## Vagas, mistura de tamanhos e reconciliação

| Task | Descrição | Evidência | Status |
| --- | --- | --- | --- |
| T15.1 | Cópia manual da aplicação fora do balanceador | `T15.1-manual-server` | concluída |
| T15.2 | Matriz de vagas: 1/4/32 (CPU) e 4/8/16 (IO), três repetições | `T15.2-*`, `results/summary-vagas.csv` | concluída |
| T15.3 | Serviços e portas originais intactos ao fim da fase | `T15.3-services-intact` | concluída |
| T16 | Mistura de tamanhos de requisição, quatro clientes | `T16-*`, `results/summary-misto.csv` | concluída |
| T17.1 | Segunda medição do bloco de tamanho (CPU e IO) | `T17-*` | concluída |
| T17.2 | Conferência pelo teto de plausibilidade do p95 | `T17.2-check-cells-*` | concluída |
| T17.3 | Consolidação final da reconciliação | `T17.3-summary` | concluída |
| T18 | Repetições de três células citadas no relatório | `T18-*` | concluída |
| T19.1 | Segunda medição do tamanho padrão do perfil de memória | `T19-*` | concluída |
| T19.2 | Conferência das células de memória contra o teto | `T19.2-check-cells` | concluída |
