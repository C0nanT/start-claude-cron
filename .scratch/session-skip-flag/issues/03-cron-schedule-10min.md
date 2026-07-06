Status: ready

## What to build

O crontab atual dispara `ask-claude.sh` em horários fixos (08:00, 23:00, 23:30), o que exige acertar exatamente o horário da primeira mensagem do dia/madrugada. Com o script agora seguro para rodar com frequência (issues 01 e 02), trocar por tentativas repetidas de 10 em 10 minutos em duas janelas: a partir das 08:00 e a partir das 23:00, 6 tentativas cada.

- Substituir os 3 jobs fixos por 12 entradas de crontab: `08:00, 08:10, 08:20, 08:30, 08:40, 08:50` e `23:00, 23:10, 23:20, 23:30, 23:40, 23:50`.
- Pode ser expresso como duas linhas usando lista de minutos (`0,10,20,30,40,50 8 * * *` e `0,10,20,30,40,50 23 * * *`) ou 12 linhas explícitas — documentar a escolha no README.
- Atualizar o README: tabela de horários, explicação do porquê da repetição a cada 10min (tentar pegar a primeira sessão do dia sem precisar de horário exato) e descrição do mecanismo de skip (marker + feature flag) das issues 01/02.

## Acceptance criteria

- [ ] Crontab atualizado com as 12 tentativas (6 a partir de 08:00, 6 a partir de 23:00, de 10 em 10min)
- [ ] README atualizado com a nova tabela/agenda de horários e a razão da mudança
- [ ] README documenta o comportamento de skip (marker de sessão + feature flag `ENABLE_SESSION_SKIP`)

## Blocked by

- 01-script-marker-skip.md
