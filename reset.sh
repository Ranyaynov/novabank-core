#!/bin/bash
# Refait tout le projet de zéro : serveur, base, droits, vues, index, triggers, procédures, tests
set -euo pipefail
cd "$(dirname "$0")"
[ -f .env ] || { echo "Fichier .env manquant : cp .env.example .env puis mets tes mots de passe"; exit 1; }
sudo -v
bash scripts/01_install.sh
DB=postgres scripts/run_sql.sh sql/01_database.sql
for f in sql/02_schema.sql sql/03_roles.sql sql/04_views.sql sql/05_indexes.sql \
         sql/06_triggers.sql sql/07_procedures.sql sql/08_tests.sql; do
  echo "##### $f"
  scripts/run_sql.sh "$f"
done
echo "OK : projet reconstruit"
