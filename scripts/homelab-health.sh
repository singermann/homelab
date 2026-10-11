#!/usr/bin/env bash
# homelab-health – kurzer Systemcheck, Ausgabe landet im Journal
# Ziel: /usr/local/bin/homelab-health
# <4> = Warnung, <6> = Info (systemd wertet das Präfix als Priorität)
set -euo pipefail

THRESHOLD="${THRESHOLD:-80}"   # Warngrenze Plattenbelegung in %

# Festplatten
while read -r use mount; do
  pct=${use%\%}
  if (( pct >= THRESHOLD )); then
    echo "<4>Festplatte $mount zu ${pct}% belegt (Grenze ${THRESHOLD}%)"
  else
    echo "<6>Festplatte $mount: ${pct}%"
  fi
done < <(df --output=pcent,target -x tmpfs -x devtmpfs -x efivarfs | tail -n +2)

# Arbeitsspeicher
mem=$(free | awk '/^Mem:/ {printf "%d", $3/$2*100}')
echo "<6>Arbeitsspeicher: ${mem}%"

# Fehlgeschlagene Dienste – Fehler der Prüfung selbst als Warnung melden
if ! out=$(systemctl --failed --no-legend --plain 2>&1); then
  echo "<4>Dienst-Prüfung nicht möglich: $out"
else
  failed=$(awk '{print $1}' <<<"$out" | xargs)
  if [[ -n "$failed" ]]; then
    echo "<4>Fehlgeschlagene Dienste: $failed"
  else
    echo "<6>Keine fehlgeschlagenen Dienste"
  fi
fi
