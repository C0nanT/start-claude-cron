# start-claude-cron

Script + cron para controlar o horário de reset do limite diário do Claude Code.

## Contexto

O Claude Code possui um limite de uso de 5 horas por janela. Esse limite reseta com base no horário da **primeira mensagem enviada** na sessão — não à meia-noite. Ou seja: se você mandar a primeira mensagem às 10h, o limite reseta às 15h do mesmo dia.

O objetivo desse script é **fixar o horário de reset** disparando uma mensagem leve (modelo Haiku, effort mínimo) em horários estratégicos, garantindo que o contador sempre inicie no mesmo ponto do dia.

## Horários configurados

O cron dispara em ticks fixos, espaçados pela duração da janela (`SESSION_WINDOW_MINUTES`, default 300min = 5h), começando em `CRON_START_HOUR:CRON_START_MINUTE` e sem passar de `CRON_END_HOUR`. Com os defaults (5h30, passo de 5h, até 21h): **05:30, 10:30, 15:30, 20:30**. Fora dessa faixa (madrugada) não roda — intencional. Tudo configurável via `.env` (veja `.env.example`); nada fica hardcoded no código.

Cada tick tenta iniciar a sessão. Se já houver uma ativa, o **próprio script** (não o cron) fica tentando de novo a cada `RETRY_INTERVAL_MINUTES` (default 5min), até `MAX_RETRIES` tentativas (default 12, cobrindo ~55min) — pensado pro caso de a sessão ativa estar quase no fim: em vez de perder essa janela e só tentar de novo daqui 5h (próximo tick), o script insiste por perto de 1h antes de desistir e devolver o controle pro próximo tick.

Isso significa que uma execução do cron pode ficar rodando (dormindo) por até ~55min quando pega uma sessão ativa que não termina a tempo — inofensivo, já que o próximo tick real só vem 5h depois.

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

## Skip de sessão ativa + retry

`.session-marker` guarda o **início fixo** da janela atual de 5h, no formato `<epoch> <origem>` (origem = `script` ou `usuário`). É fixo — não é reescrito a cada checagem — porque se ele deslizasse pra frente toda vez que houvesse atividade nova, o fim da janela nunca chegaria enquanto o uso continuasse, e a janela de 5h real do Claude Code (que conta a partir da primeira mensagem, não da última) sairia de sincronia sem o script perceber.

Em cada tentativa (a 1ª do tick, ou uma das retries):

1. Se o marker existe e ainda está dentro da janela (`SESSION_WINDOW_MINUTES`, default 300min): loga a origem e o horário de expiração (`sessão ativa (origem), expira às HH:MM (faltam Xmin)`), **sem alterar o marker** — sessão considerada ativa.
2. Senão, verifica `CLAUDE_ACTIVITY_FILE` (mtime, default `~/.claude/history.jsonl`). Se essa atividade ainda está dentro da janela, o script conclui que o usuário já iniciou uma sessão nova por conta própria, adota esse horário como início (`sessão do usuário detectada, expira às HH:MM`) e grava o marker — aproximação sujeita a alguns minutos de erro, já que só sabemos a **última** mensagem vista, não a primeira — sessão considerada ativa.
3. Se nenhum dos dois sinais está dentro da janela: chama o Claude de verdade, e o novo início (exato, porque foi o próprio script quem disparou) vira o marker. Fim da execução (sucesso).

Se o passo 3 não foi alcançado (sessão ainda ativa) e ainda restam tentativas (`MAX_RETRIES`, default 12), o script loga `tentativa N/MAX_RETRIES sem sucesso, tentando de novo em RETRY_INTERVAL_MINUTESmin`, dorme esse intervalo e repete do passo 1. Ao esgotar as tentativas, loga `sessão ainda ativa após N tentativa(s), desistindo até o próximo ciclo do cron` e sai — sem chamar o Claude.

Esse comportamento é controlado pela feature flag `ENABLE_SESSION_SKIP` (default `true`) — defina como `false` para sempre chamar o Claude direto, ignorando marker e retries. Veja `.env.example` para todas as variáveis.

## Cron jobs

```
30 5,10,15,20 * * *  /path/to/ask-claude.sh >> claude-cron.log 2>&1
```

Timezone do sistema: `America/Sao_Paulo` — sem conversão UTC necessária.

### Instalando em um PC novo

```bash
./install-cron.sh
```

O `install-cron.sh` lê `CRON_START_HOUR`/`CRON_START_MINUTE`/`CRON_END_HOUR`/`SESSION_WINDOW_MINUTES` do `.env` (ou usa os defaults 5/30/21/300) e monta a linha do crontab a partir deles — nada fica fixo no código. Ele só **adiciona** essa linha — não remove nem altera nada que já exista, e roda de novo sem duplicar (pula linhas já presentes). `SESSION_WINDOW_MINUTES` precisa ser múltiplo de 60 pra virar um passo de horas inteiras entre os ticks.

**Atenção:** se você já rodou este projeto antes nesse PC (crontab antigo com horários fixos, ou no formato `*/5 5-21 * * *` de uma versão anterior que rodava a cada 5min o dia todo), remova essas entradas antigas manualmente com `crontab -e` antes de rodar o script, para não acabar com execuções duplicadas.

## Ver logs

```bash
tail -f claude-cron.log
```

`claude-cron.log` contém só as linhas operacionais do script (`sessão iniciada`, `sessão já ativa`, `ERRO: ...`) — a resposta do Claude à pergunta `"que dia é hoje?"` é descartada, não polui o log. Quando o log passa de `LOG_MAX_BYTES` (default 1MB), o script rotaciona automaticamente para `claude-cron.log.1` (um único backup, sobrescrito a cada rotação).

Se a chamada ao Claude falhar (auth, rede, etc.), o script loga `ERRO: chamada ao claude falhou, marker não atualizado` e sai com status 1 — o marker não é atualizado, então a próxima execução tenta de novo.
