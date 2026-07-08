#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASK_CLAUDE="$SCRIPT_DIR/ask-claude.sh"
LOG_FILE="$SCRIPT_DIR/claude-cron.log"

NEW_LINES=(
  "30 5,10,15,20 * * * $ASK_CLAUDE >> $LOG_FILE 2>&1"
)

echo "Aviso: se você já rodou este projeto antes neste PC e tem entradas antigas de ask-claude.sh no crontab (ex: horários fixos como 08:00/23:00/23:30 ou os antigos 0,10,20,30,40,50 8/23h), remova-as manualmente com 'crontab -e' antes de continuar, para evitar execuções duplicadas."
echo

current_crontab="$(crontab -l 2>/dev/null || true)"

existing_project_lines="$(printf '%s\n' "$current_crontab" | grep -F "$ASK_CLAUDE" || true)"
if [ -n "$existing_project_lines" ]; then
  echo "Encontrei entrada(s) existentes no seu crontab referenciando este script:"
  while IFS= read -r existing_line; do
    echo "  $existing_line"
  done <<< "$existing_project_lines"
  echo "Este script NÃO remove nem altera entradas existentes — só adiciona as que faltam. Revise manualmente se quiser evitar duplicidade."
  echo
fi

updated_crontab="$current_crontab"
for line in "${NEW_LINES[@]}"; do
  if printf '%s\n' "$current_crontab" | grep -qxF "$line"; then
    echo "Já presente, pulando: $line"
  else
    if [ -z "$updated_crontab" ]; then
      updated_crontab="$line"
    else
      updated_crontab="$(printf '%s\n%s' "$updated_crontab" "$line")"
    fi
    echo "Adicionando: $line"
  fi
done

printf '%s\n' "$updated_crontab" | crontab -

echo
echo "Crontab atualizado. Confira com 'crontab -l'."
