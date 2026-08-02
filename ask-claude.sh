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

# stat portátil: GNU (Linux/WSL) usa -c, BSD/macOS usa -f
get_mtime_epoch() {
  stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null
}

get_marker_epoch() {
  [ -f "$MARKER_FILE" ] && cat "$MARKER_FILE" 2>/dev/null || echo 0
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

if [ "$ENABLE_SESSION_SKIP" = "true" ]; then
  marker_ts="$(get_marker_epoch)"
  activity_ts="$(get_activity_epoch)"

  latest_ts="$marker_ts"
  session_origin="script"
  if [ "$activity_ts" -gt "$marker_ts" ]; then
    latest_ts="$activity_ts"
    session_origin="usuário"
  fi

  if [ "$latest_ts" -gt 0 ]; then
    now_epoch="$(date +%s)"
    age_minutes=$(( (now_epoch - latest_ts) / 60 ))

    if [ "$age_minutes" -lt "$SESSION_WINDOW_MINUTES" ]; then
      log "sessão já ativa ($session_origin), iniciada às $(date -d "@$latest_ts" '+%H:%M'), pulando (idade: ${age_minutes}min < ${SESSION_WINDOW_MINUTES}min)"
      echo "$latest_ts" > "$MARKER_FILE"
      exit 0
    fi
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

date +%s > "$MARKER_FILE"
log "sessão iniciada, marker atualizado"
