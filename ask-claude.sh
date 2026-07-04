#!/usr/bin/env bash
set -euo pipefail

claude \
  --model claude-haiku-4-5-20251001 \
  --effort low \
  --print \
  "que dia é hoje?"
