#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASK_CLAUDE="$SCRIPT_DIR/ask-claude.sh"
LOG_FILE="$SCRIPT_DIR/claude-cron.log"

# shellcheck disable=SC1091
[ -f "$SCRIPT_DIR/.env" ] && set -a && . "$SCRIPT_DIR/.env" && set +a

# Ticks do cron: configuráveis via .env, não hardcoded — veja .env.example.
# Cada tick tenta iniciar a janela; o retry fino (sessão quase acabando) é
# feito dentro do ask-claude.sh, não pelo cron. Os ticks ficam espaçados pela
# duração da janela (SESSION_WINDOW_MINUTES) a partir de CRON_START_HOUR:CRON_START_MINUTE,
# sem passar de CRON_END_HOUR.
CRON_START_HOUR="${CRON_START_HOUR:-5}"
CRON_START_MINUTE="${CRON_START_MINUTE:-30}"
CRON_END_HOUR="${CRON_END_HOUR:-21}"
SESSION_WINDOW_MINUTES="${SESSION_WINDOW_MINUTES:-300}"

if [ $(( SESSION_WINDOW_MINUTES % 60 )) -ne 0 ]; then
  echo "Erro: SESSION_WINDOW_MINUTES ($SESSION_WINDOW_MINUTES) precisa ser múltiplo de 60 pra gerar horários de cron (hora:minuto fixo)." >&2
  exit 1
fi
step_hours=$(( SESSION_WINDOW_MINUTES / 60 ))

cron_hours=()
h="$CRON_START_HOUR"
while [ "$h" -le "$CRON_END_HOUR" ]; do
  cron_hours+=("$h")
  h=$(( h + step_hours ))
done
cron_hours_csv="$(IFS=,; echo "${cron_hours[*]}")"

NEW_LINES=(
  "$CRON_START_MINUTE $cron_hours_csv * * * $ASK_CLAUDE >> $LOG_FILE 2>&1"
)

ticks_human=""
for h in "${cron_hours[@]}"; do
  tick="$(printf '%02d:%02d' "$h" "$CRON_START_MINUTE")"
  ticks_human="${ticks_human:+$ticks_human, }$tick"
done
echo "Sugestão de agenda: $ticks_human (passo de ${step_hours}h = SESSION_WINDOW_MINUTES). Pra mudar, defina CRON_START_HOUR / CRON_START_MINUTE / CRON_END_HOUR / SESSION_WINDOW_MINUTES no .env (veja .env.example) e rode de novo."
echo
echo "Aviso: se você já rodou este projeto antes neste PC e tem entradas antigas de ask-claude.sh no crontab (ex: horários fixos como 08:00/23:00/23:30, os antigos 0,10,20,30,40,50 8/23h, ou o formato '*/5 5-21 * * *' de uma versão anterior que rodava a cada 5min o dia todo), remova-as manualmente com 'crontab -e' antes de continuar, para evitar execuções duplicadas."
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
