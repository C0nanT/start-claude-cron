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
FAKE_SLEEP="$WORK_DIR/sleep"

cat > "$FAKE_CLAUDE" <<'EOF'
#!/usr/bin/env bash
echo "fake claude called"
EOF
chmod +x "$FAKE_CLAUDE"

# sleep instantâneo -> testa o loop de retries sem esperar minutos de verdade
cat > "$FAKE_SLEEP" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$FAKE_SLEEP"

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

run_ask_claude() {
  PATH="$WORK_DIR:$PATH" CLAUDE_BIN="$FAKE_CLAUDE" CLAUDE_ACTIVITY_FILE="$FAKE_ACTIVITY" "$@" "$ASK_CLAUDE"
}

echo "=== 1) sem marker, sem activity file -> deve chamar o claude na 1a tentativa ==="
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
echo "=== 2) marker (script) ainda dentro da janela, MAX_RETRIES=1 -> desiste na 1a tentativa e NÃO desliza o início ==="
marker_epoch="$(date -d '60 minutes ago' +%s)"
printf '%s script\n' "$marker_epoch" > "$MARKER_FILE"
touch -d '1 minute ago' "$FAKE_ACTIVITY"
output="$(run_ask_claude env MAX_RETRIES=1)"
assert_contains "$output" "sessão ativa (script), expira às" "loga origem + horário de expiração"
assert_contains "$output" "sessão ainda ativa após 1 tentativa(s), desistindo até o próximo ciclo do cron" "desiste após esgotar tentativas"
read -r m_start_after _ < "$MARKER_FILE"
assert_eq "$m_start_after" "$marker_epoch" "início da janela permanece fixo (não desliza com atividade nova)"

echo
echo "=== 3) marker expirado, atividade do usuário recente, MAX_RETRIES=1 -> adota início do usuário ==="
printf '%s script\n' "$(date -d '400 minutes ago' +%s)" > "$MARKER_FILE"
touch -d '10 minutes ago' "$FAKE_ACTIVITY"
expected_epoch="$(stat -c %Y "$FAKE_ACTIVITY" 2>/dev/null || stat -f %m "$FAKE_ACTIVITY")"
output="$(run_ask_claude env MAX_RETRIES=1)"
assert_contains "$output" "sessão do usuário detectada, expira às" "loga origem usuário"
read -r m_start_after m_origin_after < "$MARKER_FILE"
assert_eq "$m_start_after" "$expected_epoch" "marker adota epoch da atividade do usuário"
assert_eq "$m_origin_after" "usuário" "marker registra origem usuário"

echo
echo "=== 4) marker e atividade fora da janela -> chama o claude de novo já na 1a tentativa ==="
printf '%s script\n' "$(date -d '400 minutes ago' +%s)" > "$MARKER_FILE"
touch -d '400 minutes ago' "$FAKE_ACTIVITY"
output="$(run_ask_claude)"
assert_contains "$output" "sessão iniciada (script), expira às" "chama claude de novo quando ambos os sinais expiraram"

echo
echo "=== 5) feature flag desativada, marker recente -> chama o claude direto, sem passar pelo retry loop ==="
printf '%s script\n' "$(date -d '5 minutes ago' +%s)" > "$MARKER_FILE"
output="$(run_ask_claude env ENABLE_SESSION_SKIP=false)"
assert_contains "$output" "sessão iniciada (script), expira às" "ENABLE_SESSION_SKIP=false ignora o marker"
if [[ "$output" == *"tentativa"* ]]; then
  echo "FAIL: não deveria ter entrado no loop de retries"
  failures=$((failures + 1))
else
  echo "PASS: pulou o retry loop"
fi

echo
echo "=== 6) claude falha -> loga erro, sai 1, não atualiza marker (sem retry, não é caso de sessão ativa) ==="
rm -f "$MARKER_FILE" "$FAKE_ACTIVITY"
FAILING_CLAUDE="$WORK_DIR/failing-claude"
cat > "$FAILING_CLAUDE" <<'EOF'
#!/usr/bin/env bash
echo "resposta que nao deveria vazar pro log" >&2
exit 1
EOF
chmod +x "$FAILING_CLAUDE"
set +e
output="$(PATH="$WORK_DIR:$PATH" CLAUDE_BIN="$FAILING_CLAUDE" CLAUDE_ACTIVITY_FILE="$FAKE_ACTIVITY" "$ASK_CLAUDE" 2>&1)"
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

echo
echo "=== 8) sessão ativa o tempo todo, MAX_RETRIES=3 -> tenta 3x (5min de intervalo, sleep mockado) e desiste sem nunca chamar o claude ==="
marker_epoch="$(date -d '1 minute ago' +%s)"
printf '%s script\n' "$marker_epoch" > "$MARKER_FILE"
rm -f "$FAKE_ACTIVITY"
output="$(run_ask_claude env MAX_RETRIES=3 SESSION_WINDOW_MINUTES=300 RETRY_INTERVAL_MINUTES=5)"
assert_count "$output" "tentativa 1/3 sem sucesso, tentando de novo em 5min" "1" "loga tentativa 1/3"
assert_count "$output" "tentativa 2/3 sem sucesso, tentando de novo em 5min" "1" "loga tentativa 2/3"
assert_contains "$output" "sessão ainda ativa após 3 tentativa(s), desistindo até o próximo ciclo do cron" "desiste após a 3a tentativa"
if [[ "$output" == *"fake claude called"* ]]; then
  echo "FAIL: claude não deveria ter sido chamado (sessão sempre ativa)"
  failures=$((failures + 1))
else
  echo "PASS: claude não foi chamado durante os retries"
fi
read -r m_start_after _ < "$MARKER_FILE"
assert_eq "$m_start_after" "$marker_epoch" "marker permanece com o início original após desistir"

rm -f "$MARKER_FILE"

echo
if [ "$failures" -gt 0 ]; then
  echo "$failures teste(s) falharam"
  exit 1
fi
echo "Todos os testes de ask-claude.sh passaram"
