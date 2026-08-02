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

rotate_log_if_needed

window_sec=$(( SESSION_WINDOW_MINUTES * 60 ))
now_epoch="$(date +%s)"

if [ "$ENABLE_SESSION_SKIP" = "true" ]; then
  # marker guarda o INÍCIO fixo da janela atual ("<epoch> <origem>"), não a
  # última atividade vista — senão cada mensagem nova empurra o fim da janela
  # pra frente e o script nunca mais dispara.
  marker_start=0
  marker_origin="none"
  if [ -f "$MARKER_FILE" ]; then
    read -r marker_start marker_origin < "$MARKER_FILE" || true
    marker_start="${marker_start:-0}"
    marker_origin="${marker_origin:-script}"
  fi

  if [ "$marker_start" -gt 0 ] && [ $(( now_epoch - marker_start )) -lt "$window_sec" ]; then
    end_ts=$(( marker_start + window_sec ))
    remaining=$(( (end_ts - now_epoch) / 60 ))
    log "sessão ativa ($marker_origin), expira às $(fmt_hm "$end_ts") (faltam ${remaining}min)"
    exit 0
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
    exit 0
  fi
fi

if ! "$CLAUDE_BIN" \
  --model claude-haiku-4-5-20251001 \
  --effort low \
  --print \
  "que dia é hoje?" > /dev/null; then
  log "ERRO: chamada ao claude falhou, marker não atualizado"
  exit 1
fi

now_epoch="$(date +%s)"
end_ts=$(( now_epoch + window_sec ))
printf '%s %s\n' "$now_epoch" "script" > "$MARKER_FILE"
log "sessão iniciada (script), expira às $(fmt_hm "$end_ts")"
