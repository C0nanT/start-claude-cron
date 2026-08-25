#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASK_CLAUDE="$SCRIPT_DIR/ask-claude.sh"
LOG_FILE="$SCRIPT_DIR/claude-cron.log"

# Ticks base (início de cada janela de 5h) e retentativas.
# Base :30 + offsets acumulados de 10,10,5,5,10,10 min:
#   05:30 05:40 05:50 05:55 06:00 06:10 06:20  (idem 10h, 15h, 20h)
# O script só chama o claude se a sessão anterior já acabou, então as
# retentativas não gastam token à toa.
BASE_HOURS="${BASE_HOURS:-5,10,15,20}"
NEXT_HOURS="$(python3 -c "print(','.join(str((int(h)+1)%24) for h in '$BASE_HOURS'.split(',')))")"

NEW_LINES=(
  "30,40,50,55 $BASE_HOURS * * * $ASK_CLAUDE >> $LOG_FILE 2>&1"
  "0,10,20 $NEXT_HOURS * * * $ASK_CLAUDE >> $LOG_FILE 2>&1"
)

current_crontab="$(crontab -l 2>/dev/null || true)"

# Remove qualquer entrada antiga deste script antes de reescrever.
kept="$(printf '%s\n' "$current_crontab" | grep -vF "$ASK_CLAUDE" || true)"

updated="$kept"
for line in "${NEW_LINES[@]}"; do
  updated="${updated:+$updated$'\n'}$line"
  echo "Adicionando: $line"
done

printf '%s\n' "$updated" | crontab -

echo
echo "Crontab atualizado. Confira com 'crontab -l'."
