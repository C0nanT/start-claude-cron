#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
INSTALL_CRON="$PROJECT_DIR/install-cron.sh"
ASK_CLAUDE="$PROJECT_DIR/ask-claude.sh"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

FAKE_STORE="$WORK_DIR/crontab-store"
touch "$FAKE_STORE"

cat > "$WORK_DIR/crontab" <<EOF
#!/usr/bin/env bash
STORE="$FAKE_STORE"
if [ "\$1" = "-l" ]; then
  cat "\$STORE"
  exit 0
elif [ "\$1" = "-" ]; then
  cat > "\$STORE"
  exit 0
fi
EOF
chmod +x "$WORK_DIR/crontab"

LINE_NEW="30 5,10,15,20 * * * $ASK_CLAUDE >> $PROJECT_DIR/claude-cron.log 2>&1"
LINE_CUSTOM="15 6,12,18 * * * $ASK_CLAUDE >> $PROJECT_DIR/claude-cron.log 2>&1"

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

assert_not_contains() {
  local haystack="$1" needle="$2" desc="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    echo "FAIL: $desc (não deveria conter: $needle)"
    failures=$((failures + 1))
  else
    echo "PASS: $desc"
  fi
}

assert_count() {
  local haystack="$1" needle="$2" expected_count="$3" desc="$4"
  local actual_count
  actual_count="$(grep -Fc "$needle" <<< "$haystack" || true)"
  if [ "$actual_count" != "$expected_count" ]; then
    echo "FAIL: $desc (esperado $expected_count ocorrência(s), achou $actual_count)"
    failures=$((failures + 1))
  else
    echo "PASS: $desc"
  fi
}

run_install() {
  PATH="$WORK_DIR:$PATH" "$@" "$INSTALL_CRON"
}

echo "=== 1) crontab vazio -> deve adicionar a linha nova ==="
: > "$FAKE_STORE"
run_install > /dev/null
result="$(cat "$FAKE_STORE")"
assert_contains "$result" "$LINE_NEW" "linha nova (30 5,10,15,20h, default) adicionada"

echo
echo "=== 2) roda de novo -> não deve duplicar ==="
run_install > /dev/null
result="$(cat "$FAKE_STORE")"
assert_count "$result" "$LINE_NEW" "1" "linha nova aparece só 1 vez"

echo
echo "=== 3) crontab com entradas antigas do projeto + job não relacionado -> preserva tudo, só adiciona as novas ==="
OLD_LINE_1="0 8 * * * $ASK_CLAUDE >> $PROJECT_DIR/claude-cron.log 2>&1"
UNRELATED_LINE="0 5 * * * /usr/bin/some-other-job.sh"
printf '%s\n%s\n' "$OLD_LINE_1" "$UNRELATED_LINE" > "$FAKE_STORE"
run_install > /dev/null
result="$(cat "$FAKE_STORE")"
assert_contains "$result" "$OLD_LINE_1" "entrada antiga do projeto permanece intacta"
assert_contains "$result" "$UNRELATED_LINE" "job não relacionado permanece intacto"
assert_contains "$result" "$LINE_NEW" "linha nova foi adicionada"

echo
echo "=== 4) CRON_START_HOUR/CRON_START_MINUTE/CRON_END_HOUR/SESSION_WINDOW_MINUTES customizados via env -> gera ticks customizados ==="
: > "$FAKE_STORE"
run_install env CRON_START_HOUR=6 CRON_START_MINUTE=15 CRON_END_HOUR=20 SESSION_WINDOW_MINUTES=360 > /dev/null
result="$(cat "$FAKE_STORE")"
assert_contains "$result" "$LINE_CUSTOM" "linha respeita CRON_START_HOUR/CRON_START_MINUTE/CRON_END_HOUR/SESSION_WINDOW_MINUTES (passo de 6h)"

echo
echo "=== 5) SESSION_WINDOW_MINUTES não múltiplo de 60 -> erro, não instala nada ==="
: > "$FAKE_STORE"
set +e
error_output="$(run_install env SESSION_WINDOW_MINUTES=90 2>&1)"
exit_code=$?
set -e
assert_eq_code() {
  if [ "$1" != "$2" ]; then
    echo "FAIL: esperava exit code $2, achou $1"
    failures=$((failures + 1))
  else
    echo "PASS: sai com erro (exit $2) quando SESSION_WINDOW_MINUTES não é múltiplo de 60"
  fi
}
assert_eq_code "$exit_code" "1"
assert_contains "$error_output" "múltiplo de 60" "mensagem de erro explica a causa"

echo
if [ "$failures" -gt 0 ]; then
  echo "$failures teste(s) falharam"
  exit 1
fi
echo "Todos os testes de install-cron.sh passaram"
