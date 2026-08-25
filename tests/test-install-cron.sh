#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
INSTALL_CRON="$PROJECT_DIR/install-cron.sh"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

CRONTAB_STATE="$WORK_DIR/crontab.txt"
FAKE_BIN="$WORK_DIR/bin"
mkdir -p "$FAKE_BIN"

# crontab falso: -l lê o arquivo de estado, sem args grava o stdin nele
cat > "$FAKE_BIN/crontab" <<EOF
#!/usr/bin/env bash
if [ "\${1:-}" = "-l" ]; then
  [ -s "$CRONTAB_STATE" ] || exit 1
  cat "$CRONTAB_STATE"
else
  cat > "$CRONTAB_STATE"
fi
EOF
chmod +x "$FAKE_BIN/crontab"

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
    echo "FAIL: $desc (não deveria conter '$needle')"
    failures=$((failures + 1))
  else
    echo "PASS: $desc"
  fi
}

run_install() {
  PATH="$FAKE_BIN:$PATH" bash "$INSTALL_CRON" 2>&1
}

echo "== crontab vazio =="
: > "$CRONTAB_STATE"
run_install > /dev/null
result="$(cat "$CRONTAB_STATE")"
assert_contains "$result" "30,40,50,55 5,10,15,20 * * * $PROJECT_DIR/ask-claude.sh" "linha dos ticks base + retries da mesma hora"
assert_contains "$result" "0,10,20 6,11,16,21 * * * $PROJECT_DIR/ask-claude.sh" "linha dos retries que caem na hora seguinte"

echo
echo "== preserva entradas de terceiros e substitui as antigas do projeto =="
{
  echo "0 3 * * * /outro/script.sh"
  echo "*/5 5-21 * * * $PROJECT_DIR/ask-claude.sh >> /tmp/velho.log 2>&1"
} > "$CRONTAB_STATE"
run_install > /dev/null
result="$(cat "$CRONTAB_STATE")"
assert_contains "$result" "0 3 * * * /outro/script.sh" "mantém entrada não relacionada"
assert_not_contains "$result" "*/5 5-21" "removeu a entrada antiga do projeto"
assert_contains "$result" "30,40,50,55 5,10,15,20" "instalou o novo agendamento"

echo
echo "== rodar duas vezes não duplica =="
run_install > /dev/null
count="$(grep -c "ask-claude.sh" "$CRONTAB_STATE")"
if [ "$count" != "2" ]; then
  echo "FAIL: esperava 2 linhas do projeto, achei $count"
  failures=$((failures + 1))
else
  echo "PASS: idempotente (2 linhas)"
fi

echo
if [ "$failures" -gt 0 ]; then
  echo "$failures teste(s) falharam"
  exit 1
fi
echo "todos os testes passaram"
