#!/usr/bin/env bash
set -euo pipefail

CLAUDE_BIN="${CLAUDE_BIN:-$HOME/.local/bin/claude}"

"$CLAUDE_BIN" \
  --model claude-haiku-4-5-20251001 \
  --effort low \
  --print \
  "que dia é hoje?"
