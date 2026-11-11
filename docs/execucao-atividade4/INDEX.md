# Atividade 4 — índice de execução

Registro por tarefa da conteinerização. Cada linha aponta para um arquivo
Markdown com objetivo, comandos, saída, decisões e problemas; as evidências
(`.txt` e `.png`) ficam em `evidencias/`.

Status possíveis: `pendente`, `em andamento`, `concluída`, `bloqueada`.

| Task | Descrição | Status | Registro |
| --- | --- | --- | --- |
| T24.1 | Instalar Docker Engine e plugin Compose na VDI | concluída | [T24.1.md](T24.1.md) |
| T24.2 | Instalar Docker Engine e plugin Compose na VM | concluída | [T24.2.md](T24.2.md) |
| T25.1 | Dockerfile, `.dockerignore` e contexto de build | concluída | [T25.1.md](T25.1.md) |
| T25.2 | Build das três imagens na VDI | concluída | [T25.2.md](T25.2.md) |
| T25.3 | Publicação das imagens no Docker Hub | concluída | [T25.3.md](T25.3.md) |
| T26.1 | Preparar volume e diretórios de log para os containers | concluída | [T26.1.md](T26.1.md) |
| T26.2 | Cutover: parar `systemd` e subir o Docker Compose | concluída | [T26.2.md](T26.2.md) |
| T26.3 | Serviços, healthchecks e logs no volume | concluída | [T26.3.md](T26.3.md) |
| T27.1 | Verificação local das três aplicações | concluída | [T27.1.md](T27.1.md) |
| T27.2 | Verificação pela VIP do balanceador | concluída | [T27.2.md](T27.2.md) |
| T27.3 | Teste de failover de um container | concluída | [T27.3.md](T27.3.md) |
| T27.4 | Configuração do balanceador: listener, pool e monitor | concluída | [T27.4.md](T27.4.md) |
| T28.1 | Snapshot da VM conteinerizada | concluída | [T28.1.md](T28.1.md) |
| T29.1 | Relatório final e dados do formulário | concluída | [T29.1.md](T29.1.md) |

## Evidências esperadas

| Prefixo | Conteúdo |
| --- | --- |
| `T24.*` | versões de Docker/Compose, `docker info`, configuração do daemon |
| `T25.*` | build das três imagens, tamanhos, digests, push e conferência no Hub |
| `T26.*` | `compose config`, `compose ps`, health, permissões e escrita no volume |
| `T27.*` | `/health` e `/work` local e pela VIP, `compose stop/start`, status do membro no LB, listener/pool/monitor do `poi-atividades` |
| `T28.*` | snapshot criado e estado final dos recursos |
| `T29.*` | consolidação final: manifest, contagem de evidências e dados do formulário |
