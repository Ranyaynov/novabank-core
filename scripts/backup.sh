#!/bin/bash
# Sauvegarde complète de la base dans backups/ (dossier ignoré par Git)
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p backups
F="backups/novabank_$(date +%Y%m%d_%H%M%S).dump"
( cd /tmp && sudo -u postgres pg_dump -Fc novabank ) > "$F"
ls -lh "$F"
