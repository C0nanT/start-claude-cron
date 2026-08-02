#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ASK_CLAUDE="$PROJECT_DIR/ask-claude.sh"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

MARKER_FILE="$PROJECT_DIR/.session-marker"
FAKE_CLAUDE="$WORK_DIR/fake-claude"
FAKE_ACTIVITY="$WORK_DIR/history.jsonl"

cat > "$FAKE_CLAUDE" <<'EOF'
#!/usr/bin/env bash
echo "fake claude called"
EOF
chmod +x "$FAKE_CLAUDE"

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

run_ask_claude() {
  CLAUDE_BIN="$FAKE_CLAUDE" CLAUDE_ACTIVITY_FILE="$FAKE_ACTIVITY" "$@" "$ASK_CLAUDE"
}

echo "=== 1) sem marker, sem activity file -> deve chamar o claude ==="
rm -f "$MARKER_FILE" "$FAKE_ACTIVITY"
output="$(run_ask_claude)"
assert_contains "$output" "sessão iniciada (script), expira às" "chama claude quando não há marker nem atividade"
if [ -f "$MARKER_FILE" ]; then
  echo "PASS: marker foi criado"
  read -r m_start m_origin < "$MARKER_FILE"
  assert_eq "$m_origin" "script" "marker gravado com origem script"
else
  echo "FAIL: marker não foi criado"
  failures=$((failures + 1))
fi

echo
echo "=== 2) marker (script) ainda dentro da janela -> pula e NÃO desliza o início ==="
marker_epoch="$(date -d '60 minutes ago' +%s)"
printf '%s script\n' "$marker_epoch" > "$MARKER_FILE"
touch -d '1 minute ago' "$FAKE_ACTIVITY"
output="$(run_ask_claude)"
assert_contains "$output" "sessão ativa (script), expira às" "pula e loga origem + horário de expiração"
read -r m_start_after _ < "$MARKER_FILE"
assert_eq "$m_start_after" "$marker_epoch" "início da janela permanece fixo (não desliza com atividade nova)"

echo
echo "=== 3) marker expirado, atividade do usuário recente -> adota início do usuário ==="
printf '%s script\n' "$(date -d '400 minutes ago' +%s)" > "$MARKER_FILE"
touch -d '10 minutes ago' "$FAKE_ACTIVITY"
expected_epoch="$(stat -c %Y "$FAKE_ACTIVITY" 2>/dev/null || stat -f %m "$FAKE_ACTIVITY")"
output="$(run_ask_claude)"
assert_contains "$output" "sessão do usuário detectada, expira às" "pula e loga origem usuário"
read -r m_start_after m_origin_after < "$MARKER_FILE"
assert_eq "$m_start_after" "$expected_epoch" "marker adota epoch da atividade do usuário"
assert_eq "$m_origin_after" "usuário" "marker registra origem usuário"

echo
echo "=== 4) marker e atividade fora da janela -> deve chamar o claude de novo ==="
printf '%s script\n' "$(date -d '400 minutes ago' +%s)" > "$MARKER_FILE"
touch -d '400 minutes ago' "$FAKE_ACTIVITY"
output="$(run_ask_claude)"
assert_contains "$output" "sessão iniciada (script), expira às" "chama claude de novo quando ambos os sinais expiraram"

echo
echo "=== 5) feature flag desativada, marker recente -> deve chamar o claude mesmo assim ==="
printf '%s script\n' "$(date -d '5 minutes ago' +%s)" > "$MARKER_FILE"
output="$(run_ask_claude env ENABLE_SESSION_SKIP=false)"
assert_contains "$output" "sessão iniciada (script), expira às" "ENABLE_SESSION_SKIP=false ignora o marker"

echo
echo "=== 6) claude falha -> loga erro, sai 1, não atualiza marker ==="
rm -f "$MARKER_FILE"
FAILING_CLAUDE="$WORK_DIR/failing-claude"
cat > "$FAILING_CLAUDE" <<'EOF'
#!/usr/bin/env bash
echo "resposta que nao deveria vazar pro log" >&2
exit 1
EOF
chmod +x "$FAILING_CLAUDE"
set +e
output="$(CLAUDE_BIN="$FAILING_CLAUDE" CLAUDE_ACTIVITY_FILE="$FAKE_ACTIVITY" "$ASK_CLAUDE" 2>&1)"
exit_code=$?
set -e
assert_eq "$exit_code" "1" "sai com status 1 quando claude falha"
assert_contains "$output" "ERRO: chamada ao claude falhou" "loga erro explícito"
if [ -f "$MARKER_FILE" ]; then
  echo "FAIL: marker não deveria ter sido criado após falha"
  failures=$((failures + 1))
else
  echo "PASS: marker não foi criado após falha"
fi

echo
echo "=== 7) resposta do claude não vaza pro stdout do script ==="
rm -f "$MARKER_FILE" "$FAKE_ACTIVITY"
output="$(run_ask_claude)"
if [[ "$output" == *"fake claude called"* ]]; then
  echo "FAIL: resposta do claude vazou pro log"
  failures=$((failures + 1))
else
  echo "PASS: resposta do claude não aparece no log"
fi

rm -f "$MARKER_FILE"

echo
if [ "$failures" -gt 0 ]; then
  echo "$failures teste(s) falharam"
  exit 1
fi
echo "Todos os testes de ask-claude.sh passaram"
