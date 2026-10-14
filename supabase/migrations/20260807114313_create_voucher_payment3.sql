/*
 * ============================================================
 * AUTHENTICATED VOUCHER PAYMENT WRAPPER
 * ============================================================
 */

create or replace function public.complete_my_voucher_payment(
    p_transaction jsonb,
    p_voucher jsonb,
    p_transaction_state_id text,
    p_ip_address text default null
)
returns table (
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
    push_reference text
)
language plpgsql
security definer
set search_path to ''
as $function$
declare
    v_user public.users%rowtype;
begin
    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHORIZED';
    end if;

    if not public.has_role(
        array[
            'merchant',
            'vendor'
        ]::text[]
    ) then
        raise exception using
            errcode = '42501',
            message = 'FORBIDDEN';
    end if;

    select user_record.*
    into v_user
    from public.users user_record
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
       or btrim(v_user.country_code) = ''
    then
        raise exception
            'MERCHANT_COUNTRY_NOT_CONFIGURED';
    end if;

    return query
    select *
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
    );
end;
$function$;


revoke all on function
    public.complete_my_voucher_payment(
        jsonb,
        jsonb,
        text,
        text
    )
from public;

revoke execute on function
    public.complete_my_voucher_payment(
        jsonb,
        jsonb,
        text,
        text
    )
from anon;

grant execute on function
    public.complete_my_voucher_payment(
        jsonb,
        jsonb,
        text,
        text
    )
to authenticated;