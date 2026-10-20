#!/bin/bash
# Usage : scripts/run_sql.sh sql/fichier.sql   (DB=postgres pour une autre base)
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; source .env; set +a
f="$1"
STOP=1
case "$f" in *08_tests*) STOP=0;; esac   # les tests contiennent des erreurs voulues
( cd /tmp && sudo -u postgres psql -d "${DB:-novabank}" \
    -v ON_ERROR_STOP=$STOP \
    -v pwd_analyste="$PWD_ANALYSTE" -v pwd_support="$PWD_SUPPORT" \
    -v pwd_appli="$PWD_APPLI" -v pwd_auditeur="$PWD_AUDITEUR" ) < "$f"
