Status: ready

## What to build

Hoje o `ask-claude.sh` roda o Claude 100% das vezes que é chamado, mesmo se já existir uma sessão ativa dentro da janela de 5h — o que desperdiça tokens quando o script passa a rodar com frequência maior (a cada 10min).

Adicionar um mecanismo de marker/feature-flag no próprio script:

- Após uma chamada bem-sucedida ao Claude, gravar o timestamp (epoch) atual em um arquivo marker local (ex: `.session-marker`, ignorado pelo git).
- No início da execução, ler o marker: se existir e estiver dentro da janela configurada (default 5h), logar o motivo ("sessão já ativa, iniciada pelo script às HH:MM") e sair sem chamar o Claude.
- A janela deve ser configurável via env var (ex: `SESSION_WINDOW_MINUTES`, default 300).
- Adicionar uma feature flag via env var (ex: `ENABLE_SESSION_SKIP`, default true) que permite desativar esse comportamento e voltar ao modo antigo (sempre chama o Claude) — útil para debug/rollback sem precisar reverter código.

## Acceptance criteria

- [ ] Script grava marker com timestamp epoch após chamada bem-sucedida ao Claude
- [ ] Script lê o marker no início; se dentro da janela, pula a chamada, loga o motivo e sai com código 0
- [ ] Janela configurável via env var, com default de 5h10 (310min)
- [ ] Feature flag (`ENABLE_SESSION_SKIP`) desativa o skip e restaura o comportamento atual (sempre chama)
- [ ] Marker file vive no diretório do projeto e está no `.gitignore`
- [ ] `.env.example` documenta as novas variáveis

## Blocked by

None - can start immediately
