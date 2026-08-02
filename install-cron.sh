#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASK_CLAUDE="$SCRIPT_DIR/ask-claude.sh"
LOG_FILE="$SCRIPT_DIR/claude-cron.log"

# shellcheck disable=SC1091
[ -f "$SCRIPT_DIR/.env" ] && set -a && . "$SCRIPT_DIR/.env" && set +a

# Faixa/intervalo do cron: configuráveis via .env, não hardcoded — veja .env.example
CRON_START_HOUR="${CRON_START_HOUR:-5}"
CRON_END_HOUR="${CRON_END_HOUR:-21}"
CRON_INTERVAL_MINUTES="${CRON_INTERVAL_MINUTES:-5}"

NEW_LINES=(
  "*/$CRON_INTERVAL_MINUTES $CRON_START_HOUR-$CRON_END_HOUR * * * $ASK_CLAUDE >> $LOG_FILE 2>&1"
)

echo "Sugestão de agenda: a cada ${CRON_INTERVAL_MINUTES}min, entre ${CRON_START_HOUR}h e ${CRON_END_HOUR}h. Pra mudar, defina CRON_START_HOUR / CRON_END_HOUR / CRON_INTERVAL_MINUTES no .env (veja .env.example) e rode de novo."
echo
echo "Aviso: se você já rodou este projeto antes neste PC e tem entradas antigas de ask-claude.sh no crontab (ex: horários fixos como 08:00/23:00/23:30, os antigos 0,10,20,30,40,50 8/23h, ou o formato anterior '30 5,10,15,20 * * *'), remova-as manualmente com 'crontab -e' antes de continuar, para evitar execuções duplicadas."
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
