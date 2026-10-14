DROP FUNCTION IF EXISTS public.complete_gold_sell(
    text,
    jsonb,
    text,
    text,
    text,
    text
);

CREATE OR REPLACE FUNCTION public.complete_gold_sell(
    p_seller_id text,
    p_transaction jsonb,
    p_country_code text,
    p_transaction_state_id text,
    p_blockchain_transaction_id text,
    p_blockchain_code text,
    p_ip_address text DEFAULT NULL::text
)
RETURNS TABLE(
    success boolean,
    document_number text,
    token_document_number text,
    quantity text,
    gross_amount text,
    net_amount text,
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

    v_seller public.users%rowtype;
    v_treasury public.users%rowtype;

    v_blockchain_transaction
        public.blockchain_transaction%rowtype;

    v_receiver_notification
        public.notification_message;

    v_device_tokens text[] :=
        array[]::text[];

    v_document_number text;
    v_token_document_number text;

    v_financial_transaction_id bigint;
    v_token_financial_transaction_id bigint;

    v_receiver_notification_id text;

    v_reference text;
    v_blockchain_code text;

    /*
     * Actual fiat amount moved between wallets.
     *
     * Fiat input:
     * The entered USD amount is the exact amount received.
     *
     * Gold input:
     * Use the debit side of the main sell principal.
     *
     * This preserves the existing settlement rules.
     */
    v_fiat_wallet_amount numeric;

    v_stage text := 'initialization';

    v_error_state text;
    v_error_message text;
    v_error_detail text;
    v_error_hint text;
    v_error_context text;
BEGIN
    /*
     * ==========================================================
     * 1. SERVICE ROLE AUTHORIZATION
     * ==========================================================
     */
    v_stage := 'service role validation';

    IF coalesce(auth.role(), '') <> 'service_role' THEN
        RAISE EXCEPTION USING
            ERRCODE = '42501',
            MESSAGE = 'SERVICE_ROLE_REQUIRED';
    END IF;

    /*
     * ==========================================================
     * 2. VALIDATE BLOCKCHAIN CODE
     * ==========================================================
     */
    v_stage := 'validate blockchain code';

    v_blockchain_code :=
        lower(nullif(btrim(p_blockchain_code), ''));

    IF v_blockchain_code IS NULL THEN
        RAISE EXCEPTION
            'BLOCKCHAIN_CODE_REQUIRED';
    END IF;

    /*
     * ==========================================================
     * 3. PREPARE GOLD SELL
     * ==========================================================
     *
     * The preparation function validates:
     * - Processing transaction state
     * - Selected blockchain
     * - Seller and treasury
     * - Gold wallet balance on selected blockchain
     * - Pricing
     * - GL mappings
     * - Posting components
     */
    v_stage := 'prepare gold sell';

    SELECT preparation_record.*
    INTO v_preparation
    FROM public.prepare_gold_sell(
        p_seller_id,
        p_transaction,
        p_country_code,
        p_transaction_state_id,
        v_blockchain_code
    ) AS preparation_record;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'GOLD_SELL_PREPARATION_NOT_FOUND';
    END IF;

    IF v_preparation.blockchain_code
       IS DISTINCT FROM v_blockchain_code
    THEN
        RAISE EXCEPTION
            'PREPARATION_BLOCKCHAIN_MISMATCH';
    END IF;

    /*
     * Validate the exact customer sell price returned
     * by the preparation function.
     *
     * Do not fetch the market price again here.
     */
    v_stage := 'validate gold price';

    IF coalesce(
        v_preparation.gold_price::numeric,
        0
    ) <= 0 THEN
        RAISE EXCEPTION
            'INVALID_GOLD_PRICE';
    END IF;

    /*
     * ==========================================================
     * 4. DETERMINE FIAT WALLET SETTLEMENT AMOUNT
     * ==========================================================
     */
    v_stage := 'resolve fiat wallet amount';

    IF lower(btrim(v_preparation.input_currency)) <> 'gold' THEN

        /*
         * FIAT INPUT
         *
         * The customer receives exactly the entered
         * USD amount.
         */
        v_fiat_wallet_amount :=
            v_preparation.input_amount::numeric;

    ELSE

        /*
         * GOLD INPUT
         *
         * Use the debit side of the main principal
         * component, preserving the existing logic.
         */
        SELECT
            component_record.debit_amount
        INTO
            v_fiat_wallet_amount
        FROM unnest(
            v_preparation.sell_components
        ) AS component_record
        WHERE component_record.component_type =
              'principal'::public."ComponentType"
        LIMIT 1;

        IF v_fiat_wallet_amount IS NULL THEN
            RAISE EXCEPTION
                'GOLD_SELL_PRINCIPAL_COMPONENT_NOT_FOUND';
        END IF;

    END IF;

    IF v_fiat_wallet_amount IS NULL
       OR v_fiat_wallet_amount <= 0
    THEN
        RAISE EXCEPTION
            'INVALID_FIAT_WALLET_AMOUNT';
    END IF;

    /*
     * ==========================================================
     * 5. VALIDATE TRANSACTION REFERENCE
     * ==========================================================
     */
    v_stage := 'validate transaction reference';

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
     * 6. LOCK PENDING BLOCKCHAIN TRANSACTION
     * ==========================================================
     */
    v_stage := 'lock blockchain transaction';

    SELECT blockchain_record.*
    INTO v_blockchain_transaction
    FROM public.blockchain_transaction AS blockchain_record
    WHERE blockchain_record.id::text =
          p_blockchain_transaction_id
      AND blockchain_record.created_by =
          p_seller_id
      AND blockchain_record.reference =
          v_reference
      AND blockchain_record.transaction_type =
          'gold_token_sell'::public."TransactionType"
      AND blockchain_record.status =
          'pending'::public."BlockchainTxStatus"
      AND blockchain_record.chain =
          v_blockchain_code
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'INVALID_BLOCKCHAIN_TRANSACTION';
    END IF;

    /*
     * ==========================================================
     * 7. VALIDATE BLOCKCHAIN TRANSACTION
     * ==========================================================
     */
    v_stage := 'validate blockchain transaction';

    IF lower(v_blockchain_transaction.sender)
       IS DISTINCT FROM
       lower(v_preparation.seller_wallet_address)
    THEN
        RAISE EXCEPTION
            'BLOCKCHAIN_SELLER_MISMATCH';
    END IF;

    IF lower(v_blockchain_transaction.receiver)
       IS DISTINCT FROM
       lower(v_preparation.treasury_wallet_address)
    THEN
        RAISE EXCEPTION
            'BLOCKCHAIN_TREASURY_MISMATCH';
    END IF;

    IF v_blockchain_transaction.quantity
       IS DISTINCT FROM
       v_preparation.token_quantity::numeric
    THEN
        RAISE EXCEPTION
            'BLOCKCHAIN_QUANTITY_MISMATCH';
    END IF;

    IF coalesce(
        v_blockchain_transaction.gross_amount,
        0
    ) IS DISTINCT FROM
       v_preparation.gross_amount::numeric
    THEN
        RAISE EXCEPTION
            'BLOCKCHAIN_GROSS_AMOUNT_MISMATCH';
    END IF;

    IF coalesce(
        v_blockchain_transaction.net_amount,
        0
    ) IS DISTINCT FROM
       v_preparation.net_amount::numeric
    THEN
        RAISE EXCEPTION
            'BLOCKCHAIN_NET_AMOUNT_MISMATCH';
    END IF;

    IF coalesce(
        v_blockchain_transaction.fee_amount,
        0
    ) IS DISTINCT FROM
       v_preparation.token_fee_equivalent::numeric
    THEN
        RAISE EXCEPTION
            'BLOCKCHAIN_FEE_AMOUNT_MISMATCH';
    END IF;

    IF lower(
        btrim(v_blockchain_transaction.country_code)
    ) IS DISTINCT FROM
       lower(btrim(v_preparation.country_code))
    THEN
        RAISE EXCEPTION
            'BLOCKCHAIN_COUNTRY_MISMATCH';
    END IF;

    /*
     * ==========================================================
     * 8. FETCH SELLER AND TREASURY
     * ==========================================================
     */
    v_stage := 'fetch seller and treasury';

    v_seller :=
        public.fetch_user_by_id(
            v_preparation.seller_id
        );

    v_treasury :=
        public.fetch_user_by_id(
            v_preparation.treasury_id
        );

    IF v_seller.id IS NULL THEN
        RAISE EXCEPTION
            'SELLER_NOT_FOUND';
    END IF;

    IF v_treasury.id IS NULL THEN
        RAISE EXCEPTION
            'TREASURY_NOT_FOUND';
    END IF;

    /*
     * ==========================================================
     * 9. CREATE SELLER NOTIFICATION
     * ==========================================================
     *
     * The seller receives the USD wallet settlement.
     */
    v_stage := 'create seller notification';

    v_receiver_notification :=
        public.create_notification_message(
            v_preparation.country_code,
            'gold_token_sell'::public."TransactionType",
            'receiver'::public."NotificationAudience",
            v_fiat_wallet_amount,
            'USD',
            v_reference,
            v_preparation.token_quantity::numeric,
            coalesce(
                v_treasury.email,
                v_treasury.phone,
                v_treasury.id
            ),
            coalesce(
                v_seller.email,
                v_seller.phone,
                v_seller.id
            )
        );

    /*
     * ==========================================================
     * 10. FETCH DEVICE TOKENS
     * ==========================================================
     */
    v_stage := 'fetch seller device tokens';

    v_device_tokens :=
        coalesce(
            public.fetch_device_tokens(
                v_preparation.country_code,
                v_seller.id
            ),
            array[]::text[]
        );

    /*
     * ==========================================================
     * 11. GENERATE DOCUMENT NUMBERS
     * ==========================================================
     */
    v_stage := 'generate main document number';

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

    v_token_document_number :=
        v_document_number || '-01';

    /*
     * ==========================================================
     * 12. INSERT FIAT FINANCIAL TRANSACTION
     * ==========================================================
     */
    v_stage := 'insert fiat financial transaction';

    INSERT INTO public.financial_transaction (
        document_number,
        fiscal_year,
        period,
        reference,
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
        v_preparation.period,
        v_reference,
        'gold_token_sell'::public."TransactionType",

        'User ' ||
        coalesce(
            v_seller.email,
            v_seller.phone,
            v_seller.id
        ) ||
        ' sold ' ||
        v_preparation.token_quantity ||
        'g Gold tokens at USD ' ||
        v_preparation.gold_price ||
        '/g',

        v_seller.id,
        v_preparation.gross_amount::numeric,
        'usd',
        v_preparation.country_code
    )
    RETURNING id
    INTO v_financial_transaction_id;

    /*
     * ==========================================================
     * 13. POST FIAT GL ENTRIES
     * ==========================================================
     */
    v_stage := 'post fiat financial entries';

    PERFORM *
    FROM public.post_financial_entries(
        p_document_number =>
            v_document_number,

        p_country_code =>
            v_preparation.country_code,

        p_transaction_id =>
            v_financial_transaction_id,

        p_transaction_type =>
            'gold_token_sell'::public."TransactionType",

        p_created_by =>
            v_seller.id,

        p_components =>
            v_preparation.sell_components,

        p_mappings =>
            v_preparation.sell_mappings,

        p_currency_code =>
            'usd',

        p_fiscal_year =>
            v_preparation.fiscal_year,

        p_period =>
            v_preparation.period,

        p_reference =>
            v_reference,

        p_deposit_type =>
            null
    );

    /*
     * ==========================================================
     * 14. POST USD WALLET ENTRIES
     * ==========================================================
     *
     * Treasury USD wallet:
     *     Debit
     *
     * Seller customer USD wallet:
     *     Credit
     *
     * USD wallets are not blockchain-specific.
     * p_blockchain_code must remain NULL.
     */
    v_stage := 'post fiat wallet entries';

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
            v_seller.id,

        p_sender_id =>
            v_treasury.id,

        p_transaction_type =>
            'gold_token_sell'::public."TransactionType",

        p_credit_amount =>
            v_fiat_wallet_amount,

        p_debit_amount =>
            v_fiat_wallet_amount,

        p_sender_wallet_owner =>
            'treasury'::public."WalletOwnerType",

        p_receiver_wallet_owner =>
            'customer'::public."WalletOwnerType",

        p_currency_code =>
            'usd',

        p_country_code =>
            v_preparation.country_code,

        p_audit_action_type =>
            'token_sold'::public."AuditActionType",

        p_treasury_id =>
            null,

        p_fee_amount =>
            0,

        p_ip_address =>
            p_ip_address,

        p_receiver_notification =>
            v_receiver_notification,

        p_sender_notification =>
            null,

        p_blockchain_code =>
            null
    ) AS wallet_result;

    /*
     * ==========================================================
     * 15. INSERT GOLD FINANCIAL TRANSACTION
     * ==========================================================
     */
    v_stage := 'insert token financial transaction';

    INSERT INTO public.financial_transaction (
        document_number,
        fiscal_year,
        period,
        reference,
        transaction_type,
        description,
        created_by,
        gross_amount,
        currency_code,
        country_code
    )
    VALUES (
        v_token_document_number,
        v_preparation.fiscal_year,
        v_preparation.period,
        v_reference || '-01',
        'gold_token_sell_sub_tx'::public."TransactionType",

        'User ' ||
        coalesce(
            v_seller.email,
            v_seller.phone,
            v_seller.id
        ) ||
        ' transferred ' ||
        v_preparation.token_quantity ||
        'g Gold tokens to treasury on ' ||
        v_blockchain_code,

        v_seller.id,
        v_preparation.token_quantity::numeric,
        'gold',
        v_preparation.country_code
    )
    RETURNING id
    INTO v_token_financial_transaction_id;

    /*
     * ==========================================================
     * 16. POST GOLD GL ENTRIES
     * ==========================================================
     */
    v_stage := 'post token financial entries';

    PERFORM *
    FROM public.post_financial_entries(
        p_document_number =>
            v_token_document_number,

        p_country_code =>
            v_preparation.country_code,

        p_transaction_id =>
            v_token_financial_transaction_id,

        p_transaction_type =>
            'gold_token_sell_sub_tx'::public."TransactionType",

        p_created_by =>
            v_seller.id,

        p_components =>
            v_preparation.token_components,

        p_mappings =>
            v_preparation.token_mappings,

        p_currency_code =>
            'gold',

        p_fiscal_year =>
            v_preparation.fiscal_year,

        p_period =>
            v_preparation.period,

        p_reference =>
            v_reference || '-01',

        p_deposit_type =>
            null
    );

    /*
     * ==========================================================
     * 17. POST BLOCKCHAIN-SPECIFIC GOLD WALLET ENTRIES
     * ==========================================================
     *
     * Seller customer Gold wallet:
     *     Debit token_quantity
     *
     * Treasury Gold wallet:
     *     Credit token_quantity
     *
     * Both wallets belong to the selected blockchain.
     *
     * No additional Gold fee is transferred.
     */
    v_stage := 'post token wallet entries';

    PERFORM *
    FROM public.post_wallet_entries(
        p_fiscal_year =>
            v_preparation.fiscal_year,

        p_period =>
            v_preparation.period,

        p_document_number =>
            v_token_document_number,

        p_reference =>
            v_reference || '-01',

        p_receiver_id =>
            v_treasury.id,

        p_sender_id =>
            v_seller.id,

        p_transaction_type =>
            'gold_token_sell'::public."TransactionType",

        p_credit_amount =>
            v_preparation.token_quantity::numeric,

        p_debit_amount =>
            v_preparation.token_quantity::numeric,

        p_sender_wallet_owner =>
            'customer'::public."WalletOwnerType",

        p_receiver_wallet_owner =>
            'treasury'::public."WalletOwnerType",

        p_currency_code =>
            'gold',

        p_country_code =>
            v_preparation.country_code,

        p_audit_action_type =>
            'token_sold'::public."AuditActionType",

        p_treasury_id =>
            null,

        p_fee_amount =>
            0,

        p_ip_address =>
            p_ip_address,

        p_receiver_notification =>
            null,

        p_sender_notification =>
            null,

        p_blockchain_code =>
            v_blockchain_code
    );

    /*
     * ==========================================================
     * 18. COMPLETE BLOCKCHAIN TRANSACTION
     * ==========================================================
     */
    v_stage := 'complete blockchain transaction';

    UPDATE public.blockchain_transaction
    SET
        document_number =
            v_token_document_number,

        status =
            'completed'::public."BlockchainTxStatus"

    WHERE id::text =
          p_blockchain_transaction_id
      AND chain =
          v_blockchain_code
      AND status =
          'pending'::public."BlockchainTxStatus";

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'BLOCKCHAIN_TRANSACTION_UPDATE_FAILED';
    END IF;

    /*
     * ==========================================================
     * 19. COMPLETE TRANSACTION STATE
     * ==========================================================
     */
    v_stage := 'complete transaction state';

    UPDATE public.transaction_state
    SET
        user_id =
            v_seller.id,

        status =
            'success'::public."TransactionStatus",

        message =
            null,

        updated_at =
            now()

    WHERE id =
          p_transaction_state_id
      AND created_by =
          p_seller_id
      AND transaction_type =
          'gold_token_sell'::public."TransactionType"
      AND blockchain_code =
          v_blockchain_code
      AND status =
          'processing'::public."TransactionStatus";

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'TRANSACTION_STATE_UPDATE_FAILED';
    END IF;

    /*
     * ==========================================================
     * 20. RETURN COMPLETION RESULT
     * ==========================================================
     *
     * Financial gross and net values remain unchanged.
     * Fiat wallet settlement is calculated separately.
     */
    v_stage := 'return gold sell result';

    RETURN QUERY
    SELECT
        true,
        v_document_number,
        v_token_document_number,
        v_preparation.token_quantity,
        v_preparation.gross_amount,
        v_preparation.net_amount,
        v_preparation.fiat_fee,
        v_blockchain_transaction.explorer_url,
        v_receiver_notification_id,
        v_device_tokens,
        v_receiver_notification.title,
        v_receiver_notification.body,
        v_receiver_notification.payload
            ->> 'reference';

EXCEPTION
    WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS
            v_error_state =
                RETURNED_SQLSTATE,

            v_error_message =
                MESSAGE_TEXT,

            v_error_detail =
                PG_EXCEPTION_DETAIL,

            v_error_hint =
                PG_EXCEPTION_HINT,

            v_error_context =
                PG_EXCEPTION_CONTEXT;

        RAISE EXCEPTION USING
            ERRCODE =
                v_error_state,

            MESSAGE =
                format(
                    'GOLD_SELL_FAILED at [%s]: %s',
                    v_stage,
                    v_error_message
                ),

            DETAIL =
                coalesce(
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

            HINT =
                coalesce(
                    nullif(v_error_hint, ''),
                    'Check the Gold Sell stage reported in the error'
                );
END;
$function$;