# start-claude-cron

Script + cron para controlar o horário de reset do limite diário do Claude Code.

## Contexto

O Claude Code possui um limite de uso de 5 horas por janela. Esse limite reseta com base no horário da **primeira mensagem enviada** na sessão — não à meia-noite. Ou seja: se você mandar a primeira mensagem às 10h, o limite reseta às 15h do mesmo dia.

O objetivo desse script é **fixar o horário de reset** disparando uma mensagem leve (modelo Haiku, effort mínimo) em horários estratégicos, garantindo que o contador sempre inicie no mesmo ponto do dia.

## Horários configurados (horário de Brasília)

| Janela | Tentativas | Intenção |
|--------|------------|----------|
| 08:00–08:50 | 6, de 10 em 10 min | Reset matutino — limite disponível durante o dia |
| 23:00–23:50 | 6, de 10 em 10 min | Reset noturno — limite disponível na madrugada |

O job roda a cada 10 minutos dentro de cada janela porque não é possível garantir de antemão o horário exato da primeira mensagem do dia/madrugada. Como o script pula a execução quando já existe sessão ativa (ver "Skip de sessão ativa" abaixo), as tentativas repetidas não têm custo de token — só a primeira de cada janela de fato chama o Claude.

## Arquivos

```
ask-claude.sh       # Script principal
.session-marker     # Marker com o epoch da última sessão iniciada (gerado automaticamente, git-ignored)
claude-cron.log     # Output das execuções (gerado automaticamente)
```

## Como funciona

`ask-claude.sh` roda o Claude Code em modo não-interativo (`--print`) com:
- Modelo: `claude-haiku-4-5-20251001` (mais leve e barato)
- Effort: `low` (mínimo processamento)
- Pergunta: `"que dia é hoje?"` (token mínimo, só pra iniciar sessão)

## Skip de sessão ativa

Antes de chamar o Claude, o script verifica se já existe uma sessão ativa dentro da janela de 5h (`SESSION_WINDOW_MINUTES`, default 300min), considerando dois sinais:

- **Marker do script** (`.session-marker`): timestamp gravado após a última chamada bem-sucedida, e também atualizado quando o script pula por já ter detectado sessão ativa — assim as execuções seguintes não repetem a checagem de atividade do usuário até a janela expirar.
- **Atividade do usuário**: mtime de `CLAUDE_ACTIVITY_FILE` (default `~/.claude/history.jsonl`) — detecta sessões abertas manualmente, fora do cron.

Se qualquer um dos dois estiver dentro da janela, o script pula a chamada, loga o motivo e sai sem gastar tokens. Esse comportamento é controlado pela feature flag `ENABLE_SESSION_SKIP` (default `true`) — defina como `false` para sempre chamar o Claude, ignorando os markers. Veja `.env.example` para todas as variáveis.

## Cron jobs

```
0,10,20,30,40,50 8  * * *  /path/to/ask-claude.sh >> claude-cron.log 2>&1
0,10,20,30,40,50 23 * * *  /path/to/ask-claude.sh >> claude-cron.log 2>&1
```

Usamos lista de minutos (2 linhas) em vez de 12 entradas explícitas — mesmo efeito, menos repetição para manter.

Timezone do sistema: `America/Sao_Paulo` — sem conversão UTC necessária.

### Instalando em um PC novo

```bash
./install-cron.sh
```

O script só **adiciona** as 2 linhas acima ao seu crontab — não remove nem altera nada que já exista, e roda de novo sem duplicar (pula linhas já presentes).

**Atenção:** se você já rodou este projeto antes nesse PC (crontab antigo com horários fixos, por exemplo), remova essas entradas antigas manualmente com `crontab -e` antes de rodar o script, para não acabar com execuções duplicadas.

## Ver logs

```bash
tail -f claude-cron.log
```
