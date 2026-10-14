
CREATE OR REPLACE FUNCTION public.prepare_gold_transfer(
    p_sender_id text,
    p_transaction jsonb,
    p_country_code text,
    p_transaction_state_id text,
    p_blockchain_code text
)
RETURNS TABLE(
    sender_id text,
    sender_wallet_address text,
    sender_wallet_index bigint,
    receiver_id text,
    receiver_wallet_address text,
    treasury_id text,
    treasury_wallet_address text,
    country_code text,
    blockchain_code text,
    fiscal_year integer,
    period integer,
    document_prefix text,
    amount text,
    fee text,
    total_amount text,
    mappings public.transaction_gl_mapping[],
    components public.posting_component[]
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
    v_state public.transaction_state%rowtype;

    v_sender public.users%rowtype;
    v_receiver public.users%rowtype;
    v_treasury public.users%rowtype;

    v_sender_wallet public.wallet%rowtype;

    v_receiver_identifier text;
    v_reference text;
    v_currency text;
    v_blockchain_code text;
    v_country_code text;

    v_raw_amount numeric;
    v_amount numeric;
    v_fee numeric := 0;
    v_total_amount numeric;

    v_fiscal_year integer;
    v_period integer;
    v_document_prefix text;

    v_mappings public.transaction_gl_mapping[];
    v_components public.posting_component[];

    v_adjusted_components public.posting_component[] :=
        ARRAY[]::public.posting_component[];

    v_component public.posting_component;
    v_adjusted_component public.posting_component;
BEGIN
    /*
     * ==========================================================
     * AUTHORIZATION
     * ==========================================================
     */
    IF coalesce(auth.role(), '') <> 'service_role' THEN
        RAISE EXCEPTION USING
            ERRCODE = '42501',
            MESSAGE = 'SERVICE_ROLE_REQUIRED';
    END IF;

    IF p_transaction IS NULL THEN
        RAISE EXCEPTION
            'TRANSACTION_DATA_IS_MISSING';
    END IF;

    /*
     * ==========================================================
     * NORMALIZE COUNTRY AND BLOCKCHAIN
     * ==========================================================
     */
    v_country_code :=
        lower(nullif(btrim(p_country_code), ''));

    IF v_country_code IS NULL THEN
        RAISE EXCEPTION
            'COUNTRY_CODE_REQUIRED';
    END IF;

    v_blockchain_code :=
        lower(nullif(btrim(p_blockchain_code), ''));

    IF v_blockchain_code IS NULL THEN
        RAISE EXCEPTION
            'BLOCKCHAIN_CODE_REQUIRED';
    END IF;

    /*
     * ==========================================================
     * VALIDATE ACTIVE BLOCKCHAIN
     * ==========================================================
     */
    PERFORM 1
    FROM public.supported_blockchain AS b
    JOIN public.supported_blockchain_network AS n
        ON n.blockchain_id = b.id
    WHERE b.code = v_blockchain_code
      AND b.is_active = true
      AND n.is_active = true
      AND n.is_default = true;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'BLOCKCHAIN_NOT_FOUND_OR_INACTIVE';
    END IF;

    /*
     * ==========================================================
     * LOCK AND VALIDATE TRANSACTION STATE
     * ==========================================================
     */
    SELECT state_record.*
    INTO v_state
    FROM public.transaction_state AS state_record
    WHERE state_record.id = p_transaction_state_id
      AND state_record.created_by = p_sender_id
      AND state_record.transaction_type =
          'gold_token_transfer'::public."TransactionType"
      AND state_record.status =
          'processing'::public."TransactionStatus"
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'INVALID_TRANSACTION_STATE';
    END IF;

    IF v_state.transaction_data
       IS DISTINCT FROM p_transaction
    THEN
        RAISE EXCEPTION
            'TRANSACTION_DATA_MISMATCH';
    END IF;

    /*
     * Blockchain is bound to the transaction state
     * at creation and cannot be changed afterward.
     */
    IF v_state.blockchain_code
       IS DISTINCT FROM v_blockchain_code
    THEN
        RAISE EXCEPTION
            'TRANSACTION_BLOCKCHAIN_MISMATCH';
    END IF;

    IF v_state.country_code
       IS DISTINCT FROM v_country_code
    THEN
        RAISE EXCEPTION
            'TRANSACTION_COUNTRY_MISMATCH';
    END IF;

    IF p_transaction ->> 'v'
       IS DISTINCT FROM 'v6'
    THEN
        RAISE EXCEPTION
            'OPERATION_NOT_ALLOWED';
    END IF;

    v_reference :=
        nullif(btrim(p_transaction ->> 'r'), '');

    IF v_reference IS NULL THEN
        RAISE EXCEPTION
            'REFERENCE_IS_REQUIRED';
    END IF;

    IF v_state.reference
       IS DISTINCT FROM v_reference
    THEN
        RAISE EXCEPTION
            'TRANSACTION_REFERENCE_MISMATCH';
    END IF;

    v_receiver_identifier :=
        nullif(btrim(p_transaction ->> 's'), '');

    IF v_receiver_identifier IS NULL THEN
        RAISE EXCEPTION
            'RECEIVER_IDENTIFIER_IS_REQUIRED';
    END IF;

    v_currency :=
        lower(nullif(btrim(p_transaction ->> 'c'), ''));

    IF v_currency IS DISTINCT FROM 'gold' THEN
        RAISE EXCEPTION
            'INVALID_GOLD_TRANSFER_CURRENCY';
    END IF;

    /*
     * ==========================================================
     * PARSE SIGNED GOLD QUANTITY
     * ==========================================================
     *
     * Preserve the existing signed serialization:
     * transaction.a / 100.
     *
     * GOLD precision: 6 decimal places.
     */
    BEGIN
        v_raw_amount :=
            (p_transaction ->> 'a')::numeric / 100;
    EXCEPTION
        WHEN invalid_text_representation
          OR numeric_value_out_of_range
        THEN
            RAISE EXCEPTION
                'INVALID_QUANTITY';
    END;

    v_amount := trunc(v_raw_amount, 6);

    IF v_amount IS NULL OR v_amount <= 0 THEN
        RAISE EXCEPTION
            'INVALID_QUANTITY';
    END IF;

    /*
     * ==========================================================
     * FETCH TRUSTED USERS
     * ==========================================================
     */
    v_sender :=
        public.fetch_user_by_id(p_sender_id);

    v_receiver :=
        public.fetch_user_by_email_or_phone(
            v_receiver_identifier
        );

    v_treasury :=
        public.fetch_country_treasury(v_country_code);

    IF v_sender.id IS NULL THEN
        RAISE EXCEPTION
            'SENDER_NOT_FOUND';
    END IF;

    IF v_receiver.id IS NULL THEN
        RAISE EXCEPTION
            'RECEIVER_NOT_FOUND';
    END IF;

    IF v_treasury.id IS NULL THEN
        RAISE EXCEPTION
            'TREASURY_NOT_FOUND';
    END IF;

    IF v_sender.status IS DISTINCT FROM
       'active'::public."UserStatus"
    THEN
        RAISE EXCEPTION
            'SENDER_NOT_ACTIVE';
    END IF;

    IF v_receiver.status IS DISTINCT FROM
       'active'::public."UserStatus"
    THEN
        RAISE EXCEPTION
            'RECEIVER_NOT_ACTIVE';
    END IF;

    IF v_sender.id = v_receiver.id THEN
        RAISE EXCEPTION
            'OPERATION_NOT_ALLOWED';
    END IF;

    IF lower(btrim(v_sender.country_code))
       IS DISTINCT FROM v_country_code
    THEN
        RAISE EXCEPTION
            'SENDER_COUNTRY_MISMATCH';
    END IF;

    IF lower(btrim(v_receiver.country_code))
       IS DISTINCT FROM v_country_code
    THEN
        RAISE EXCEPTION
            'OPERATION_NOT_ALLOWED';
    END IF;

    IF nullif(btrim(v_sender.wallet_address), '')
       IS NULL
    THEN
        RAISE EXCEPTION
            'SENDER_WALLET_NOT_CONFIGURED';
    END IF;

    IF v_sender.wallet_index IS NULL THEN
        RAISE EXCEPTION
            'SENDER_WALLET_INDEX_NOT_CONFIGURED';
    END IF;

    /*
     * The receiver's blockchain address must exist.
     * The receiver's database wallet does NOT need
     * to exist yet.
     */
    IF nullif(btrim(v_receiver.wallet_address), '')
       IS NULL
    THEN
        RAISE EXCEPTION
            'RECEIVER_WALLET_NOT_CONFIGURED';
    END IF;

    IF nullif(btrim(v_treasury.wallet_address), '')
       IS NULL
    THEN
        RAISE EXCEPTION
            'TREASURY_WALLET_NOT_CONFIGURED';
    END IF;

    /*
     * ==========================================================
     * VALIDATE EXISTING SENDER CUSTOMER GOLD WALLET
     * ==========================================================
     *
     * Wallet owner type is determined by
     * gold_token_transfer, NOT by the user's role.
     *
     * No receiver wallet lookup is performed.
     */
    SELECT w.*
    INTO v_sender_wallet
    FROM public.wallet AS w
    WHERE w.user_id = v_sender.id
      AND w.country_code = v_country_code
      AND w.currency_code = 'gold'
      AND w.blockchain_code = v_blockchain_code
      AND w.owner_type =
          'customer'::public."WalletOwnerType"
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'SENDER_BLOCKCHAIN_WALLET_NOT_FOUND';
    END IF;

    IF NOT v_sender_wallet.is_active THEN
        RAISE EXCEPTION
            'SENDER_WALLET_FROZEN';
    END IF;

    /*
     * ==========================================================
     * FETCH FISCAL PERIOD
     * ==========================================================
     */
    SELECT
        fp.fiscal_year,
        fp.period
    INTO
        v_fiscal_year,
        v_period
    FROM public.fetch_fiscal_period(
        v_country_code
    ) AS fp;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'FISCAL_PERIOD_NOT_FOUND';
    END IF;

    /*
     * ==========================================================
     * FETCH GL MAPPINGS
     * ==========================================================
     */
    SELECT array_agg(
        mapping_record
        ORDER BY mapping_record.component_type
    )
    INTO v_mappings
    FROM public.fetch_gl_mappings(
        'gold_token_transfer'::public."TransactionType"
    ) AS mapping_record;

    IF v_mappings IS NULL
       OR cardinality(v_mappings) = 0
    THEN
        RAISE EXCEPTION
            'GL_MAPPINGS_NOT_FOUND';
    END IF;

    /*
     * ==========================================================
     * BUILD POSTING COMPONENTS
     * ==========================================================
     */
    v_components :=
        public.build_posting_components(
            'gold_token_transfer'::public."TransactionType",
            v_amount,
            v_mappings,
            v_country_code,
            'gold',
            true
        );

    IF v_components IS NULL
       OR cardinality(v_components) = 0
    THEN
        RAISE EXCEPTION
            'POSTING_COMPONENTS_NOT_FOUND';
    END IF;

    /*
     * ==========================================================
     * EXTRACT TRANSACTION FEE
     * ==========================================================
     */
    SELECT greatest(
        coalesce(c.debit_amount, 0),
        coalesce(c.credit_amount, 0)
    )
    INTO v_fee
    FROM unnest(v_components) AS c
    WHERE c.component_type =
        'transaction_fee'::public."ComponentType"
    LIMIT 1;

    v_fee := trunc(coalesce(v_fee, 0), 6);

    IF v_fee < 0 THEN
        RAISE EXCEPTION
            'INVALID_FEE_AMOUNT';
    END IF;

    v_total_amount := v_amount + v_fee;

    /*
     * Only the sender wallet must already exist
     * and have enough GOLD on this blockchain.
     */
    IF v_sender_wallet.balance < v_total_amount THEN
        RAISE EXCEPTION
            'INSUFFICIENT_BALANCE';
    END IF;

    /*
     * ==========================================================
     * ADJUST POSTING COMPONENTS
     * ==========================================================
     *
     * Principal:
     *   debit  = transferred amount
     *   credit = transferred amount + fee
     *
     * Transaction fee:
     *   debit  = fee
     *   credit = zero
     */
    FOREACH v_component IN ARRAY v_components
    LOOP
        v_adjusted_component := v_component;

        IF v_component.component_type =
           'principal'::public."ComponentType"
        THEN
            v_adjusted_component.debit_amount :=
                v_amount;

            v_adjusted_component.credit_amount :=
                v_total_amount;

        ELSIF v_component.component_type =
              'transaction_fee'::public."ComponentType"
        THEN
            v_adjusted_component.debit_amount :=
                v_fee;

            v_adjusted_component.credit_amount :=
                0;
        END IF;

        v_adjusted_components :=
            array_append(
                v_adjusted_components,
                v_adjusted_component
            );
    END LOOP;

    v_components :=
        public.validate_components(
            v_adjusted_components
        );

    IF v_components IS NULL
       OR cardinality(v_components) = 0
    THEN
        RAISE EXCEPTION
            'INVALID_POSTING_COMPONENTS';
    END IF;

    /*
     * ==========================================================
     * DOCUMENT PREFIX
     * ==========================================================
     */
    v_document_prefix :=
        public.fetch_transaction_doc_num_prefix(
            'gold_token_transfer'::public."TransactionType"
        );

    IF nullif(btrim(v_document_prefix), '')
       IS NULL
    THEN
        RAISE EXCEPTION
            'DOCUMENT_PREFIX_NOT_FOUND';
    END IF;

    /*
     * ==========================================================
     * RETURN PREPARED TRANSFER
     * ==========================================================
     */
    RETURN QUERY
    SELECT
        v_sender.id,
        v_sender.wallet_address,
        v_sender.wallet_index::bigint,

        v_receiver.id,
        v_receiver.wallet_address,

        v_treasury.id,
        v_treasury.wallet_address,

        v_country_code,
        v_blockchain_code,

        v_fiscal_year,
        v_period,
        v_document_prefix,

        v_amount::text,
        v_fee::text,
        v_total_amount::text,

        v_mappings,
        v_components;
END;
$function$;
