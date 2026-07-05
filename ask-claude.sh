#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$SCRIPT_DIR/.env" ] && set -a && . "$SCRIPT_DIR/.env" && set +a

CLAUDE_BIN="${CLAUDE_BIN:-$HOME/.local/bin/claude}"

"$CLAUDE_BIN" \
  --model claude-haiku-4-5-20251001 \
  --effort low \
  --print \
  "que dia é hoje?"
