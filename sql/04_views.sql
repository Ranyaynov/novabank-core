-- Vue qui cache des données : email masqué, pas de téléphone
CREATE VIEW core.v_customers_masked AS
SELECT customer_id, first_name, last_name,
       left(email, 2) || '***@' || split_part(email, '@', 2) AS email_masque,
       birth_date, kyc_status, risk_level
FROM core.customers;

-- Vue modifiable avec limite : impossible de sortir un compte de la vue (WITH CHECK OPTION)
CREATE VIEW core.v_active_accounts AS
SELECT account_id, customer_id, iban, account_type, balance, status
FROM core.accounts
WHERE status = 'active'
WITH CHECK OPTION;

-- Vue enregistrée (matérialisée) : volume par jour et par type
CREATE MATERIALIZED VIEW core.mv_daily_volume AS
SELECT created_at::date AS jour, tx_type, count(*) AS nb, sum(amount) AS total
FROM core.transactions
GROUP BY 1, 2;
CREATE UNIQUE INDEX ON core.mv_daily_volume (jour, tx_type);

GRANT SELECT ON core.v_customers_masked, core.v_active_accounts, core.mv_daily_volume
  TO analyste, support, auditeur;

SELECT * FROM core.v_customers_masked LIMIT 3;
