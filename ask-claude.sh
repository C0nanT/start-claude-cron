#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
[ -f "$SCRIPT_DIR/.env" ] && set -a && . "$SCRIPT_DIR/.env" && set +a

CLAUDE_BIN="${CLAUDE_BIN:-$HOME/.local/bin/claude}"
CLAUDE_MODEL="${CLAUDE_MODEL:-claude-haiku-4-5-20251001}"
SESSION_WINDOW_MINUTES="${SESSION_WINDOW_MINUTES:-300}"
# Folga pra fechar a sessão: o cron dispara em :30:01 e a sessão anterior
# começou em :30:06, então sem folga ela ainda "estaria ativa" por 5s.
SESSION_GRACE_SECONDS="${SESSION_GRACE_SECONDS:-120}"
DB_FILE="${DB_FILE:-$SCRIPT_DIR/sessions.db}"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

fmt_hm() {
  date -d "@$1" '+%H:%M' 2>/dev/null || date -r "$1" '+%H:%M'
}

# Fim da última sessão registrada (0 se não houver nenhuma).
db_last_end() {
  python3 - "$DB_FILE" <<'PY'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
c.execute("""CREATE TABLE IF NOT EXISTS sessions(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  start_epoch INTEGER NOT NULL,
  end_epoch INTEGER NOT NULL)""")
c.commit()
row = c.execute("SELECT end_epoch FROM sessions ORDER BY end_epoch DESC LIMIT 1").fetchone()
print(row[0] if row else 0)
PY
}

db_insert() {
  python3 - "$DB_FILE" "$1" "$2" <<'PY'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
c.execute("INSERT INTO sessions(start_epoch, end_epoch) VALUES (?, ?)",
          (int(sys.argv[2]), int(sys.argv[3])))
c.commit()
PY
}

window_sec=$(( SESSION_WINDOW_MINUTES * 60 ))
now="$(date +%s)"
last_end="$(db_last_end)"

# Sessão anterior ainda rodando: sai sem chamar o claude (não gasta token).
# O próximo tick do cron tenta de novo.
if [ "$now" -lt $(( last_end - SESSION_GRACE_SECONDS )) ]; then
  log "sessão ativa até $(fmt_hm "$last_end") (faltam $(( (last_end - now) / 60 ))min), pulando"
  exit 0
fi

if ! "$CLAUDE_BIN" --model "$CLAUDE_MODEL" --effort low --print "que dia é hoje?" > /dev/null; then
  log "ERRO: chamada ao claude falhou, sessão não registrada"
  exit 1
fi

start_epoch="$(date +%s)"
end_epoch=$(( start_epoch + window_sec ))
db_insert "$start_epoch" "$end_epoch"
log "sessão iniciada às $(fmt_hm "$start_epoch"), expira às $(fmt_hm "$end_epoch")"
