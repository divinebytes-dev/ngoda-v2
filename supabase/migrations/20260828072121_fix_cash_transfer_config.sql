begin;


create or replace function public.fetch_my_cash_transfer_fee_configuration()
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
    v_user public.users%rowtype;
    v_currency record;
    v_rate_to_usd numeric;
    v_points_per_usd bigint;
    v_loyalty_redemption_enabled boolean := false;
    v_currencies jsonb := '[]'::jsonb;
begin
    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHORIZED';
    end if;

    select user_record.*
    into v_user
    from public.users user_record
    join public.user_role role_record
      on role_record.id = user_record.role_id
    where user_record.id = auth.uid()::text
      and user_record.status =
          'active'::public."UserStatus"
      and lower(role_record.name::text) in (
          'customer',
          'agent',
          'vendor'
      )
    limit 1;

    if not found then
        raise exception using
            errcode = '42501',
            message = 'CASH_TRANSFER_NOT_AUTHORIZED';
    end if;

    select exists (
        select 1
        from public.loyalty_account account_record
        where account_record.user_id = v_user.id
          and account_record.is_active = true
    )
    into v_loyalty_redemption_enabled;

    for v_currency in
        select lower(supported_record.currency_code) as currency_code
        from public.country_currencies country_currency_record
        join public.supported_currency supported_record
          on lower(supported_record.currency_code) =
             lower(country_currency_record.currency_code)
        where country_currency_record.country_code =
              v_user.country_code
          and country_currency_record.is_active = true
          and supported_record.is_active = true
          and supported_record.currency_category =
              'fiat'::public."CurrencyCategory"
        order by lower(supported_record.currency_code)
    loop
        if v_currency.currency_code = 'usd' then
            v_rate_to_usd := 1;
        else
            select rate_record.rate_to_usd
            into v_rate_to_usd
            from public.current_rates rate_record
            where lower(btrim(rate_record.code)) =
                  v_currency.currency_code
            limit 1;

            if not found
               or v_rate_to_usd is null
               or v_rate_to_usd <= 0
            then
                raise exception
                    'CURRENT_RATE_NOT_FOUND_%',
                    upper(v_currency.currency_code);
            end if;
        end if;

        v_points_per_usd := null;

        select config_record.points_per_usd
        into v_points_per_usd
        from public.loyalty_redemption_config config_record
        where config_record.transaction_type =
              'cash_transfer'::public."TransactionType"
          and config_record.is_active = true
          and (
              config_record.country_code is null
              or config_record.country_code =
                 lower(v_user.country_code)
          )
          and (
              config_record.currency_code is null
              or config_record.currency_code =
                 v_currency.currency_code
          )
          and (
              config_record.valid_from is null
              or config_record.valid_from <= now()
          )
          and (
              config_record.valid_until is null
              or config_record.valid_until > now()
          )
        order by
            case
                when config_record.country_code is not null
                    then 0
                else 1
            end,
            case
                when config_record.currency_code is not null
                    then 0
                else 1
            end,
            config_record.priority,
            config_record.id
        limit 1;

        v_currencies :=
            v_currencies ||
            jsonb_build_array(
                jsonb_build_object(
                    'currency_code',
                    v_currency.currency_code,
                    'rate_to_usd',
                    trim_scale(v_rate_to_usd)::text,
                    'points_per_usd',
                    v_points_per_usd,
                    'points_payment_available',
                    v_points_per_usd is not null
                )
            );
    end loop;

    return jsonb_build_object(
        'country_code',
        lower(v_user.country_code),
        'loyalty_redemption_enabled',
        v_loyalty_redemption_enabled,
        'currencies',
        v_currencies
    );
end;
$function$;


revoke all on function
    public.fetch_my_cash_transfer_fee_configuration()
from public, anon;

grant execute on function
    public.fetch_my_cash_transfer_fee_configuration()
to authenticated;


notify pgrst, 'reload schema';

commit;

