CREATE OR REPLACE FUNCTION public.fetch_my_gold_sell_context(
    p_v text,
    p_blockchain_code text
)
RETURNS TABLE(
    seller_id text,
    country_code text,
    wallet_address text,
    wallet_index bigint,
    version_time bigint,
    blockchain_code text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
    v_seller public.users%rowtype;
    v_version_time bigint;
    v_blockchain_code text;
    v_network record;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION USING
            ERRCODE = '42501',
            MESSAGE = 'UNAUTHORIZED';
    END IF;

    IF p_v IS DISTINCT FROM 'v7' THEN
        RAISE EXCEPTION USING
            ERRCODE = '42501',
            MESSAGE = 'OPERATION_NOT_ALLOWED';
    END IF;

    IF NOT public.has_role(
        ARRAY[
            'customer',
            'agent',
            'vendor'
        ]::text[]
    ) THEN
        RAISE EXCEPTION USING
            ERRCODE = '42501',
            MESSAGE = 'FORBIDDEN';
    END IF;

    v_blockchain_code :=
        lower(nullif(btrim(p_blockchain_code), ''));

    IF v_blockchain_code IS NULL THEN
        RAISE EXCEPTION
            'BLOCKCHAIN_CODE_REQUIRED';
    END IF;

    /*
     * Validate the selected blockchain using
     * the existing authenticated RPC.
     */
    SELECT network.*
    INTO v_network
    FROM public.fetch_active_supported_blockchain(
        v_blockchain_code
    ) AS network;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'BLOCKCHAIN_NOT_FOUND_OR_INACTIVE';
    END IF;

    SELECT user_record.*
    INTO v_seller
    FROM public.users AS user_record
    WHERE user_record.id = auth.uid()::text
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'SELLER_NOT_FOUND';
    END IF;

    IF v_seller.status <>
       'active'::public."UserStatus"
    THEN
        RAISE EXCEPTION
            'SELLER_NOT_ACTIVE';
    END IF;

    IF v_seller.country_code IS NULL
       OR btrim(v_seller.country_code) = ''
    THEN
        RAISE EXCEPTION
            'USER_COUNTRY_NOT_CONFIGURED';
    END IF;

    IF v_seller.wallet_address IS NULL
       OR btrim(v_seller.wallet_address) = ''
    THEN
        RAISE EXCEPTION
            'USER_WALLET_NOT_CONFIGURED';
    END IF;

    /*
     * Wallet index zero is valid.
     */
    IF v_seller.wallet_index IS NULL THEN
        RAISE EXCEPTION
            'USER_WALLET_INDEX_NOT_CONFIGURED';
    END IF;

    SELECT public.get_transaction_v(p_v)::bigint
    INTO v_version_time;

    IF v_version_time IS NULL
       OR v_version_time <= 0
    THEN
        RAISE EXCEPTION
            'INVALID_TRANSACTION_VERSION';
    END IF;

    RETURN QUERY
    SELECT
        v_seller.id,
        lower(btrim(v_seller.country_code)),
        v_seller.wallet_address,
        v_seller.wallet_index::bigint,
        v_version_time,
        v_blockchain_code;
END;
$function$;


CREATE OR REPLACE FUNCTION public.create_my_gold_sell_state(
    p_transaction jsonb,
    p_blockchain_code text
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
    v_seller public.users%rowtype;

    v_reference text;
    v_version text;
    v_input_currency text;
    v_blockchain_code text;
    v_transaction_id text;

    v_network record;
BEGIN
    /*
     * Authentication.
     */
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION USING
            ERRCODE = '42501',
            MESSAGE = 'UNAUTHORIZED';
    END IF;

    IF p_transaction IS NULL THEN
        RAISE EXCEPTION
            'TRANSACTION_DATA_IS_MISSING';
    END IF;

    IF NOT public.has_role(
        ARRAY[
            'customer',
            'agent',
            'vendor'
        ]::text[]
    ) THEN
        RAISE EXCEPTION USING
            ERRCODE = '42501',
            MESSAGE = 'FORBIDDEN';
    END IF;

    /*
     * Validate transaction version.
     */
    v_version :=
        nullif(
            btrim(p_transaction ->> 'v'),
            ''
        );

    IF v_version IS DISTINCT FROM 'v7' THEN
        RAISE EXCEPTION
            'OPERATION_NOT_ALLOWED';
    END IF;

    /*
     * Validate reference.
     */
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
     * Validate transaction currency.
     */
    v_input_currency :=
        lower(
            nullif(
                btrim(p_transaction ->> 'c'),
                ''
            )
        );

    IF v_input_currency IS NULL THEN
        RAISE EXCEPTION
            'CURRENCY_IS_REQUIRED';
    END IF;

    IF v_input_currency NOT IN (
        'usd',
        'gold'
    ) THEN
        RAISE EXCEPTION
            'UNSUPPORTED_GOLD_SELL_CURRENCY';
    END IF;

    /*
     * Validate blockchain code.
     */
    v_blockchain_code :=
        lower(
            nullif(
                btrim(p_blockchain_code),
                ''
            )
        );

    IF v_blockchain_code IS NULL THEN
        RAISE EXCEPTION
            'BLOCKCHAIN_CODE_REQUIRED';
    END IF;

    /*
     * Verify active blockchain configuration.
     */
    SELECT network.*
    INTO v_network
    FROM public.fetch_active_supported_blockchain(
        v_blockchain_code
    ) AS network;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'BLOCKCHAIN_NOT_FOUND_OR_INACTIVE';
    END IF;

    /*
     * Fetch authenticated seller.
     */
    SELECT user_record.*
    INTO v_seller
    FROM public.users AS user_record
    WHERE user_record.id = auth.uid()::text
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'SELLER_NOT_FOUND';
    END IF;

    IF v_seller.status <>
       'active'::public."UserStatus"
    THEN
        RAISE EXCEPTION
            'SELLER_NOT_ACTIVE';
    END IF;

    IF v_seller.country_code IS NULL
       OR btrim(v_seller.country_code) = ''
    THEN
        RAISE EXCEPTION
            'USER_COUNTRY_NOT_CONFIGURED';
    END IF;

    IF v_seller.wallet_address IS NULL
       OR btrim(v_seller.wallet_address) = ''
    THEN
        RAISE EXCEPTION
            'SELLER_WALLET_NOT_CONFIGURED';
    END IF;

    IF v_seller.wallet_index IS NULL THEN
        RAISE EXCEPTION
            'SELLER_WALLET_INDEX_NOT_CONFIGURED';
    END IF;

    /*
     * Create processing state.
     *
     * Store the selected blockchain separately
     * from the original signed transaction.
     */
    BEGIN
        INSERT INTO public.transaction_state (
            reference,
            status,
            transaction_type,
            country_code,
            blockchain_code,
            transaction_data,
            created_by,
            user_id
        )
        VALUES (
            v_reference,
            'processing'::public."TransactionStatus",
            'gold_token_sell'::public."TransactionType",
            lower(btrim(v_seller.country_code)),
            v_blockchain_code,
            p_transaction,
            v_seller.id,
            v_seller.id
        )
        RETURNING id::text
        INTO v_transaction_id;

    EXCEPTION
        WHEN unique_violation THEN
            RAISE EXCEPTION USING
                ERRCODE = '23505',
                MESSAGE = 'TRANSACTION_REPLAY';
    END;

    IF v_transaction_id IS NULL THEN
        RAISE EXCEPTION
            'TRANSACTION_STATE_CREATE_FAILED';
    END IF;

    RETURN v_transaction_id;
END;
$function$;


DROP FUNCTION IF EXISTS public.fetch_my_gold_sell_context(
    text
);

DROP FUNCTION IF EXISTS public.create_my_gold_sell_state(
    jsonb
);