CREATE OR REPLACE FUNCTION public.complete_gold_transfer(
    p_sender_id text,
    p_transaction jsonb,
    p_country_code text,
    p_transaction_state_id text,
    p_blockchain_transaction_id text,
    p_ip_address text DEFAULT NULL::text,
    p_blockchain_code text DEFAULT NULL::text
)
RETURNS TABLE(
    success boolean,
    document_number text,
    amount text,
    fee text,
    explorer_url text,
    receiver_notification_id text,
    device_tokens text[],
    push_title text,
    push_body text,
    push_reference text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
    v_preparation record;
    v_sender public.users%rowtype;
    v_receiver public.users%rowtype;
    v_blockchain_transaction public.blockchain_transaction%rowtype;
    v_sender_notification public.notification_message;
    v_receiver_notification public.notification_message;
    v_device_tokens text[] := ARRAY[]::text[];
    v_document_number text;
    v_financial_transaction_id bigint;
    v_receiver_notification_id text;
    v_reference text;
    v_blockchain_code text;
    v_stage text := 'initialization';
    v_error_state text;
    v_error_message text;
    v_error_detail text;
    v_error_hint text;
    v_error_context text;
BEGIN
    IF coalesce(auth.role(), '') <> 'service_role' THEN
        RAISE EXCEPTION USING
            ERRCODE = '42501',
            MESSAGE = 'SERVICE_ROLE_REQUIRED';
    END IF;

    v_stage := 'validate blockchain code';

    v_blockchain_code :=
        lower(nullif(btrim(p_blockchain_code), ''));

    IF v_blockchain_code IS NULL THEN
        RAISE EXCEPTION 'BLOCKCHAIN_CODE_REQUIRED';
    END IF;

    v_stage := 'prepare gold transfer';

    SELECT preparation_record.*
    INTO v_preparation
    FROM public.prepare_gold_transfer(
        p_sender_id,
        p_transaction,
        p_country_code,
        p_transaction_state_id,
        v_blockchain_code
    ) AS preparation_record;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'GOLD_TRANSFER_PREPARATION_NOT_FOUND';
    END IF;

    IF v_preparation.blockchain_code
       IS DISTINCT FROM v_blockchain_code THEN
        RAISE EXCEPTION 'TRANSACTION_BLOCKCHAIN_MISMATCH';
    END IF;

    v_reference :=
        nullif(btrim(p_transaction ->> 'r'), '');

    IF v_reference IS NULL THEN
        RAISE EXCEPTION 'REFERENCE_IS_REQUIRED';
    END IF;

    v_stage := 'lock blockchain transaction';

    SELECT blockchain_record.*
    INTO v_blockchain_transaction
    FROM public.blockchain_transaction AS blockchain_record
    WHERE blockchain_record.id::text = p_blockchain_transaction_id
      AND blockchain_record.created_by = p_sender_id
      AND blockchain_record.reference = v_reference
      AND blockchain_record.transaction_type =
          'gold_token_transfer'::public."TransactionType"
      AND blockchain_record.status =
          'pending'::public."BlockchainTxStatus"
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'INVALID_BLOCKCHAIN_TRANSACTION';
    END IF;

    v_stage := 'validate blockchain transaction';

    IF lower(btrim(v_blockchain_transaction.chain))
       IS DISTINCT FROM v_blockchain_code THEN
        RAISE EXCEPTION 'BLOCKCHAIN_CODE_MISMATCH';
    END IF;

    IF lower(v_blockchain_transaction.sender)
       IS DISTINCT FROM
       lower(v_preparation.sender_wallet_address) THEN
        RAISE EXCEPTION 'BLOCKCHAIN_SENDER_MISMATCH';
    END IF;

    IF lower(v_blockchain_transaction.receiver)
       IS DISTINCT FROM
       lower(v_preparation.receiver_wallet_address) THEN
        RAISE EXCEPTION 'BLOCKCHAIN_RECEIVER_MISMATCH';
    END IF;

    IF v_blockchain_transaction.quantity
       IS DISTINCT FROM v_preparation.amount::numeric THEN
        RAISE EXCEPTION 'BLOCKCHAIN_QUANTITY_MISMATCH';
    END IF;

    IF coalesce(v_blockchain_transaction.fee_amount, 0)
       IS DISTINCT FROM v_preparation.fee::numeric THEN
        RAISE EXCEPTION 'BLOCKCHAIN_FEE_MISMATCH';
    END IF;

    IF lower(btrim(v_blockchain_transaction.currency_code))
       IS DISTINCT FROM 'gold' THEN
        RAISE EXCEPTION 'INVALID_BLOCKCHAIN_CURRENCY';
    END IF;

    v_stage := 'fetch transfer users';

    v_sender :=
        public.fetch_user_by_id(v_preparation.sender_id);

    v_receiver :=
        public.fetch_user_by_id(v_preparation.receiver_id);

    IF v_sender.id IS NULL THEN
        RAISE EXCEPTION 'SENDER_NOT_FOUND';
    END IF;

    IF v_receiver.id IS NULL THEN
        RAISE EXCEPTION 'RECEIVER_NOT_FOUND';
    END IF;

    v_stage := 'create sender notification';

    v_sender_notification :=
        public.create_notification_message(
            v_preparation.country_code,
            'gold_token_transfer'::public."TransactionType",
            'sender'::public."NotificationAudience",
            v_preparation.amount::numeric,
            'GOLD',
            v_reference || '-01',
            v_preparation.amount::numeric,
            coalesce(v_sender.email, v_sender.phone, v_sender.id),
            coalesce(v_receiver.email, v_receiver.phone, v_receiver.id)
        );

    v_stage := 'create receiver notification';

    v_receiver_notification :=
        public.create_notification_message(
            v_preparation.country_code,
            'gold_token_transfer'::public."TransactionType",
            'receiver'::public."NotificationAudience",
            v_preparation.amount::numeric,
            'GOLD',
            v_reference || '-02',
            v_preparation.amount::numeric,
            coalesce(v_sender.email, v_sender.phone, v_sender.id),
            coalesce(v_receiver.email, v_receiver.phone, v_receiver.id)
        );

    v_stage := 'fetch receiver device tokens';

    v_device_tokens :=
        coalesce(
            public.fetch_device_tokens(
                v_preparation.country_code,
                v_receiver.id
            ),
            ARRAY[]::text[]
        );

    v_stage := 'generate document number';

    v_document_number :=
        public.generate_document_number(
            v_preparation.document_prefix,
            v_preparation.fiscal_year,
            v_preparation.period,
            v_preparation.country_code
        );

    IF nullif(btrim(v_document_number), '') IS NULL THEN
        RAISE EXCEPTION 'DOCUMENT_NUMBER_GENERATION_FAILED';
    END IF;

    v_stage := 'insert financial transaction';

    INSERT INTO public.financial_transaction (
        document_number,
        fiscal_year,
        reference,
        period,
        transaction_type,
        description,
        created_by,
        gross_amount,
        currency_code,
        country_code
    )
    VALUES (
        v_document_number,
        v_preparation.fiscal_year,
        v_reference,
        v_preparation.period,
        'gold_token_transfer'::public."TransactionType",
        'User ' ||
        coalesce(v_sender.email, v_sender.phone, v_sender.id) ||
        ' transferred ' ||
        v_preparation.amount ||
        'g Gold tokens to user ' ||
        coalesce(v_receiver.email, v_receiver.phone, v_receiver.id),
        v_sender.id,
        v_preparation.total_amount::numeric,
        'gold',
        v_preparation.country_code
    )
    RETURNING id INTO v_financial_transaction_id;

    v_stage := 'post financial entries';

    PERFORM *
    FROM public.post_financial_entries(
        p_document_number => v_document_number,
        p_country_code => v_preparation.country_code,
        p_transaction_id => v_financial_transaction_id,
        p_transaction_type =>
            'gold_token_transfer'::public."TransactionType",
        p_created_by => v_sender.id,
        p_components => v_preparation.components,
        p_mappings => v_preparation.mappings,
        p_currency_code => 'gold',
        p_fiscal_year => v_preparation.fiscal_year,
        p_period => v_preparation.period,
        p_reference => v_reference,
        p_deposit_type => NULL
    );

    /*
     * The transaction type selects the wallets.
     * Both users use customer wallets.
     *
     * Receiver wallet creation, if needed,
     * occurs inside post_wallet_entries.
     */
    v_stage := 'post wallet entries';

    SELECT wallet_result.receiver_notification_id
    INTO v_receiver_notification_id
    FROM public.post_wallet_entries(
        p_fiscal_year => v_preparation.fiscal_year,
        p_period => v_preparation.period,
        p_document_number => v_document_number,
        p_reference => v_reference,
        p_receiver_id => v_receiver.id,
        p_sender_id => v_sender.id,
        p_transaction_type =>
            'gold_token_transfer'::public."TransactionType",
        p_credit_amount => v_preparation.amount::numeric,
        p_debit_amount => v_preparation.total_amount::numeric,
        p_sender_wallet_owner =>
            'customer'::public."WalletOwnerType",
        p_receiver_wallet_owner =>
            'customer'::public."WalletOwnerType",
        p_currency_code => 'gold',
        p_country_code => v_preparation.country_code,
        p_audit_action_type =>
            'token_transferred'::public."AuditActionType",
        p_treasury_id => v_preparation.treasury_id,
        p_fee_amount => v_preparation.fee::numeric,
        p_ip_address => p_ip_address,
        p_receiver_notification => v_receiver_notification,
        p_sender_notification => v_sender_notification,
        p_blockchain_code => v_blockchain_code
    ) AS wallet_result;

    v_stage := 'complete blockchain transaction';

    UPDATE public.blockchain_transaction
    SET
        document_number = v_document_number,
        status = 'completed'::public."BlockchainTxStatus"
    WHERE id::text = p_blockchain_transaction_id
      AND status = 'pending'::public."BlockchainTxStatus"
      AND lower(btrim(chain)) = v_blockchain_code;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'BLOCKCHAIN_TRANSACTION_UPDATE_FAILED';
    END IF;

    v_stage := 'complete transaction state';

    UPDATE public.transaction_state
    SET
        user_id = v_receiver.id,
        status = 'success'::public."TransactionStatus",
        message = NULL,
        updated_at = now()
    WHERE id = p_transaction_state_id
      AND created_by = p_sender_id
      AND transaction_type =
          'gold_token_transfer'::public."TransactionType"
      AND status = 'processing'::public."TransactionStatus"
      AND blockchain_code = v_blockchain_code;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'TRANSACTION_STATE_UPDATE_FAILED';
    END IF;

    v_stage := 'return gold transfer result';

    RETURN QUERY
    SELECT
        true,
        v_document_number,
        v_preparation.amount,
        v_preparation.fee,
        v_blockchain_transaction.explorer_url,
        v_receiver_notification_id,
        v_device_tokens,
        v_receiver_notification.title,
        v_receiver_notification.body,
        v_receiver_notification.payload ->> 'reference';

EXCEPTION
    WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS
            v_error_state = RETURNED_SQLSTATE,
            v_error_message = MESSAGE_TEXT,
            v_error_detail = PG_EXCEPTION_DETAIL,
            v_error_hint = PG_EXCEPTION_HINT,
            v_error_context = PG_EXCEPTION_CONTEXT;

        RAISE EXCEPTION USING
            ERRCODE = v_error_state,
            MESSAGE = format(
                'GOLD_TRANSFER_FAILED at [%s]: %s',
                v_stage,
                v_error_message
            ),
            DETAIL = coalesce(
                nullif(
                    concat_ws(
                        E'\n',
                        nullif(v_error_detail, ''),
                        nullif(v_error_context, '')
                    ),
                    ''
                ),
                'No additional PostgreSQL context'
            ),
            HINT = coalesce(
                nullif(v_error_hint, ''),
                'Check the Gold Transfer stage reported in the error'
            );
END;
$function$;


CREATE OR REPLACE FUNCTION public.post_wallet_entries(
    p_fiscal_year integer,
    p_period integer,
    p_document_number text,
    p_reference text,
    p_receiver_id text,
    p_sender_id text,
    p_transaction_type "TransactionType",
    p_credit_amount numeric,
    p_debit_amount numeric,
    p_sender_wallet_owner "WalletOwnerType",
    p_receiver_wallet_owner "WalletOwnerType",
    p_currency_code text,
    p_country_code text,
    p_audit_action_type "AuditActionType",
    p_treasury_id text DEFAULT NULL::text,
    p_fee_amount numeric DEFAULT 0,
    p_ip_address text DEFAULT NULL::text,
    p_receiver_notification notification_message DEFAULT NULL::notification_message,
    p_sender_notification notification_message DEFAULT NULL::notification_message,
    p_blockchain_code text DEFAULT NULL::text
)
RETURNS TABLE(
    wallet_entry_count integer,
    receiver_notification_id text
)
LANGUAGE plpgsql
AS $function$
DECLARE
    v_blockchain_code text;
    v_sender_wallet public.wallet%rowtype;
    v_receiver_wallet public.wallet%rowtype;
    v_treasury_wallet public.wallet%rowtype;

    v_sender_balance_before numeric;
    v_sender_balance_after numeric;
    v_receiver_balance_before numeric;
    v_receiver_balance_after numeric;

    v_entry_count integer := 0;
    v_receiver_notification_id text := NULL;
BEGIN
    /*
     * GOLD wallets are blockchain-specific.
     * Fiat wallets must have NULL blockchain_code.
     */
    v_blockchain_code :=
        lower(nullif(btrim(p_blockchain_code), ''));

    IF lower(btrim(p_currency_code)) = 'gold' THEN
        IF v_blockchain_code IS NULL THEN
            RAISE EXCEPTION 'BLOCKCHAIN_CODE_REQUIRED';
        END IF;
    ELSIF v_blockchain_code IS NOT NULL THEN
        RAISE EXCEPTION 'BLOCKCHAIN_NOT_ALLOWED_FOR_FIAT';
    END IF;

    /*
     * Wallet ownership comes from transaction type,
     * not from the sender's or receiver's user role.
     */
    IF p_transaction_type =
       'gold_token_transfer'::public."TransactionType"
    THEN
        IF lower(btrim(p_currency_code))
               IS DISTINCT FROM 'gold'
           OR p_sender_wallet_owner IS DISTINCT FROM
               'customer'::public."WalletOwnerType"
           OR p_receiver_wallet_owner IS DISTINCT FROM
               'customer'::public."WalletOwnerType"
        THEN
            RAISE EXCEPTION
                'INVALID_GOLD_TRANSFER_WALLET_OWNER';
        END IF;
    END IF;

    /*
     * ==========================================================
     * LOCK EXISTING SENDER WALLET
     * ==========================================================
     */
    SELECT w.*
    INTO v_sender_wallet
    FROM public.wallet AS w
    WHERE w.country_code = p_country_code
      AND w.user_id = p_sender_id
      AND w.currency_code = p_currency_code
      AND w.blockchain_code
          IS NOT DISTINCT FROM v_blockchain_code
      AND w.owner_type = p_sender_wallet_owner
    LIMIT 1
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'SENDER_WALLET_NOT_FOUND';
    END IF;

    IF NOT v_sender_wallet.is_active THEN
        RAISE EXCEPTION 'SENDER_WALLET_FROZEN';
    END IF;

    v_sender_balance_before := v_sender_wallet.balance;

    /*
     * ==========================================================
     * LAZY RECEIVER WALLET CREATION
     * ==========================================================
     *
     * Receiver wallet is created on first receipt.
     * Existing wallets are reused.
     *
     * Separate conflict targets match the partial
     * unique indexes for fiat and blockchain wallets.
     */
    IF v_blockchain_code IS NULL THEN

        INSERT INTO public.wallet (
            user_id,
            currency_code,
            country_code,
            owner_type,
            blockchain_code,
            balance,
            is_active
        )
        VALUES (
            p_receiver_id,
            p_currency_code,
            p_country_code,
            p_receiver_wallet_owner,
            NULL,
            0,
            true
        )
        ON CONFLICT (
            country_code,
            user_id,
            currency_code,
            owner_type
        )
        WHERE blockchain_code IS NULL
        DO NOTHING;

    ELSE

        INSERT INTO public.wallet (
            user_id,
            currency_code,
            country_code,
            owner_type,
            blockchain_code,
            balance,
            is_active
        )
        VALUES (
            p_receiver_id,
            p_currency_code,
            p_country_code,
            p_receiver_wallet_owner,
            v_blockchain_code,
            0,
            true
        )
        ON CONFLICT (
            country_code,
            user_id,
            currency_code,
            owner_type,
            blockchain_code
        )
        WHERE blockchain_code IS NOT NULL
        DO NOTHING;

    END IF;

    /*
     * ==========================================================
     * LOCK RECEIVER WALLET
     * ==========================================================
     */
    SELECT w.*
    INTO v_receiver_wallet
    FROM public.wallet AS w
    WHERE w.country_code = p_country_code
      AND w.user_id = p_receiver_id
      AND w.currency_code = p_currency_code
      AND w.blockchain_code
          IS NOT DISTINCT FROM v_blockchain_code
      AND w.owner_type = p_receiver_wallet_owner
    LIMIT 1
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'RECEIVER_WALLET_NOT_FOUND';
    END IF;

    IF NOT v_receiver_wallet.is_active THEN
        RAISE EXCEPTION 'RECEIVER_WALLET_FROZEN';
    END IF;

    v_receiver_balance_before := v_receiver_wallet.balance;

    /*
     * ==========================================================
     * LOCK TREASURY WALLET WHEN FEES EXIST
     * ==========================================================
     */
    IF coalesce(p_fee_amount, 0) > 0 THEN

        IF p_treasury_id IS NULL THEN
            RAISE EXCEPTION 'TREASURY_REQUIRED_FOR_FEE';
        END IF;

        SELECT w.*
        INTO v_treasury_wallet
        FROM public.wallet AS w
        WHERE w.country_code = p_country_code
          AND w.user_id = p_treasury_id
          AND w.currency_code = p_currency_code
          AND w.blockchain_code
              IS NOT DISTINCT FROM v_blockchain_code
          AND w.owner_type =
              'treasury'::public."WalletOwnerType"
        LIMIT 1
        FOR UPDATE;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'TREASURY_WALLET_NOT_FOUND';
        END IF;

        IF NOT v_treasury_wallet.is_active THEN
            RAISE EXCEPTION 'TREASURY_WALLET_FROZEN';
        END IF;
    END IF;

    /*
     * ==========================================================
     * DEBIT SENDER
     * ==========================================================
     */
    IF p_debit_amount > 0 THEN

        UPDATE public.wallet
        SET balance = balance - p_debit_amount
        WHERE id = v_sender_wallet.id
          AND is_active = true
          AND balance >= p_debit_amount
        RETURNING balance INTO v_sender_balance_after;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'INSUFFICIENT_BALANCE';
        END IF;

        INSERT INTO public.wallet_entry (
            document_number,
            reference,
            fiscal_year,
            period,
            transaction_type,
            wallet_id,
            blockchain_code,
            currency_code,
            country_code,
            debit,
            credit,
            created_by
        )
        VALUES (
            p_document_number,
            p_reference,
            p_fiscal_year,
            p_period,
            p_transaction_type,
            v_sender_wallet.id,
            v_blockchain_code,
            p_currency_code,
            p_country_code,
            p_debit_amount,
            0,
            p_sender_id
        );

        v_entry_count := v_entry_count + 1;
    ELSE
        v_sender_balance_after := v_sender_balance_before;
    END IF;

    /*
     * ==========================================================
     * CREDIT RECEIVER
     * ==========================================================
     */
    IF p_credit_amount > 0 THEN

        UPDATE public.wallet
        SET balance = balance + p_credit_amount
        WHERE id = v_receiver_wallet.id
          AND is_active = true
        RETURNING balance INTO v_receiver_balance_after;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'RECEIVER_WALLET_FROZEN';
        END IF;

        INSERT INTO public.wallet_entry (
            document_number,
            reference,
            fiscal_year,
            period,
            transaction_type,
            wallet_id,
            blockchain_code,
            currency_code,
            country_code,
            debit,
            credit,
            created_by
        )
        VALUES (
            p_document_number,
            p_reference,
            p_fiscal_year,
            p_period,
            p_transaction_type,
            v_receiver_wallet.id,
            v_blockchain_code,
            p_currency_code,
            p_country_code,
            0,
            p_credit_amount,
            p_receiver_id
        );

        v_entry_count := v_entry_count + 1;
    ELSE
        v_receiver_balance_after := v_receiver_balance_before;
    END IF;

    /*
     * ==========================================================
     * CREDIT TREASURY FEE
     * ==========================================================
     */
    IF coalesce(p_fee_amount, 0) > 0 THEN

        UPDATE public.wallet
        SET balance = balance + p_fee_amount
        WHERE id = v_treasury_wallet.id
          AND is_active = true;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'TREASURY_WALLET_FROZEN';
        END IF;

        INSERT INTO public.wallet_entry (
            document_number,
            reference,
            fiscal_year,
            period,
            transaction_type,
            wallet_id,
            blockchain_code,
            currency_code,
            country_code,
            debit,
            credit,
            created_by
        )
        VALUES (
            p_document_number,
            p_reference,
            p_fiscal_year,
            p_period,
            p_transaction_type,
            v_treasury_wallet.id,
            v_blockchain_code,
            p_currency_code,
            p_country_code,
            0,
            p_fee_amount,
            p_treasury_id
        );

        v_entry_count := v_entry_count + 1;
    END IF;

    IF v_entry_count = 0 THEN
        RAISE EXCEPTION 'NO_WALLET_ENTRIES_TO_POST';
    END IF;

    /*
     * ==========================================================
     * UPDATE WALLET BALANCE SNAPSHOTS
     * ==========================================================
     */
    PERFORM public.update_wallet_balance_snapshot(
        p_transaction_type,
        p_sender_id,
        p_receiver_id,
        p_treasury_id,
        p_currency_code,
        v_sender_wallet.owner_type,
        v_receiver_wallet.owner_type,
        p_debit_amount,
        p_credit_amount,
        p_fiscal_year,
        p_period,
        p_country_code,
        coalesce(p_fee_amount, 0),
        v_blockchain_code
    );

    /*
     * ==========================================================
     * RECEIVER NOTIFICATION
     * ==========================================================
     */
    IF p_receiver_notification IS DISTINCT FROM NULL THEN

        INSERT INTO public.notifications (
            country_code,
            reference,
            user_id,
            payload,
            title,
            body,
            notification_type,
            transaction_type
        )
        VALUES (
            p_country_code,
            p_receiver_notification.payload ->> 'reference',
            p_receiver_id,
            p_receiver_notification.payload,
            p_receiver_notification.title,
            p_receiver_notification.body,
            p_receiver_notification.notification_type,
            p_transaction_type
        )
        RETURNING id::text INTO v_receiver_notification_id;
    END IF;

    /*
     * ==========================================================
     * SENDER NOTIFICATION
     * ==========================================================
     */
    IF p_sender_notification IS DISTINCT FROM NULL THEN

        INSERT INTO public.notifications (
            country_code,
            reference,
            user_id,
            payload,
            title,
            body,
            notification_type,
            transaction_type
        )
        VALUES (
            p_country_code,
            p_sender_notification.payload ->> 'reference',
            p_sender_id,
            p_sender_notification.payload,
            p_sender_notification.title,
            p_sender_notification.body,
            p_sender_notification.notification_type,
            p_transaction_type
        );
    END IF;

    /*
     * ==========================================================
     * AUDIT SENDER AND RECEIVER BALANCES
     * ==========================================================
     */
    INSERT INTO public.audit_log (
        fiscal_year,
        period,
        user_id,
        country_code,
        action_type,
        entity_type,
        entity_id,
        old_value,
        new_value,
        metadata,
        ip_address,
        document_number
    )
    VALUES
    (
        p_fiscal_year,
        p_period,
        p_sender_id,
        p_country_code,
        p_audit_action_type,
        'wallet',
        v_sender_wallet.id,
        jsonb_build_object(
            'balance_before', v_sender_balance_before::text
        ),
        jsonb_build_object(
            'balance_after', v_sender_balance_after::text
        ),
        jsonb_build_object(
            'receiver_id', p_receiver_id,
            'amount', p_credit_amount::text,
            'fee', coalesce(p_fee_amount, 0)::text,
            'currency', p_currency_code,
            'blockchain_code', v_blockchain_code
        ),
        p_ip_address,
        p_document_number
    ),
    (
        p_fiscal_year,
        p_period,
        p_receiver_id,
        p_country_code,
        p_audit_action_type,
        'wallet',
        v_receiver_wallet.id,
        jsonb_build_object(
            'balance_before', v_receiver_balance_before::text
        ),
        jsonb_build_object(
            'balance_after', v_receiver_balance_after::text
        ),
        jsonb_build_object(
            'sender_id', p_sender_id,
            'amount', p_credit_amount::text,
            'fee', coalesce(p_fee_amount, 0)::text,
            'currency', p_currency_code,
            'blockchain_code', v_blockchain_code
        ),
        p_ip_address,
        p_document_number
    );

    RETURN QUERY
    SELECT
        v_entry_count,
        v_receiver_notification_id;
END;
$function$;