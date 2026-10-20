\set VERBOSITY terse
\echo '##### CONTRAINTES (chaque test doit afficher ERROR) #####'
\echo '--- T1 email invalide'
INSERT INTO core.customers (first_name,last_name,email,birth_date) VALUES ('A','B','pas-un-email','1990-01-01');
\echo '--- T2 client mineur'
INSERT INTO core.customers (first_name,last_name,email,birth_date) VALUES ('A','B','mineur@test.fr', CURRENT_DATE - 3650);
\echo '--- T3 email en double'
INSERT INTO core.customers (first_name,last_name,email,birth_date) VALUES ('A','B','client1@novabank.test','1990-01-01');
\echo '--- T4 solde négatif'
UPDATE core.accounts SET balance = -1 WHERE account_id = 1;
\echo '--- T5 virement vers le même compte'
INSERT INTO core.transfers (from_account_id, to_account_id, amount) VALUES (1, 1, 10);
\echo '--- T6 montant de virement négatif'
INSERT INTO core.transfers (from_account_id, to_account_id, amount) VALUES (1, 2, -5);
\echo '--- T7 modifier une écriture'
UPDATE core.transactions SET amount = 1 WHERE tx_id = 1;
\echo '--- T8 supprimer une écriture'
DELETE FROM core.transactions WHERE tx_id = 1;
\echo '--- T9 vider le grand livre'
TRUNCATE core.transactions;
\echo '--- T10 sortir un compte de la vue modifiable'
UPDATE core.v_active_accounts SET status = 'closed' WHERE account_id = 1;

\echo '##### VIREMENT OK (soldes avant / après) #####'
SELECT account_id, balance FROM core.accounts WHERE account_id IN (1, 2) ORDER BY 1;
CALL core.sp_transfer(1, 2, 10, 'test OK');
SELECT account_id, balance FROM core.accounts WHERE account_id IN (1, 2) ORDER BY 1;
SELECT tx_id, account_id, tx_type, amount, balance_after FROM core.transactions
WHERE transfer_id = (SELECT max(transfer_id) FROM core.transfers) ORDER BY tx_id;

\echo '##### VIREMENT TROP GROS : refusé, soldes inchangés #####'
CALL core.sp_transfer(1, 2, 99999999, 'trop gros');
SELECT account_id, balance FROM core.accounts WHERE account_id IN (1, 2) ORDER BY 1;

\echo '##### FRAUDE #####'
INSERT INTO core.transactions (account_id, tx_type, amount) VALUES (3, 'deposit', 10000);
INSERT INTO core.transactions (account_id, tx_type, amount) VALUES (3, 'withdrawal', 5000);
DO $$ BEGIN FOR i IN 1..5 LOOP CALL core.sp_transfer(4, 5, 1, 'rafale'); END LOOP; END $$;
SELECT alert_id, account_id, rule_code, status FROM core.fraud_alerts ORDER BY alert_id;

\echo '##### AUDIT #####'
UPDATE core.customers SET phone = '0600000000' WHERE customer_id = 1;
SELECT log_id, table_name, operation, old_data->>'phone' AS ancien, new_data->>'phone' AS nouveau, db_user
FROM audit.audit_log ORDER BY log_id DESC LIMIT 2;

\echo '##### OUVERTURE DE COMPTE + RELEVE #####'
CALL core.sp_open_account(1, 'savings', 100, NULL);
CALL core.sp_open_account(3, 'savings', 100, NULL);
SELECT * FROM core.fn_statement((SELECT max(account_id) FROM core.accounts), 5);

\echo '##### VUES #####'
REFRESH MATERIALIZED VIEW core.mv_daily_volume;
SELECT * FROM core.mv_daily_volume ORDER BY jour DESC, tx_type LIMIT 4;

\echo '##### DROITS (les ERROR sont voulues) #####'
SET ROLE analyste;
\echo '--- analyste lit l''email (refusé)'
SELECT email FROM core.customers LIMIT 1;
\echo '--- analyste lit la vue masquée (OK)'
SELECT * FROM core.v_customers_masked LIMIT 2;
\echo '--- analyste supprime un compte (refusé)'
DELETE FROM core.accounts WHERE account_id = 1;
RESET ROLE;
SET ROLE support;
\echo '--- support lit les écritures (refusé)'
SELECT * FROM core.transactions LIMIT 1;
\echo '--- support supprime un client (refusé)'
DELETE FROM core.customers WHERE customer_id = 1;
RESET ROLE;
SET ROLE auditeur;
\echo '--- auditeur lit le journal (OK)'
SELECT log_id, table_name, operation FROM audit.audit_log LIMIT 2;
\echo '--- auditeur lit les écritures (refusé)'
SELECT * FROM core.transactions LIMIT 1;
RESET ROLE;
SET ROLE appli;
\echo '--- appli lit le journal d''audit (refusé)'
SELECT * FROM audit.audit_log LIMIT 1;
\echo '--- appli modifie un solde (refusé)'
UPDATE core.accounts SET balance = 1000000 WHERE account_id = 5;
\echo '--- appli fait un virement (OK)'
CALL core.sp_transfer(5, 6, 1, 'par appli');
RESET ROLE;
