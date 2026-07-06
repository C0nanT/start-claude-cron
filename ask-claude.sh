#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$SCRIPT_DIR/.env" ] && set -a && . "$SCRIPT_DIR/.env" && set +a

CLAUDE_BIN="${CLAUDE_BIN:-$HOME/.local/bin/claude}"
ENABLE_SESSION_SKIP="${ENABLE_SESSION_SKIP:-true}"
SESSION_WINDOW_MINUTES="${SESSION_WINDOW_MINUTES:-300}"
MARKER_FILE="$SCRIPT_DIR/.session-marker"
CLAUDE_ACTIVITY_FILE="${CLAUDE_ACTIVITY_FILE:-$HOME/.claude/history.jsonl}"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

get_marker_epoch() {
  [ -f "$MARKER_FILE" ] && cat "$MARKER_FILE" 2>/dev/null || echo 0
}

get_activity_epoch() {
  [ -f "$CLAUDE_ACTIVITY_FILE" ] && stat -c %Y "$CLAUDE_ACTIVITY_FILE" 2>/dev/null || echo 0
}

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

"$CLAUDE_BIN" \
  --model claude-haiku-4-5-20251001 \
  --effort low \
  --print \
  "que dia é hoje?"

date +%s > "$MARKER_FILE"
log "sessão iniciada, marker atualizado"
