CREATE SCHEMA core;
CREATE SCHEMA audit;

-- Clients : email unique et valide, client majeur
CREATE TABLE core.customers (
  customer_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  first_name  TEXT NOT NULL,
  last_name   TEXT NOT NULL,
  email       TEXT NOT NULL UNIQUE CHECK (email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  phone       TEXT,
  birth_date  DATE NOT NULL CHECK (birth_date <= CURRENT_DATE - INTERVAL '18 years'),
  kyc_status  TEXT NOT NULL DEFAULT 'pending' CHECK (kyc_status IN ('pending','verified','rejected')),
  risk_level  TEXT NOT NULL DEFAULT 'low' CHECK (risk_level IN ('low','medium','high')),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Comptes : solde jamais sous 0, IBAN unique
CREATE TABLE core.accounts (
  account_id   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  customer_id  BIGINT NOT NULL REFERENCES core.customers(customer_id),
  iban         TEXT NOT NULL UNIQUE,
  account_type TEXT NOT NULL CHECK (account_type IN ('checking','savings')),
  balance      NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (balance >= 0),
  status       TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','frozen','closed')),
  opened_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Virements : montant positif, deux comptes différents
CREATE TABLE core.transfers (
  transfer_id     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  from_account_id BIGINT NOT NULL REFERENCES core.accounts(account_id),
  to_account_id   BIGINT NOT NULL REFERENCES core.accounts(account_id),
  amount          NUMERIC(14,2) NOT NULL CHECK (amount > 0),
  label           TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (from_account_id <> to_account_id)
);

-- Écritures (grand livre)
CREATE TABLE core.transactions (
  tx_id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  account_id    BIGINT NOT NULL REFERENCES core.accounts(account_id),
  tx_type       TEXT NOT NULL CHECK (tx_type IN ('deposit','withdrawal','transfer_in','transfer_out')),
  amount        NUMERIC(14,2) NOT NULL CHECK (amount > 0),
  balance_after NUMERIC(14,2) NOT NULL CHECK (balance_after >= 0),
  transfer_id   BIGINT REFERENCES core.transfers(transfer_id),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Alertes de fraude
CREATE TABLE core.fraud_alerts (
  alert_id   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  account_id BIGINT NOT NULL REFERENCES core.accounts(account_id),
  tx_id      BIGINT REFERENCES core.transactions(tx_id),
  rule_code  TEXT NOT NULL CHECK (rule_code IN ('BIG_WITHDRAWAL','BURST_TRANSFERS')),
  status     TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open','reviewed','closed')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Journal d'audit
CREATE TABLE audit.audit_log (
  log_id     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  table_name TEXT NOT NULL,
  operation  TEXT NOT NULL,
  old_data   JSONB,
  new_data   JSONB,
  db_user    TEXT NOT NULL,
  changed_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 10 000 clients
INSERT INTO core.customers (first_name, last_name, email, phone, birth_date, kyc_status, risk_level)
SELECT 'Prenom' || g, 'Nom' || g, 'client' || g || '@novabank.test',
       '06' || lpad(((g * 7919) % 100000000)::text, 8, '0'),
       DATE '1950-01-01' + (g * 37) % 18000,
       (ARRAY['verified','verified','pending','rejected'])[1 + g % 4],
       (ARRAY['low','low','medium','high'])[1 + g % 4]
FROM generate_series(1, 10000) AS g;

-- 20 000 comptes (2 par client)
INSERT INTO core.accounts (customer_id, iban, account_type)
SELECT 1 + (g - 1) % 10000, 'FR76' || lpad(g::text, 23, '0'),
       CASE WHEN g <= 10000 THEN 'checking' ELSE 'savings' END
FROM generate_series(1, 20000) AS g;

-- 1 000 000 d'écritures : 50 par compte, solde cumulé jamais négatif
INSERT INTO core.transactions (account_id, tx_type, amount, balance_after, created_at)
SELECT account_id, tx_type, amount,
       SUM(CASE WHEN tx_type = 'deposit' THEN amount ELSE -amount END)
         OVER (PARTITION BY account_id ORDER BY n),
       created_at
FROM (
  SELECT a.account_id, g.n,
         CASE WHEN g.n % 2 = 1 THEN 'deposit' ELSE 'withdrawal' END AS tx_type,
         CASE WHEN g.n % 2 = 1
              THEN (100 + (a.account_id * 31 + ((g.n + 1) / 2) * 17) % 900)::numeric
              ELSE round((100 + (a.account_id * 31 + ((g.n + 1) / 2) * 17) % 900) / 2.0, 2)
         END AS amount,
         now() - make_interval(days => 50 - g.n) AS created_at
  FROM core.accounts a CROSS JOIN generate_series(1, 50) AS g(n)
) s;

-- Le solde de chaque compte = balance_after de sa dernière écriture
UPDATE core.accounts a SET balance = t.balance_after
FROM (SELECT DISTINCT ON (account_id) account_id, balance_after
      FROM core.transactions ORDER BY account_id, created_at DESC) t
WHERE a.account_id = t.account_id;

ANALYZE;

SELECT 'customers' AS table_name, count(*) FROM core.customers
UNION ALL SELECT 'accounts', count(*) FROM core.accounts
UNION ALL SELECT 'transactions', count(*) FROM core.transactions;
