#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ASK_CLAUDE="$PROJECT_DIR/ask-claude.sh"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

FAKE_CLAUDE="$WORK_DIR/fake-claude"
CALL_LOG="$WORK_DIR/calls.txt"
DB_FILE="$WORK_DIR/sessions.db"

cat > "$FAKE_CLAUDE" <<EOF
#!/usr/bin/env bash
echo "\$@" >> "$CALL_LOG"
EOF
chmod +x "$FAKE_CLAUDE"

FAILING_CLAUDE="$WORK_DIR/failing-claude"
cat > "$FAILING_CLAUDE" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$FAILING_CLAUDE"

failures=0

assert_contains() {
  local haystack="$1" needle="$2" desc="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "FAIL: $desc"
    echo "  expected to contain: $needle"
    echo "  got: $haystack"
    failures=$((failures + 1))
  else
    echo "PASS: $desc"
  fi
}

assert_eq() {
  local actual="$1" expected="$2" desc="$3"
  if [ "$actual" != "$expected" ]; then
    echo "FAIL: $desc (expected '$expected', got '$actual')"
    failures=$((failures + 1))
  else
    echo "PASS: $desc"
  fi
}

run_script() {
  CLAUDE_BIN="$FAKE_CLAUDE" DB_FILE="$DB_FILE" "$@" bash "$ASK_CLAUDE" 2>&1
}

seed_session() {
  python3 - "$DB_FILE" "$1" "$2" <<'PY'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
c.execute("""CREATE TABLE IF NOT EXISTS sessions(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  start_epoch INTEGER NOT NULL,
  end_epoch INTEGER NOT NULL)""")
c.execute("INSERT INTO sessions(start_epoch, end_epoch) VALUES (?, ?)",
          (int(sys.argv[2]), int(sys.argv[3])))
c.commit()
PY
}

count_rows() {
  python3 - "$DB_FILE" <<'PY'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
print(c.execute("SELECT COUNT(*) FROM sessions").fetchone()[0])
PY
}

echo "== sem sessão no banco: inicia e registra =="
out="$(run_script)"
assert_contains "$out" "sessão iniciada" "loga início da sessão"
assert_eq "$(wc -l < "$CALL_LOG")" "1" "chamou o claude uma vez"
assert_contains "$(cat "$CALL_LOG")" "claude-haiku-4-5-20251001" "usou o modelo haiku"
assert_eq "$(count_rows)" "1" "gravou 1 sessão no sqlite"

echo
echo "== sessão ainda ativa: pula sem gastar token =="
out="$(run_script)"
assert_contains "$out" "pulando" "loga que pulou"
assert_eq "$(wc -l < "$CALL_LOG")" "1" "não chamou o claude de novo"
assert_eq "$(count_rows)" "1" "não gravou sessão nova"

echo
echo "== sessão expirada: inicia de novo =="
rm -f "$DB_FILE" "$CALL_LOG"
now="$(date +%s)"
seed_session $(( now - 20000 )) $(( now - 100 ))
out="$(run_script)"
assert_contains "$out" "sessão iniciada" "reinicia após expirar"
assert_eq "$(count_rows)" "2" "gravou a nova sessão"

echo
echo "== fim da janela dentro da folga: trata como expirada =="
rm -f "$DB_FILE" "$CALL_LOG"
now="$(date +%s)"
seed_session $(( now - 18000 )) $(( now + 5 ))
out="$(run_script)"
assert_contains "$out" "sessão iniciada" "SESSION_GRACE_SECONDS cobre o atraso de segundos do cron"

echo
echo "== claude falhando: não registra sessão =="
rm -f "$DB_FILE"
out="$(CLAUDE_BIN="$FAILING_CLAUDE" DB_FILE="$DB_FILE" bash "$ASK_CLAUDE" 2>&1 || true)"
assert_contains "$out" "ERRO" "loga erro"
assert_eq "$(count_rows)" "0" "nenhuma sessão gravada"

echo
if [ "$failures" -gt 0 ]; then
  echo "$failures teste(s) falharam"
  exit 1
fi
echo "todos os testes passaram"
