#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
[ -f "$SCRIPT_DIR/.env" ] && set -a && . "$SCRIPT_DIR/.env" && set +a

CLAUDE_BIN="${CLAUDE_BIN:-$HOME/.local/bin/claude}"
ENABLE_SESSION_SKIP="${ENABLE_SESSION_SKIP:-true}"
SESSION_WINDOW_MINUTES="${SESSION_WINDOW_MINUTES:-300}"
MARKER_FILE="$SCRIPT_DIR/.session-marker"
CLAUDE_ACTIVITY_FILE="${CLAUDE_ACTIVITY_FILE:-$HOME/.claude/history.jsonl}"
LOG_MAX_BYTES="${LOG_MAX_BYTES:-1048576}"
LOG_FILE="$SCRIPT_DIR/claude-cron.log"
RETRY_INTERVAL_MINUTES="${RETRY_INTERVAL_MINUTES:-5}"
MAX_RETRIES="${MAX_RETRIES:-12}"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# stat/date portáteis: GNU (Linux/WSL) usa -c/-d, BSD/macOS usa -f/-r
get_mtime_epoch() {
  stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null
}

fmt_hm() {
  date -d "@$1" '+%H:%M' 2>/dev/null || date -r "$1" '+%H:%M'
}

get_activity_epoch() {
  [ -f "$CLAUDE_ACTIVITY_FILE" ] && get_mtime_epoch "$CLAUDE_ACTIVITY_FILE" || echo 0
}

rotate_log_if_needed() {
  [ -f "$LOG_FILE" ] || return 0
  local size
  size="$(stat -c %s "$LOG_FILE" 2>/dev/null || stat -f %z "$LOG_FILE" 2>/dev/null || echo 0)"
  if [ "$size" -gt "$LOG_MAX_BYTES" ]; then
    # copytruncate, não mv: o cron já tem "$LOG_FILE" aberto via >>, então
    # trocar o inode faria as próximas escritas irem pro arquivo antigo renomeado
    cp "$LOG_FILE" "$LOG_FILE.1"
    : > "$LOG_FILE"
  fi
}

window_sec=$(( SESSION_WINDOW_MINUTES * 60 ))

# marker guarda o INÍCIO fixo da janela atual ("<epoch> <origem>"), não a
# última atividade vista — senão cada mensagem nova empurra o fim da janela
# pra frente e o script nunca mais dispara.
#
# Retorna 0 (sessão ativa) se marker ou atividade do usuário ainda estão
# dentro da janela; 1 caso contrário. Loga o horário de expiração.
session_active() {
  local now_epoch marker_start marker_origin activity_ts end_ts remaining
  now_epoch="$(date +%s)"

  marker_start=0
  marker_origin="script"
  if [ -f "$MARKER_FILE" ]; then
    read -r marker_start marker_origin < "$MARKER_FILE" || true
    marker_start="${marker_start:-0}"
    marker_origin="${marker_origin:-script}"
  fi

  if [ "$marker_start" -gt 0 ] && [ $(( now_epoch - marker_start )) -lt "$window_sec" ]; then
    end_ts=$(( marker_start + window_sec ))
    remaining=$(( (end_ts - now_epoch) / 60 ))
    log "sessão ativa ($marker_origin), expira às $(fmt_hm "$end_ts") (faltam ${remaining}min)"
    return 0
  fi

  # marker inexistente ou expirado: janela do usuário pode já ter recomeçado
  # sem o script perceber (só sabemos a ÚLTIMA mensagem, não a primeira) —
  # se a última atividade ainda está dentro da janela, adota esse início.
  activity_ts="$(get_activity_epoch)"
  if [ "$activity_ts" -gt 0 ] && [ $(( now_epoch - activity_ts )) -lt "$window_sec" ]; then
    end_ts=$(( activity_ts + window_sec ))
    remaining=$(( (end_ts - now_epoch) / 60 ))
    printf '%s %s\n' "$activity_ts" "usuário" > "$MARKER_FILE"
    log "sessão do usuário detectada, expira às $(fmt_hm "$end_ts") (faltam ${remaining}min)"
    return 0
  fi

  return 1
}

start_session() {
  local now_epoch end_ts
  if ! "$CLAUDE_BIN" \
    --model claude-haiku-4-5-20251001 \
    --effort low \
    --print \
    "que dia é hoje?" > /dev/null; then
    log "ERRO: chamada ao claude falhou, marker não atualizado"
    return 1
  fi

  now_epoch="$(date +%s)"
  end_ts=$(( now_epoch + window_sec ))
  printf '%s %s\n' "$now_epoch" "script" > "$MARKER_FILE"
  log "sessão iniciada (script), expira às $(fmt_hm "$end_ts")"
  return 0
}

rotate_log_if_needed

if [ "$ENABLE_SESSION_SKIP" != "true" ]; then
  start_session || exit 1
  exit 0
fi

# Tenta iniciar a sessão; se já houver uma ativa, tenta de novo a cada
# RETRY_INTERVAL_MINUTES até MAX_RETRIES tentativas (cobre o caso de a sessão
# ativa estar quase acabando, ao invés de esperar o próximo ciclo do cron,
# até 5h depois). Se esgotar as tentativas, desiste e devolve o controle pro
# próximo disparo do cron.
attempt=1
while true; do
  if ! session_active; then
    start_session || exit 1
    exit 0
  fi

  if [ "$attempt" -ge "$MAX_RETRIES" ]; then
    log "sessão ainda ativa após ${attempt} tentativa(s), desistindo até o próximo ciclo do cron"
    exit 0
  fi

  log "tentativa ${attempt}/${MAX_RETRIES} sem sucesso, tentando de novo em ${RETRY_INTERVAL_MINUTES}min"
  sleep $(( RETRY_INTERVAL_MINUTES * 60 ))
  attempt=$((attempt + 1))
done
