# NovaBank Core

Base de données PostgreSQL d'une banque en ligne (projet seul, module SQL avancé et administration PostgreSQL, Bachelor 2).
Elle rend impossibles les 3 problèmes du prototype :
1. Un employé voit trop de données : 4 profils avec le minimum de droits, et des vues qui masquent les emails.
2. Deux virements simultanés donnent un solde négatif : verrouillage des comptes (FOR UPDATE), contrainte CHECK, procédure tout ou rien.
3. L'historique est lent : index sur transactions(account_id, created_at), mesuré avec EXPLAIN ANALYZE.

## Prérequis
VM Ubuntu avec un utilisateur sudo, accès internet pour apt.

## Utilisation

    git clone <URL_DU_DEPOT> && cd novabank_core
    cp .env.example .env        # puis mets tes mots de passe dans .env (jamais envoyé sur Git)
    ./reset.sh                  # refait TOUT de zéro (3 à 5 minutes)
    scripts/backup.sh           # sauvegarde pg_dump dans backups/

## Contenu
| Fichier | Étape |
|---|---|
| scripts/01_install.sh | 1. Serveur : PostgreSQL, pg_hba.conf (scram-sha-256, base novabank en local uniquement), ufw (tout fermé sauf SSH) |
| sql/01_database.sql, sql/02_schema.sql | 2. Base, 6 tables avec CHECK / UNIQUE / clés étrangères, 1 000 000 d'écritures (generate_series) |
| sql/03_roles.sql | 3. Profils analyste, support, appli, auditeur (GRANT / REVOKE, droits par colonne) |
| sql/04_views.sql | 4. Vue masquée, vue modifiable WITH CHECK OPTION, vue matérialisée |
| sql/05_indexes.sql | 5. 4 index et mesure avant / après |
| sql/06_triggers.sql | 6. Solde automatique, écritures immuables, alertes de fraude, journal d'audit |
| sql/07_procedures.sql | 7. sp_transfer, sp_open_account, fn_statement |
| sql/08_tests.sql | 8. Tests : les interdits sont refusés, les cas valides passent |
| reset.sh | Refait tout le projet |
| scripts/backup.sh | Sauvegarde pg_dump |
| captures/ | Captures d'écran du terminal |

## Sécurité
- Aucun mot de passe dans Git : ils sont dans .env (listé dans .gitignore).
- Mots de passe stockés en scram-sha-256.
- Les fonctions de trigger sont SECURITY DEFINER avec search_path fixé, pour que les profils limités ne puissent pas modifier eux-mêmes les soldes ni le journal.

## Déclaration d'utilisation de l'IA
Ce projet a été réalisé avec l'aide de Claude (Anthropic), utilisé pour structurer le projet et générer les scripts. J'ai relu, testé et compris chaque ligne, et je peux les expliquer.
