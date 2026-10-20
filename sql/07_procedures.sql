CREATE SEQUENCE core.iban_seq START 100000;

-- Virement sûr : tout ou rien (une erreur annule les 3 écritures)
CREATE PROCEDURE core.sp_transfer(p_from BIGINT, p_to BIGINT, p_amount NUMERIC, p_label TEXT DEFAULT NULL)
LANGUAGE plpgsql AS $$
DECLARE v_id BIGINT;
BEGIN
  IF p_from = p_to THEN RAISE EXCEPTION 'Les deux comptes doivent être différents'; END IF;
  IF p_amount IS NULL OR p_amount <= 0 THEN RAISE EXCEPTION 'Montant invalide'; END IF;
  -- On verrouille les 2 comptes dans l'ordre des id (évite les blocages croisés)
  PERFORM 1 FROM core.accounts WHERE account_id IN (p_from, p_to) ORDER BY account_id FOR UPDATE;
  IF (SELECT count(*) FROM core.accounts WHERE account_id IN (p_from, p_to)) <> 2 THEN
    RAISE EXCEPTION 'Compte introuvable';
  END IF;
  INSERT INTO core.transfers (from_account_id, to_account_id, amount, label)
  VALUES (p_from, p_to, p_amount, p_label) RETURNING transfer_id INTO v_id;
  -- Un virement = 2 écritures ; le trigger calcule le solde et refuse si insuffisant
  INSERT INTO core.transactions (account_id, tx_type, amount, transfer_id) VALUES (p_from, 'transfer_out', p_amount, v_id);
  INSERT INTO core.transactions (account_id, tx_type, amount, transfer_id) VALUES (p_to,   'transfer_in',  p_amount, v_id);
END $$;

-- Ouverture de compte (client vérifié obligatoire) avec dépôt initial optionnel
CREATE PROCEDURE core.sp_open_account(p_customer_id BIGINT, p_type TEXT, p_initial NUMERIC DEFAULT 0,
                                      INOUT p_account_id BIGINT DEFAULT NULL)
LANGUAGE plpgsql AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM core.customers WHERE customer_id = p_customer_id AND kyc_status = 'verified') THEN
    RAISE EXCEPTION 'Client inexistant ou KYC non validé';
  END IF;
  INSERT INTO core.accounts (customer_id, iban, account_type)
  VALUES (p_customer_id, 'FR76' || lpad(nextval('core.iban_seq')::text, 23, '0'), p_type)
  RETURNING account_id INTO p_account_id;
  IF p_initial > 0 THEN
    INSERT INTO core.transactions (account_id, tx_type, amount) VALUES (p_account_id, 'deposit', p_initial);
  END IF;
END $$;

-- Relevé (fonction : une procédure ne peut pas renvoyer de lignes)
CREATE FUNCTION core.fn_statement(p_account_id BIGINT, p_limit INT DEFAULT 50)
RETURNS TABLE (tx_id BIGINT, tx_type TEXT, amount NUMERIC, balance_after NUMERIC, created_at TIMESTAMPTZ)
LANGUAGE sql STABLE AS $$
  SELECT t.tx_id, t.tx_type, t.amount, t.balance_after, t.created_at
  FROM core.transactions t
  WHERE t.account_id = p_account_id
  ORDER BY t.created_at DESC, t.tx_id DESC
  LIMIT p_limit;
$$;

-- Droits d'exécution : seulement l'appli (et l'analyste pour le relevé)
REVOKE ALL ON ALL ROUTINES IN SCHEMA core FROM PUBLIC;
GRANT EXECUTE ON ALL PROCEDURES IN SCHEMA core TO appli;
GRANT EXECUTE ON FUNCTION core.fn_statement(BIGINT, INT) TO appli, analyste;
GRANT USAGE ON SEQUENCE core.iban_seq TO appli;
