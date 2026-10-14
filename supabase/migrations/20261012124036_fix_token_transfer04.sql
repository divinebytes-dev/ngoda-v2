
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

    v_blockchain_transaction
        public.blockchain_transaction%rowtype;

    v_sender_notification
        public.notification_message;

    v_receiver_notification
        public.notification_message;

    v_device_tokens text[] :=
        ARRAY[]::text[];

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
    /*
     * ==========================================================
     * AUTHORIZATION
     * ==========================================================
     */
    IF coalesce(auth.role(), '') <> 'service_role'
    THEN
        RAISE EXCEPTION USING
            ERRCODE = '42501',
            MESSAGE = 'SERVICE_ROLE_REQUIRED';
    END IF;

    /*
     * ==========================================================
     * VALIDATE BLOCKCHAIN CODE
     * ==========================================================
     */
    v_stage := 'validate blockchain code';

    v_blockchain_code :=
        lower(nullif(btrim(p_blockchain_code), ''));

    IF v_blockchain_code IS NULL THEN
        RAISE EXCEPTION 'BLOCKCHAIN_CODE_REQUIRED';
    END IF;

    /*
     * ==========================================================
     * PREPARE GOLD TRANSFER
     * ==========================================================
     *
     * Recalculate and validate trusted values.
     * Also locks the processing transaction state.
     */
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
        RAISE EXCEPTION
            'GOLD_TRANSFER_PREPARATION_NOT_FOUND';
    END IF;

    IF v_preparation.blockchain_code
       IS DISTINCT FROM v_blockchain_code
    THEN
        RAISE EXCEPTION
            'BLOCKCHAIN_CODE_MISMATCH';
    END IF;

    v_reference :=
        nullif(
            btrim(p_transaction ->> 'r'),
            ''
        );

    IF v_reference IS NULL THEN
        RAISE EXCEPTION
            'REFERENCE_IS_REQUIRED';
    END IF;

    /*
     * ==========================================================
     * LOCK BLOCKCHAIN TRANSACTION
     * ==========================================================
     */
    v_stage := 'lock blockchain transaction';

    SELECT blockchain_record.*
    INTO v_blockchain_transaction
    FROM public.blockchain_transaction AS blockchain_record
    WHERE blockchain_record.id::text =
          p_blockchain_transaction_id
      AND blockchain_record.created_by =
          p_sender_id
      AND blockchain_record.reference =
          v_reference
      AND blockchain_record.transaction_type =
          'gold_token_transfer'::public."TransactionType"
      AND blockchain_record.status =
          'pending'::public."BlockchainTxStatus"
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'INVALID_BLOCKCHAIN_TRANSACTION';
    END IF;

    /*
     * ==========================================================
     * VALIDATE BLOCKCHAIN TRANSACTION
     * ==========================================================
     */
    v_stage := 'validate blockchain transaction';

    /*
     * Ensure the recorded blockchain is the same
     * as the selected blockchain.
     */
    IF lower(btrim(v_blockchain_transaction.chain))
       IS DISTINCT FROM v_blockchain_code
    THEN
        RAISE EXCEPTION
            'BLOCKCHAIN_CODE_MISMATCH';
    END IF;

    IF lower(v_blockchain_transaction.sender)
       IS DISTINCT FROM
       lower(v_preparation.sender_wallet_address)
    THEN
        RAISE EXCEPTION
            'BLOCKCHAIN_SENDER_MISMATCH';
    END IF;

    IF lower(v_blockchain_transaction.receiver)
       IS DISTINCT FROM
       lower(v_preparation.receiver_wallet_address)
    THEN
        RAISE EXCEPTION
            'BLOCKCHAIN_RECEIVER_MISMATCH';
    END IF;

    IF v_blockchain_transaction.quantity
       IS DISTINCT FROM
       v_preparation.amount::numeric
    THEN
        RAISE EXCEPTION
            'BLOCKCHAIN_QUANTITY_MISMATCH';
    END IF;

    IF coalesce(
        v_blockchain_transaction.fee_amount,
        0
    ) IS DISTINCT FROM
       v_preparation.fee::numeric
    THEN
        RAISE EXCEPTION
            'BLOCKCHAIN_FEE_MISMATCH';
    END IF;

    IF lower(
        btrim(v_blockchain_transaction.currency_code)
    ) IS DISTINCT FROM 'gold'
    THEN
        RAISE EXCEPTION
            'INVALID_BLOCKCHAIN_CURRENCY';
    END IF;

    /*
     * ==========================================================
     * FETCH TRANSFER USERS
     * ==========================================================
     */
    v_stage := 'fetch transfer users';

    v_sender :=
        public.fetch_user_by_id(
            v_preparation.sender_id
        );

    v_receiver :=
        public.fetch_user_by_id(
            v_preparation.receiver_id
        );

    IF v_sender.id IS NULL THEN
        RAISE EXCEPTION
            'SENDER_NOT_FOUND';
    END IF;

    IF v_receiver.id IS NULL THEN
        RAISE EXCEPTION
            'RECEIVER_NOT_FOUND';
    END IF;

    /*
     * ==========================================================
     * CREATE SENDER NOTIFICATION
     * ==========================================================
     */
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
            coalesce(
                v_sender.email,
                v_sender.phone,
                v_sender.id
            ),
            coalesce(
                v_receiver.email,
                v_receiver.phone,
                v_receiver.id
            )
        );

    /*
     * ==========================================================
     * CREATE RECEIVER NOTIFICATION
     * ==========================================================
     */
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
            coalesce(
                v_sender.email,
                v_sender.phone,
                v_sender.id
            ),
            coalesce(
                v_receiver.email,
                v_receiver.phone,
                v_receiver.id
            )
        );

    /*
     * ==========================================================
     * FETCH RECEIVER DEVICE TOKENS
     * ==========================================================
     */
    v_stage := 'fetch receiver device tokens';

    v_device_tokens :=
        coalesce(
            public.fetch_device_tokens(
                v_preparation.country_code,
                v_receiver.id
            ),
            ARRAY[]::text[]
        );

    /*
     * ==========================================================
     * GENERATE DOCUMENT NUMBER
     * ==========================================================
     */
    v_stage := 'generate document number';

    v_document_number :=
        public.generate_document_number(
            v_preparation.document_prefix,
            v_preparation.fiscal_year,
            v_preparation.period,
            v_preparation.country_code
        );

    IF v_document_number IS NULL
       OR btrim(v_document_number) = ''
    THEN
        RAISE EXCEPTION
            'DOCUMENT_NUMBER_GENERATION_FAILED';
    END IF;

    /*
     * ==========================================================
     * CREATE FINANCIAL TRANSACTION
     * ==========================================================
     */
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
        coalesce(
            v_sender.email,
            v_sender.phone,
            v_sender.id
        ) ||
        ' transferred ' ||
        v_preparation.amount ||
        'g Gold tokens to user ' ||
        coalesce(
            v_receiver.email,
            v_receiver.phone,
            v_receiver.id
        ),
        v_sender.id,
        v_preparation.total_amount::numeric,
        'gold',
        v_preparation.country_code
    )
    RETURNING id
    INTO v_financial_transaction_id;

    /*
     * ==========================================================
     * POST GOLD GL ENTRIES
     * ==========================================================
     */
    v_stage := 'post financial entries';

    PERFORM *
    FROM public.post_financial_entries(
        p_document_number =>
            v_document_number,

        p_country_code =>
            v_preparation.country_code,

        p_transaction_id =>
            v_financial_transaction_id,

        p_transaction_type =>
            'gold_token_transfer'::public."TransactionType",

        p_created_by =>
            v_sender.id,

        p_components =>
            v_preparation.components,

        p_mappings =>
            v_preparation.mappings,

        p_currency_code =>
            'gold',

        p_fiscal_year =>
            v_preparation.fiscal_year,

        p_period =>
            v_preparation.period,

        p_reference =>
            v_reference,

        p_deposit_type =>
            NULL
    );

    /*
     * ==========================================================
     * POST WALLET ENTRIES
     * ==========================================================
     *
     * Sender:
     *   Debit amount + fee
     *
     * Receiver:
     *   Credit amount
     *
     * Treasury:
     *   Credit fee
     *
     * All movements use the selected blockchain.
     */
    v_stage := 'post wallet entries';

    SELECT wallet_result.receiver_notification_id
    INTO v_receiver_notification_id
    FROM public.post_wallet_entries(
        p_fiscal_year =>
            v_preparation.fiscal_year,

        p_period =>
            v_preparation.period,

        p_document_number =>
            v_document_number,

        p_reference =>
            v_reference,

        p_receiver_id =>
            v_receiver.id,

        p_sender_id =>
            v_sender.id,

        p_transaction_type =>
            'gold_token_transfer'::public."TransactionType",

        p_credit_amount =>
            v_preparation.amount::numeric,

        p_debit_amount =>
            v_preparation.total_amount::numeric,

        p_sender_wallet_owner =>
            'customer'::public."WalletOwnerType",

        p_receiver_wallet_owner =>
            'customer'::public."WalletOwnerType",

        p_currency_code =>
            'gold',

        p_country_code =>
            v_preparation.country_code,

        p_audit_action_type =>
            'token_transferred'::public."AuditActionType",

        p_treasury_id =>
            v_preparation.treasury_id,

        p_fee_amount =>
            v_preparation.fee::numeric,

        p_ip_address =>
            p_ip_address,

        p_receiver_notification =>
            v_receiver_notification,

        p_sender_notification =>
            v_sender_notification,

        p_blockchain_code =>
            v_blockchain_code
    ) AS wallet_result;

    /*
     * ==========================================================
     * COMPLETE BLOCKCHAIN TRANSACTION
     * ==========================================================
     */
    v_stage := 'complete blockchain transaction';

    UPDATE public.blockchain_transaction
    SET
        document_number = v_document_number,
        status =
            'completed'::public."BlockchainTxStatus"
    WHERE id::text = p_blockchain_transaction_id
      AND status =
          'pending'::public."BlockchainTxStatus"
      AND lower(btrim(chain)) = v_blockchain_code;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'BLOCKCHAIN_TRANSACTION_UPDATE_FAILED';
    END IF;

    /*
     * ==========================================================
     * COMPLETE TRANSACTION STATE
     * ==========================================================
     */
    v_stage := 'complete transaction state';

    UPDATE public.transaction_state
    SET
        user_id = v_receiver.id,
        status =
            'success'::public."TransactionStatus",
        message = NULL,
        updated_at = now()
    WHERE id = p_transaction_state_id
      AND created_by = p_sender_id
      AND transaction_type =
          'gold_token_transfer'::public."TransactionType"
      AND status =
          'processing'::public."TransactionStatus";

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'TRANSACTION_STATE_UPDATE_FAILED';
    END IF;

    /*
     * ==========================================================
     * RETURN RESULT
     * ==========================================================
     */
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
