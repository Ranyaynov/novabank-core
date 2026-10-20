\timing on
\echo '===== AVANT les index ====='
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM core.transactions WHERE account_id = 4242 ORDER BY created_at DESC LIMIT 50;

-- 4 index
CREATE INDEX idx_tx_account_created ON core.transactions (account_id, created_at DESC);
CREATE INDEX idx_tx_transfer        ON core.transactions (transfer_id) WHERE transfer_id IS NOT NULL;
CREATE INDEX idx_accounts_customer  ON core.accounts (customer_id);
CREATE INDEX idx_transfers_from     ON core.transfers (from_account_id, created_at);
ANALYZE;

\echo '===== APRES les index ====='
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM core.transactions WHERE account_id = 4242 ORDER BY created_at DESC LIMIT 50;
