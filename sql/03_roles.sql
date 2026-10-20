-- Création des 4 profils (sans doublon si on relance)
DO $$
DECLARE r TEXT;
BEGIN
  FOREACH r IN ARRAY ARRAY['analyste','support','appli','auditeur'] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r) THEN
      EXECUTE format('CREATE ROLE %I LOGIN', r);
    END IF;
  END LOOP;
END $$;

-- Mots de passe lus dans .env (jamais écrits dans Git)
ALTER ROLE analyste PASSWORD :'pwd_analyste';
ALTER ROLE support  PASSWORD :'pwd_support';
ALTER ROLE appli    PASSWORD :'pwd_appli';
ALTER ROLE auditeur PASSWORD :'pwd_auditeur';

-- On retire tout à tout le monde, puis on donne le minimum
REVOKE ALL ON SCHEMA core, audit FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA core, audit FROM PUBLIC;
REVOKE CONNECT ON DATABASE novabank FROM PUBLIC;
GRANT CONNECT ON DATABASE novabank TO analyste, support, appli, auditeur;
GRANT USAGE ON SCHEMA core TO analyste, support, appli, auditeur;
GRANT USAGE ON SCHEMA audit TO auditeur;

-- ANALYSTE : lit tout sauf email et téléphone des clients
GRANT SELECT ON core.accounts, core.transfers, core.transactions, core.fraud_alerts TO analyste;
GRANT SELECT (customer_id, first_name, last_name, birth_date, kyc_status, risk_level, created_at)
  ON core.customers TO analyste;

-- SUPPORT : lit clients et comptes, modifie seulement email et téléphone
GRANT SELECT ON core.customers, core.accounts TO support;
GRANT UPDATE (email, phone) ON core.customers TO support;

-- APPLI : fait vivre l'application, ne touche jamais au solde directement
GRANT SELECT, INSERT, UPDATE ON core.customers TO appli;
GRANT SELECT, INSERT ON core.accounts, core.transfers, core.transactions, core.fraud_alerts TO appli;
GRANT UPDATE (status) ON core.accounts TO appli;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA core TO appli;

-- AUDITEUR : lit seulement le journal et les alertes
GRANT SELECT ON audit.audit_log, core.fraud_alerts TO auditeur;

\du
