# start-claude-cron

Script + cron para controlar o horário de reset do limite diário do Claude Code.

## Contexto

O Claude Code possui um limite de uso de 5 horas por janela. Esse limite reseta com base no horário da **primeira mensagem enviada** na sessão — não à meia-noite. Ou seja: se você mandar a primeira mensagem às 10h, o limite reseta às 15h do mesmo dia.

O objetivo desse script é **fixar o horário de reset** disparando uma mensagem leve (modelo Haiku, effort mínimo) em horários estratégicos, garantindo que o contador sempre inicie no mesmo ponto do dia.

## Horários configurados

O cron roda a cada `CRON_INTERVAL_MINUTES` minutos (default 5), dentro da faixa `CRON_START_HOUR`–`CRON_END_HOUR` (default 05h–21h). Fora dessa faixa (madrugada) não roda — isso é intencional. Os três valores são configuráveis via `.env` (veja `.env.example`) e usados pelo `install-cron.sh` pra gerar a linha do crontab; não há horário fixo hardcoded no código.

Em cada execução, o script só chama o Claude de fato se não houver sessão ativa dentro da janela de 5h (`SESSION_WINDOW_MINUTES`, ver "Skip de sessão ativa" abaixo); caso contrário, pula sem custo de token — é uma checagem local, não uma chamada de API.

O intervalo curto existe pra minimizar o atraso entre o fim real de uma janela de 5h e a próxima tentativa do script de fixar o reset: como o script só sabe que uma janela acabou quando roda de novo, um intervalo de 5 minutos garante no máximo ~5min de atraso, em vez de até 5h no esquema antigo de 4 horários fixos por dia.

## Arquivos

```
ask-claude.sh       # Script principal
install-cron.sh     # Gera/instala a linha do crontab a partir do .env
.session-marker     # Marker com o início fixo da janela atual + origem (gerado automaticamente, git-ignored)
claude-cron.log     # Output das execuções (gerado automaticamente)
```

## Como funciona

`ask-claude.sh` roda o Claude Code em modo não-interativo (`--print`) com:
- Modelo: `claude-haiku-4-5-20251001` (mais leve e barato)
- Effort: `low` (mínimo processamento)
- Pergunta: `"que dia é hoje?"` (token mínimo, só pra iniciar sessão)

## Skip de sessão ativa

`.session-marker` guarda o **início fixo** da janela atual de 5h, no formato `<epoch> <origem>` (origem = `script` ou `usuário`). É fixo — não é reescrito a cada checagem — porque se ele deslizasse pra frente toda vez que houvesse atividade nova, o fim da janela nunca chegaria enquanto o uso continuasse, e a janela de 5h real do Claude Code (que conta a partir da primeira mensagem, não da última) sairia de sincronia sem o script perceber.

Em cada execução:

1. Se o marker existe e ainda está dentro da janela (`SESSION_WINDOW_MINUTES`, default 300min): pula, loga a origem e o horário de expiração (`sessão ativa (origem), expira às HH:MM (faltam Xmin)`), **sem alterar o marker**.
2. Se o marker não existe ou já expirou: verifica `CLAUDE_ACTIVITY_FILE` (mtime, default `~/.claude/history.jsonl`). Se essa atividade ainda está dentro da janela, o script conclui que o usuário já iniciou uma sessão nova por conta própria, adota esse horário como início (`sessão do usuário detectada, expira às HH:MM`) e grava o marker — aproximação sujeita a até `CRON_INTERVAL_MINUTES` de erro, já que só sabemos a **última** mensagem vista, não a primeira.
3. Se nenhum dos dois sinais está dentro da janela: chama o Claude de verdade, e o novo início (exato, porque foi o próprio script quem disparou) vira o marker.

Esse comportamento é controlado pela feature flag `ENABLE_SESSION_SKIP` (default `true`) — defina como `false` para sempre chamar o Claude, ignorando os markers. Veja `.env.example` para todas as variáveis.

## Cron jobs

```
*/5 5-21 * * *  /path/to/ask-claude.sh >> claude-cron.log 2>&1
```

Roda a cada 5 minutos entre 05h e 21h (valores default de `CRON_INTERVAL_MINUTES`/`CRON_START_HOUR`/`CRON_END_HOUR`, configuráveis via `.env`). A maioria das execuções apenas confere o marker e sai sem chamar o Claude — só dispara de fato quando a janela de 5h expira.

Timezone do sistema: `America/Sao_Paulo` — sem conversão UTC necessária.

### Instalando em um PC novo

```bash
./install-cron.sh
```

O `install-cron.sh` lê `CRON_START_HOUR`/`CRON_END_HOUR`/`CRON_INTERVAL_MINUTES` do `.env` (ou usa os defaults 5/21/5) e monta a linha do crontab a partir deles — nada fica fixo no código. Ele só **adiciona** essa linha — não remove nem altera nada que já exista, e roda de novo sem duplicar (pula linhas já presentes).

**Atenção:** se você já rodou este projeto antes nesse PC (crontab antigo com horários fixos, ou no formato anterior `30 5,10,15,20 * * *`), remova essas entradas antigas manualmente com `crontab -e` antes de rodar o script, para não acabar com execuções duplicadas.

## Ver logs

```bash
tail -f claude-cron.log
```

`claude-cron.log` contém só as linhas operacionais do script (`sessão iniciada`, `sessão já ativa`, `ERRO: ...`) — a resposta do Claude à pergunta `"que dia é hoje?"` é descartada, não polui o log. Quando o log passa de `LOG_MAX_BYTES` (default 1MB), o script rotaciona automaticamente para `claude-cron.log.1` (um único backup, sobrescrito a cada rotação).

Se a chamada ao Claude falhar (auth, rede, etc.), o script loga `ERRO: chamada ao claude falhou, marker não atualizado` e sai com status 1 — o marker não é atualizado, então a próxima execução tenta de novo.
