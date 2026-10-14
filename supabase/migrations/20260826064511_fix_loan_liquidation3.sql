/* Canonical Gold-rate support RPCs. */

/*
 * PostgREST cannot safely expose overloaded RPC functions.
 * Remove the obsolete text signature and retain one
 * numeric signature only.
 */
DROP FUNCTION IF EXISTS
    public.update_gold_rate_from_ounce_price(text);

CREATE OR REPLACE FUNCTION public.update_gold_rate_from_ounce_price(
    p_price_per_ounce numeric
)
RETURNS numeric
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
declare
    v_price_per_ounce numeric;
    v_price_per_gram numeric;
    v_saved_rate numeric;
begin
    /*
     * Only the liquidation Edge Function service client
     * may refresh the system Gold rate.
     */
    if coalesce(
        auth.role(),
        ''
    ) <> 'service_role'
    then
        raise exception using
            errcode = '42501',
            message = 'SERVICE_ROLE_REQUIRED';
    end if;

    v_price_per_ounce :=
        p_price_per_ounce;

    if v_price_per_ounce is null
       or v_price_per_ounce <= 0
    then
        raise exception
            'INVALID_GOLD_PRICE_PER_OUNCE';
    end if;

    /*
     * One troy ounce contains 31.1034768 grams.
     * Gold values are truncated to six decimal places.
     */
    v_price_per_gram :=
        trunc(
            v_price_per_ounce /
            31.1034768,
            6
        );

    if v_price_per_gram <= 0 then
        raise exception
            'INVALID_GOLD_PRICE_PER_GRAM';
    end if;

    update public.current_rates
    set
        rate_to_usd =
            v_price_per_gram,

        updated_at =
            now()
    where lower(
        btrim(code)
    ) = 'gold'
    returning rate_to_usd
    into v_saved_rate;

    if not found then
        raise exception
            'CURRENT_RATE_NOT_FOUND_GOLD';
    end if;

    return v_saved_rate;
end;
$function$;


CREATE OR REPLACE FUNCTION public.fetch_gold_rate_api()
RETURNS TABLE(rate_api text)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
begin
    if coalesce(
        auth.role(),
        ''
    ) <> 'service_role'
    then
        raise exception using
            errcode = '42501',
            message = 'SERVICE_ROLE_REQUIRED';
    end if;

    return query
    select
        btrim(
            currency_record.rate_api
        )
    from public.supported_currency
        currency_record
    where lower(
        btrim(
            currency_record.currency_code
        )
    ) = 'gold'

      and currency_record.is_active = true

      and nullif(
          btrim(
              currency_record.rate_api
          ),
          ''
      ) is not null
    limit 1;
end;
$function$;


create or replace function public.fetch_active_operational_countries()
returns table(country_code text)
language plpgsql
stable
security definer
set search_path to ''
as $function$
begin
    if coalesce(auth.role(), '') <> 'service_role' then
        raise exception using
            errcode = '42501',
            message = 'SERVICE_ROLE_REQUIRED';
    end if;

    return query
    select lower(btrim(country_record.country_code))
    from public.operational_country country_record
    where country_record.is_active = true
      and nullif(btrim(country_record.country_code), '') is not null
    order by lower(btrim(country_record.country_code));
end;
$function$;


revoke all on function public.update_gold_rate_from_ounce_price(numeric)
from public, anon, authenticated;
grant execute on function public.update_gold_rate_from_ounce_price(numeric)
to service_role;

revoke all on function public.fetch_gold_rate_api()
from public, anon, authenticated;
grant execute on function public.fetch_gold_rate_api()
to service_role;

revoke all on function public.fetch_active_operational_countries()
from public, anon, authenticated;
grant execute on function public.fetch_active_operational_countries()
to service_role;
