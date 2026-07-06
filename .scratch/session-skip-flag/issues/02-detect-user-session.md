Status: ready

## What to build

O marker da issue 01-script-marker-skip.md só sabe se o **script** iniciou uma sessão recentemente. Se o usuário usar o Claude Code manualmente (fora do cron), o script não tem como saber e vai chamar o Claude de novo sem necessidade, gastando tokens à toa.

Estender a checagem de skip para também considerar atividade recente do próprio Claude Code, não só do marker do script:

- Verificar um sinal de atividade recente do Claude Code (ex: mtime de `~/.claude/history.jsonl`, ou o arquivo de sessão mais recente em `~/.claude/projects/**`).
- Se esse sinal for mais recente que o marker do script e estiver dentro da janela configurada, tratar como "sessão ativa (usuário)": logar o motivo e pular a chamada ao Claude.
- Atualizar o marker do script para refletir esse horário detectado, para que execuções seguintes do cron não precisem repetir a checagem de atividade do usuário até a janela expirar.

## Acceptance criteria

- [ ] Script verifica atividade recente do Claude Code (fonte de sinal a definir na implementação, ex: mtime de `~/.claude/history.jsonl`)
- [ ] Se a atividade do usuário for mais recente que o marker do script e estiver dentro da janela, pula a chamada e loga "sessão ativa (usuário) às HH:MM"
- [ ] Marker do script é atualizado com o horário detectado da sessão do usuário
- [ ] Comportamento respeita a mesma feature flag (`ENABLE_SESSION_SKIP`) da issue 01

## Blocked by

- 01-script-marker-skip.md
