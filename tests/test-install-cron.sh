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
  PATH="$WORK_DIR:$PATH" "$INSTALL_CRON"
}

echo "=== 1) crontab vazio -> deve adicionar a linha nova ==="
: > "$FAKE_STORE"
run_install > /dev/null
result="$(cat "$FAKE_STORE")"
assert_contains "$result" "$LINE_NEW" "linha nova (5,10,15,20h30) adicionada"

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
if [ "$failures" -gt 0 ]; then
  echo "$failures teste(s) falharam"
  exit 1
fi
echo "Todos os testes de install-cron.sh passaram"
