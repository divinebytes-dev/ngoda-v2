DROP FUNCTION IF EXISTS public.complete_my_voucher_payment(
    jsonb,
    jsonb,
    text,
    text
);


CREATE FUNCTION public.complete_my_voucher_payment(
    p_transaction jsonb,
    p_voucher jsonb,
    p_transaction_state_id text,
    p_ip_address text DEFAULT NULL::text
)
RETURNS TABLE(
    success boolean,
    reference text,
    customer_id text,
    gross_amount text,
    fee text,
    currency text,
    voucher_remaining_balance text,
    notification_id text,
    device_tokens text[],
    push_title text,
    push_body text,
    push_reference text,

    /*
     * USD equivalent of the committed voucher purchase amount.
     *
     * Appended to preserve the existing return-field order.
     */
    gross_amount_usd text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
declare
    v_user
        public.users%rowtype;

begin
    /*
     * ========================================================
     * AUTHORIZE MERCHANT / VENDOR
     * ========================================================
     */
    if auth.uid() is null then
        raise exception using
            errcode =
                '42501',

            message =
                'UNAUTHORIZED';
    end if;


    if not public.has_role(
        array[
            'merchant',
            'vendor'
        ]::text[]
    ) then
        raise exception using
            errcode =
                '42501',

            message =
                'FORBIDDEN';
    end if;


    /*
     * ========================================================
     * FETCH AUTHENTICATED MERCHANT
     * ========================================================
     */
    select
        user_record.*
    into
        v_user
    from public.users
        user_record
    where user_record.id =
          auth.uid()::text
    limit 1;


    if not found then
        raise exception
            'MERCHANT_NOT_FOUND';
    end if;


    if v_user.status <>
       'active'::public."UserStatus"
    then
        raise exception
            'MERCHANT_NOT_ACTIVE';
    end if;


    if v_user.country_code is null
       or btrim(
           v_user.country_code
       ) = ''
    then
        raise exception
            'MERCHANT_COUNTRY_NOT_CONFIGURED';
    end if;


    /*
     * ========================================================
     * COMPLETE VOUCHER PAYMENT
     * ========================================================
     *
     * The underlying function owns all pricing, currency
     * conversion, voucher accounting and financial posting.
     *
     * It must return gross_amount_usd as the final appended
     * result field.
     */
    return query
    select
        payment_result.success,
        payment_result.reference,
        payment_result.customer_id,
        payment_result.gross_amount,
        payment_result.fee,
        payment_result.currency,
        payment_result.voucher_remaining_balance,
        payment_result.notification_id,
        payment_result.device_tokens,
        payment_result.push_title,
        payment_result.push_body,
        payment_result.push_reference,
        payment_result.gross_amount_usd

    from public.complete_voucher_payment(
        p_merchant_id =>
            v_user.id,

        p_transaction =>
            p_transaction,

        p_voucher =>
            p_voucher,

        p_country_code =>
            v_user.country_code,

        p_transaction_state_id =>
            p_transaction_state_id,

        p_ip_address =>
            p_ip_address
    ) as payment_result;

end;
$function$;