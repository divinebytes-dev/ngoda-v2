
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
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION USING
            ERRCODE = '42501',
            MESSAGE = 'UNAUTHORIZED';
    END IF;

    IF p_transaction IS NULL THEN
        RAISE EXCEPTION
            'TRANSACTION_DATA_IS_MISSING';
    END IF;

    /*
     * Roles authorize the operation.
     * They do not determine wallet owner_type.
     */
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
     * Blockchain is supplied separately
     * from the signed transaction.
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
                AND n.is_default = true
          )
    ) THEN
        RAISE EXCEPTION
            'BLOCKCHAIN_NOT_FOUND_OR_INACTIVE';
    END IF;

    v_version :=
        nullif(
            btrim(p_transaction ->> 'v'),
            ''
        );

    IF v_version IS DISTINCT FROM 'v6' THEN
        RAISE EXCEPTION
            'OPERATION_NOT_ALLOWED';
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

    v_receiver_identifier :=
        nullif(
            btrim(p_transaction ->> 's'),
            ''
        );

    IF v_receiver_identifier IS NULL THEN
        RAISE EXCEPTION
            'RECEIVER_IDENTIFIER_IS_REQUIRED';
    END IF;

    v_currency :=
        lower(
            nullif(
                btrim(p_transaction ->> 'c'),
                ''
            )
        );

    IF v_currency IS DISTINCT FROM 'gold' THEN
        RAISE EXCEPTION
            'INVALID_GOLD_TRANSFER_CURRENCY';
    END IF;

    /*
     * Fetch authenticated sender.
     */
    SELECT u.*
    INTO v_sender
    FROM public.users AS u
    WHERE u.id = auth.uid()::text
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'SENDER_NOT_FOUND';
    END IF;

    IF v_sender.status IS DISTINCT FROM
       'active'::public."UserStatus"
    THEN
        RAISE EXCEPTION
            'SENDER_NOT_ACTIVE';
    END IF;

    /*
     * Fetch receiver.
     */
    v_receiver :=
        public.fetch_user_by_email_or_phone(
            v_receiver_identifier
        );

    IF v_receiver.id IS NULL THEN
        RAISE EXCEPTION
            'RECEIVER_NOT_FOUND';
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
     * GOLD TOKEN TRANSFER:
     *
     * Sender wallet owner_type = customer.
     * Receiver wallet owner_type = customer.
     *
     * This does not depend on user roles.
     */
    IF NOT EXISTS (
        SELECT 1
        FROM public.wallet AS w
        WHERE w.user_id = v_sender.id
          AND w.country_code =
              lower(btrim(v_sender.country_code))
          AND w.currency_code = 'gold'
          AND w.owner_type =
              'customer'::public."WalletOwnerType"
          AND w.blockchain_code =
              v_blockchain_code
    ) THEN
        RAISE EXCEPTION
            'SENDER_CUSTOMER_GOLD_WALLET_NOT_FOUND';
    END IF;

    /*
     * Store blockchain selection independently
     * of signed TransactionData.
     *
     * Reference uniqueness prevents replay.
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
