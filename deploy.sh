#!/bin/bash
# Copies all .mq5 files from the repo to every MT5 Experts folder on this server.
# Called by GitHub Actions on every push that touches a .mq5 file.

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

EXPERTS_DIRS=(
  "/root/.wine/drive_c/Program Files/Equiti Brokerage (Seychelles) MT5 Terminal/MQL5/Experts"
  "/root/.wine/drive_c/Program Files/MetaTrader 5/MQL5/Experts"
  "/root/.wine_puprime/drive_c/Program Files/MetaTrader 5/MQL5/Experts"
  "/root/.wine_tmgm/drive_c/Program Files/MetaTrader 5/MQL5/Experts"
)

echo "=== Deploy $(date '+%Y-%m-%d %H:%M:%S') ==="
for dir in "${EXPERTS_DIRS[@]}"; do
  if [ -d "$dir" ]; then
    cp "$REPO_DIR"/*.mq5 "$dir/" && echo "OK  → $dir" || echo "FAIL→ $dir"
  else
    echo "SKIP→ $dir (not found)"
  fi
done
echo "=== Done ==="
