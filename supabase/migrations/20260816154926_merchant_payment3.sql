CREATE OR REPLACE FUNCTION public.create_my_merchant_payment_state(
    p_transaction jsonb,
    p_approval jsonb
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
declare
    v_payer public.users%rowtype;
    v_merchant public.users%rowtype;

    v_reference text;
    v_merchant_id text;
    v_currency text;
    v_version text;

    v_transaction_id text;
begin
    /*
     * Authenticate the payer.
     */
    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHORIZED';
    end if;

    if p_transaction is null then
        raise exception
            'TRANSACTION_DATA_MISSING';
    end if;

    if p_approval is null then
        raise exception
            'SENDER_APPROVAL_MISSING';
    end if;

    /*
     * Users allowed to make merchant payments.
     */
    if not public.has_role(
        array[
            'customer',
            'vendor',
            'agent'
        ]::text[]
    ) then
        raise exception using
            errcode = '42501',
            message = 'FORBIDDEN';
    end if;

    /*
     * Read the signed transaction fields.
     */
    v_version :=
        nullif(
            btrim(
                p_transaction ->> 'v'
            ),
            ''
        );

    if v_version is distinct from 'v4' then
        raise exception
            'OPERATION_NOT_ALLOWED';
    end if;

    v_reference :=
        nullif(
            btrim(
                p_transaction ->> 'r'
            ),
            ''
        );

    if v_reference is null then
        raise exception
            'REFERENCE_IS_REQUIRED';
    end if;

    /*
     * transaction.s contains the receiving merchant or
     * vendor user ID.
     */
    v_merchant_id :=
        nullif(
            btrim(
                p_transaction ->> 's'
            ),
            ''
        );

    if v_merchant_id is null then
        raise exception
            'MERCHANT_ID_IS_REQUIRED';
    end if;

    v_currency :=
        lower(
            nullif(
                btrim(
                    p_transaction ->> 'c'
                ),
                ''
            )
        );

    if v_currency is null then
        raise exception
            'CURRENCY_IS_REQUIRED';
    end if;

    /*
     * The transaction and approval must describe the same
     * payment.
     */
    if p_transaction ->> 'a'
       is distinct from
       p_approval ->> 'a'
    then
        raise exception
            'AMOUNT_MISMATCH';
    end if;

    if lower(
        p_transaction ->> 'c'
    ) is distinct from lower(
        p_approval ->> 'c'
    ) then
        raise exception
            'CURRENCY_MISMATCH';
    end if;

    if p_transaction ->> 'r'
       is distinct from
       p_approval ->> 'r'
    then
        raise exception
            'REFERENCE_MISMATCH';
    end if;

    /*
     * Fetch the authenticated payer.
     */
    select payer_record.*
    into v_payer
    from public.users payer_record
    where payer_record.id =
          auth.uid()::text
    limit 1;

    if not found then
        raise exception
            'PAYER_NOT_FOUND';
    end if;

    /*
     * Fetch the payment receiver.
     */
    select merchant_record.*
    into v_merchant
    from public.users merchant_record
    where merchant_record.id =
          v_merchant_id
    limit 1;

    if not found then
        raise exception
            'MERCHANT_NOT_FOUND';
    end if;

    /*
     * Validate participant status.
     */
    if v_payer.status <>
       'active'::public."UserStatus"
    then
        raise exception
            'PAYER_NOT_ACTIVE';
    end if;

    if v_merchant.status <>
       'active'::public."UserStatus"
    then
        raise exception
            'MERCHANT_NOT_ACTIVE';
    end if;

    /*
     * Prevent payment to the same user.
     */
    if v_payer.id =
       v_merchant.id
    then
        raise exception
            'OPERATION_NOT_ALLOWED';
    end if;

    /*
     * Both participants must belong to the same country.
     */
    if lower(
        btrim(
            v_payer.country_code
        )
    ) is distinct from lower(
        btrim(
            v_merchant.country_code
        )
    ) then
        raise exception
            'OPERATION_NOT_ALLOWED';
    end if;

    /*
     * Both merchants and vendors may receive merchant
     * payments.
     */
    if not exists (
        select 1
        from public.user_role role_record
        where role_record.id =
              v_merchant.role_id

          and lower(
              role_record.name::text
          ) in (
              'merchant',
              'vendor'
          )
    ) then
        raise exception
            'INVALID_MERCHANT_ROLE';
    end if;

    /*
     * Create the processing transaction state.
     */
    begin
        insert into public.transaction_state (
            reference,
            status,
            transaction_type,
            country_code,
            transaction_data,
            sender_approval,
            created_by,
            user_id
        )
        values (
            v_reference,
            'processing'::public."TransactionStatus",
            'merchant_payment'::public."TransactionType",

            lower(
                btrim(
                    v_payer.country_code
                )
            ),

            p_transaction,
            p_approval,
            v_payer.id,
            v_merchant.id
        )
        returning id::text
        into v_transaction_id;

    exception
        when unique_violation then
            raise exception using
                errcode = '23505',
                message = 'TRANSACTION_REPLAY';
    end;

    if v_transaction_id is null then
        raise exception
            'TRANSACTION_STATE_CREATE_FAILED';
    end if;

    return v_transaction_id;
end;
$function$;