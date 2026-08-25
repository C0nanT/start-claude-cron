# start-claude-cron

Script + cron para controlar o horário de reset do limite diário do Claude Code.

## Contexto

O Claude Code possui um limite de uso de 5 horas por janela. Esse limite reseta com base no horário da **primeira mensagem enviada** na sessão — não à meia-noite. Ou seja: se você mandar a primeira mensagem às 10h, o limite reseta às 15h do mesmo dia.

O objetivo desse script é **fixar o horário de reset** disparando uma mensagem leve (modelo Haiku, effort mínimo) em horários estratégicos, garantindo que o contador sempre inicie no mesmo ponto do dia.

## Horários

Ticks base (início de cada janela de 5h): **05:30, 10:30, 15:30, 20:30**.

Como a janela real pode terminar alguns minutos depois do tick (ex.: sessão iniciada às 05:32 só acaba às 10:32), cada tick tem retentativas com intervalos de **10, 10, 5, 5, 10, 10 minutos**:

```
05:30  05:40  05:50  05:55  06:00  06:10  06:20
10:30  10:40  10:50  10:55  11:00  11:10  11:20
15:30  15:40  15:50  15:55  16:00  16:10  16:20
20:30  20:40  20:50  20:55  21:00  21:10  21:20
```

Se nenhuma das tentativas conseguir abrir a sessão, desiste até o próximo tick base.

## Como funciona

O cron **sempre** dispara nos horários acima. Quem decide se vale chamar o Claude é o script:

1. Consulta o sqlite (`sessions.db`) pelo `end_epoch` da última sessão registrada.
2. Se essa sessão ainda está dentro da janela, loga `sessão ativa até HH:MM (faltam Xmin), pulando` e **sai sem chamar o Claude** — retentativa não gasta token.
3. Se já acabou (ou não existe sessão), chama o Claude, grava `start_epoch`/`end_epoch` no sqlite e loga `sessão iniciada às HH:MM, expira às HH:MM`.

A chamada usa `--print` (não-interativo), modelo `claude-haiku-4-5-20251001`, `--effort low` e a pergunta `"que dia é hoje?"` — o mínimo pra abrir a sessão. A resposta é descartada.

`SESSION_GRACE_SECONDS` (default 120) trata a sessão como encerrada um pouco antes do fim exato, porque o cron dispara em `:30:01` enquanto a sessão anterior começou em `:30:06` — sem essa folga o tick base sempre perderia a janela por poucos segundos.

## Arquivos

```
ask-claude.sh       # Script principal
install-cron.sh     # Instala as linhas do crontab
sessions.db         # Histórico de sessões em sqlite (gerado automaticamente, git-ignored)
claude-cron.log     # Output das execuções (gerado automaticamente, git-ignored)
```

## Esquema do sqlite

```sql
CREATE TABLE sessions(
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  start_epoch INTEGER NOT NULL,
  end_epoch   INTEGER NOT NULL
);
```

Consultar o histórico:

```bash
python3 -c "import sqlite3,datetime as d; [print(d.datetime.fromtimestamp(s), '->', d.datetime.fromtimestamp(e)) for s,e in sqlite3.connect('sessions.db').execute('SELECT start_epoch,end_epoch FROM sessions ORDER BY id')]"
```

## Cron jobs

```
30,40,50,55 5,10,15,20 * * * /path/to/ask-claude.sh >> claude-cron.log 2>&1
0,10,20     6,11,16,21 * * * /path/to/ask-claude.sh >> claude-cron.log 2>&1
```

Timezone do sistema: `America/Sao_Paulo` — sem conversão UTC necessária.

### Instalando em um PC novo

```bash
./install-cron.sh
```

Remove qualquer entrada antiga de `ask-claude.sh` no crontab e instala as duas linhas acima. Entradas não relacionadas são preservadas, e rodar de novo não duplica nada.

## Configuração

Copie `.env.example` para `.env` e ajuste o que precisar (`CLAUDE_BIN`, `CLAUDE_MODEL`, `SESSION_WINDOW_MINUTES`, `SESSION_GRACE_SECONDS`, `DB_FILE`).

## Ver logs

```bash
tail -f claude-cron.log
```

Se a chamada ao Claude falhar (auth, rede, etc.), o script loga `ERRO: chamada ao claude falhou, sessão não registrada` e sai com status 1 — nada é gravado no sqlite, então a próxima tentativa repete.
