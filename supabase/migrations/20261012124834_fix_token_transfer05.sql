ALTER TABLE public.transaction_state
ADD COLUMN IF NOT EXISTS blockchain_code text;


CREATE OR REPLACE FUNCTION public.create_my_gold_transfer_state(
    p_transaction jsonb,
    p_blockchain_code text
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
    v_sender public.users%rowtype;
    v_receiver public.users%rowtype;

    v_reference text;
    v_receiver_identifier text;
    v_currency text;
    v_version text;
    v_transaction_id text;
    v_blockchain_code text;
BEGIN
    /*
     * ==========================================================
     * AUTHENTICATION
     * ==========================================================
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
     * ==========================================================
     * VALIDATE BLOCKCHAIN
     * ==========================================================
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

    IF NOT EXISTS (
        SELECT 1
        FROM public.supported_blockchain AS b
        WHERE b.code = v_blockchain_code
          AND b.is_active = true
          AND EXISTS (
              SELECT 1
              FROM public.supported_blockchain_network AS n
              WHERE n.blockchain_id = b.id
                AND n.is_active = true
          )
    ) THEN
        RAISE EXCEPTION
            'BLOCKCHAIN_NOT_FOUND_OR_INACTIVE';
    END IF;

    /*
     * ==========================================================
     * VALIDATE SIGNED TRANSACTION VERSION
     * ==========================================================
     */
    v_version :=
        nullif(
            btrim(
                p_transaction ->> 'v'
            ),
            ''
        );

    IF v_version IS DISTINCT FROM 'v6' THEN
        RAISE EXCEPTION
            'OPERATION_NOT_ALLOWED';
    END IF;

    /*
     * ==========================================================
     * VALIDATE REFERENCE
     * ==========================================================
     */
    v_reference :=
        nullif(
            btrim(
                p_transaction ->> 'r'
            ),
            ''
        );

    IF v_reference IS NULL THEN
        RAISE EXCEPTION
            'REFERENCE_IS_REQUIRED';
    END IF;

    /*
     * ==========================================================
     * VALIDATE RECEIVER IDENTIFIER
     * ==========================================================
     */
    v_receiver_identifier :=
        nullif(
            btrim(
                p_transaction ->> 's'
            ),
            ''
        );

    IF v_receiver_identifier IS NULL THEN
        RAISE EXCEPTION
            'RECEIVER_IDENTIFIER_IS_REQUIRED';
    END IF;

    /*
     * ==========================================================
     * VALIDATE CURRENCY
     * ==========================================================
     */
    v_currency :=
        lower(
            nullif(
                btrim(
                    p_transaction ->> 'c'
                ),
                ''
            )
        );

    IF v_currency IS DISTINCT FROM 'gold' THEN
        RAISE EXCEPTION
            'INVALID_GOLD_TRANSFER_CURRENCY';
    END IF;

    /*
     * ==========================================================
     * FETCH AUTHENTICATED SENDER
     * ==========================================================
     */
    SELECT sender_record.*
    INTO v_sender
    FROM public.users AS sender_record
    WHERE sender_record.id =
          auth.uid()::text
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'SENDER_NOT_FOUND';
    END IF;

    IF v_sender.status <>
       'active'::public."UserStatus"
    THEN
        RAISE EXCEPTION
            'SENDER_NOT_ACTIVE';
    END IF;

    /*
     * ==========================================================
     * FETCH RECEIVER
     * ==========================================================
     */
    v_receiver :=
        public.fetch_user_by_email_or_phone(
            v_receiver_identifier
        );

    IF v_receiver.id IS NULL THEN
        RAISE EXCEPTION
            'RECEIVER_NOT_FOUND';
    END IF;

    IF v_receiver.status <>
       'active'::public."UserStatus"
    THEN
        RAISE EXCEPTION
            'RECEIVER_NOT_ACTIVE';
    END IF;

    /*
     * ==========================================================
     * VALIDATE TRANSFER PARTICIPANTS
     * ==========================================================
     */
    IF v_sender.id = v_receiver.id THEN
        RAISE EXCEPTION
            'OPERATION_NOT_ALLOWED';
    END IF;

    IF v_sender.country_code IS DISTINCT FROM
       v_receiver.country_code
    THEN
        RAISE EXCEPTION
            'OPERATION_NOT_ALLOWED';
    END IF;

    IF v_sender.wallet_address IS NULL
       OR btrim(v_sender.wallet_address) = ''
    THEN
        RAISE EXCEPTION
            'SENDER_WALLET_NOT_CONFIGURED';
    END IF;

    IF v_receiver.wallet_address IS NULL
       OR btrim(v_receiver.wallet_address) = ''
    THEN
        RAISE EXCEPTION
            'RECEIVER_WALLET_NOT_CONFIGURED';
    END IF;

    /*
     * ==========================================================
     * VALIDATE SENDER GOLD WALLET ON SELECTED CHAIN
     * ==========================================================
     */
    IF NOT EXISTS (
        SELECT 1
        FROM public.wallet AS w
        WHERE w.user_id = v_sender.id
          AND w.country_code =
              lower(btrim(v_sender.country_code))
          AND w.currency_code = 'gold'
          AND w.blockchain_code = v_blockchain_code
          AND w.owner_type IN (
              'customer'::public."WalletOwnerType",
              'agent'::public."WalletOwnerType",
              'vendor'::public."WalletOwnerType"
          )
    ) THEN
        RAISE EXCEPTION
            'SENDER_BLOCKCHAIN_WALLET_NOT_FOUND';
    END IF;

    /*
     * ==========================================================
     * CREATE TRANSACTION STATE
     * ==========================================================
     *
     * blockchain_code is stored separately from
     * the signed TransactionData.
     *
     * The reference remains globally unique.
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
            'gold_token_transfer'::public."TransactionType",
            lower(btrim(v_sender.country_code)),
            v_blockchain_code,
            p_transaction,
            v_sender.id,
            v_receiver.id
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


DROP FUNCTION IF EXISTS public.create_my_gold_transfer_state(
    jsonb
);

