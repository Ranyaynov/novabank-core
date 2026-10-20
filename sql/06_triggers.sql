-- 1) Le solde se met à jour seul + refus si solde insuffisant
CREATE FUNCTION core.fn_apply_transaction() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = core, pg_temp AS $$
DECLARE
  v_balance NUMERIC;
  v_status  TEXT;
  v_new     NUMERIC;
BEGIN
  -- FOR UPDATE verrouille le compte : deux opérations simultanées passent l'une après l'autre
  SELECT balance, status INTO v_balance, v_status
  FROM core.accounts WHERE account_id = NEW.account_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Compte % introuvable', NEW.account_id; END IF;
  IF v_status <> 'active' THEN RAISE EXCEPTION 'Compte % non actif', NEW.account_id; END IF;
  IF NEW.tx_type IN ('deposit', 'transfer_in') THEN
    v_new := v_balance + NEW.amount;
  ELSE
    v_new := v_balance - NEW.amount;
  END IF;
  IF v_new < 0 THEN RAISE EXCEPTION 'Solde insuffisant sur le compte %', NEW.account_id; END IF;
  UPDATE core.accounts SET balance = v_new WHERE account_id = NEW.account_id;
  NEW.balance_after := v_new;
  RETURN NEW;
END $$;

CREATE TRIGGER trg_apply_tx BEFORE INSERT ON core.transactions
FOR EACH ROW EXECUTE FUNCTION core.fn_apply_transaction();

-- 2) Le passé ne change plus : ni UPDATE, ni DELETE, ni TRUNCATE
CREATE FUNCTION core.fn_block_changes() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'Table % : % interdit (écritures immuables)', TG_TABLE_NAME, TG_OP;
END $$;

CREATE TRIGGER trg_tx_immutable BEFORE UPDATE OR DELETE ON core.transactions
FOR EACH ROW EXECUTE FUNCTION core.fn_block_changes();
CREATE TRIGGER trg_tx_no_truncate BEFORE TRUNCATE ON core.transactions
FOR EACH STATEMENT EXECUTE FUNCTION core.fn_block_changes();

-- 3) Fraude : retrait >= 5000, ou 5 virements sortants en 10 minutes
CREATE FUNCTION core.fn_fraud_check() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = core, pg_temp AS $$
DECLARE v_count INT;
BEGIN
  IF NEW.tx_type = 'withdrawal' AND NEW.amount >= 5000 THEN
    INSERT INTO core.fraud_alerts (account_id, tx_id, rule_code)
    VALUES (NEW.account_id, NEW.tx_id, 'BIG_WITHDRAWAL');
  END IF;
  IF NEW.tx_type = 'transfer_out' THEN
    SELECT count(*) INTO v_count FROM core.transactions
    WHERE account_id = NEW.account_id AND tx_type = 'transfer_out'
      AND created_at >= NEW.created_at - INTERVAL '10 minutes';
    IF v_count >= 5 THEN
      INSERT INTO core.fraud_alerts (account_id, tx_id, rule_code)
      VALUES (NEW.account_id, NEW.tx_id, 'BURST_TRANSFERS');
    END IF;
  END IF;
  RETURN NULL;
END $$;

CREATE TRIGGER trg_fraud AFTER INSERT ON core.transactions
FOR EACH ROW EXECUTE FUNCTION core.fn_fraud_check();

-- 4) Audit : qui, quand, avant, après
CREATE FUNCTION audit.fn_log() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = audit, pg_temp AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO audit.audit_log (table_name, operation, old_data, new_data, db_user)
    VALUES (TG_TABLE_SCHEMA || '.' || TG_TABLE_NAME, TG_OP, NULL, to_jsonb(NEW), session_user);
  ELSIF TG_OP = 'UPDATE' THEN
    INSERT INTO audit.audit_log (table_name, operation, old_data, new_data, db_user)
    VALUES (TG_TABLE_SCHEMA || '.' || TG_TABLE_NAME, TG_OP, to_jsonb(OLD), to_jsonb(NEW), session_user);
  ELSE
    INSERT INTO audit.audit_log (table_name, operation, old_data, new_data, db_user)
    VALUES (TG_TABLE_SCHEMA || '.' || TG_TABLE_NAME, TG_OP, to_jsonb(OLD), NULL, session_user);
  END IF;
  RETURN NULL;
END $$;

CREATE TRIGGER trg_audit_customers AFTER INSERT OR UPDATE OR DELETE ON core.customers
FOR EACH ROW EXECUTE FUNCTION audit.fn_log();
CREATE TRIGGER trg_audit_accounts_life AFTER INSERT OR DELETE ON core.accounts
FOR EACH ROW EXECUTE FUNCTION audit.fn_log();
CREATE TRIGGER trg_audit_accounts_status AFTER UPDATE OF status ON core.accounts
FOR EACH ROW WHEN (OLD.status IS DISTINCT FROM NEW.status)
EXECUTE FUNCTION audit.fn_log();
