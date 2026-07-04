# start-claude-cron

Script + cron para controlar o horário de reset do limite diário do Claude Code.

## Contexto

O Claude Code possui um limite de uso de 5 horas por janela. Esse limite reseta com base no horário da **primeira mensagem enviada** na sessão — não à meia-noite. Ou seja: se você mandar a primeira mensagem às 10h, o limite reseta às 15h do mesmo dia.

O objetivo desse script é **fixar o horário de reset** disparando uma mensagem leve (modelo Haiku, effort mínimo) em horários estratégicos, garantindo que o contador sempre inicie no mesmo ponto do dia.

## Horários configurados (horário de Brasília)

| Horário | Intenção |
|---------|----------|
| 08:00   | Reset matutino — limite disponível durante o dia |
| 23:00   | Reset noturno — limite disponível na madrugada |
| 23:30   | Fallback — caso o de 23h não pegue a primeira sessão |

## Arquivos

```
ask-claude.sh       # Script principal
claude-cron.log     # Output das execuções (gerado automaticamente)
```

## Como funciona

`ask-claude.sh` roda o Claude Code em modo não-interativo (`--print`) com:
- Modelo: `claude-haiku-4-5-20251001` (mais leve e barato)
- Effort: `low` (mínimo processamento)
- Pergunta: `"que dia é hoje?"` (token mínimo, só pra iniciar sessão)

## Cron jobs

```
0  8  * * *  /path/to/ask-claude.sh >> claude-cron.log 2>&1
0  23 * * *  /path/to/ask-claude.sh >> claude-cron.log 2>&1
30 23 * * *  /path/to/ask-claude.sh >> claude-cron.log 2>&1
```

Timezone do sistema: `America/Sao_Paulo` — sem conversão UTC necessária.

## Ver logs

```bash
tail -f claude-cron.log
```
