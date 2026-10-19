CREATE OR REPLACE FUNCTION public.fetch_fiat_price_update_currencies()
RETURNS TABLE (
    currency_code text,
    rate_api text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
begin
    if coalesce(auth.role(), '') <> 'service_role' then
        raise exception using
            errcode = '42501',
            message = 'SERVICE_ROLE_REQUIRED';
    end if;

    /*
     * USD is the base currency.
     * Initialize it without calling an external API.
     */
    if exists (
        select 1
        from public.supported_currency c
        where c.currency_code = 'usd'
          and c.is_active = true
          and c.currency_category = 'fiat'
    ) then
        insert into public.current_rates (
            code,
            rate_to_usd,
            updated_at
        )
        values (
            'usd',
            1,
            now()
        )
        on conflict (code)
        do update set
            rate_to_usd = 1,
            updated_at = now();
    end if;

    return query
    select
        c.currency_code,
        c.rate_api
    from public.supported_currency c
    where c.is_active = true
      and c.currency_category = 'fiat'
      and c.currency_code <> 'usd'
    order by c.currency_code;
end;
$function$;


CREATE OR REPLACE FUNCTION public.upsert_fiat_currency_rate(
    p_currency_code text,
    p_rate_to_usd numeric
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
declare
    v_currency_code text;
    v_rate numeric(20, 6);
begin
    if coalesce(auth.role(), '') <> 'service_role' then
        raise exception using
            errcode = '42501',
            message = 'SERVICE_ROLE_REQUIRED';
    end if;

    v_currency_code :=
        nullif(lower(btrim(p_currency_code)), '');

    if v_currency_code is null then
        raise exception 'CURRENCY_CODE_REQUIRED';
    end if;

    if p_rate_to_usd is null
       or p_rate_to_usd::text in (
           'NaN',
           'Infinity',
           '-Infinity'
       )
       or p_rate_to_usd <= 0
    then
        raise exception 'INVALID_CURRENCY_RATE';
    end if;

    if v_currency_code = 'usd' then
        raise exception 'USD_RATE_MANAGED_AS_BASE_CURRENCY';
    end if;

    /*
     * Revalidate when writing: configuration could have
     * changed after the Edge function fetched its list.
     *
     * Hold the row lock until this transaction completes.
     */
    perform 1
    from public.supported_currency c
    where c.currency_code = v_currency_code
      and c.is_active = true
      and c.currency_category = 'fiat'
    for share;

    if not found then
        raise exception 'ACTIVE_FIAT_CURRENCY_NOT_FOUND';
    end if;

    v_rate := p_rate_to_usd;

    if v_rate <= 0 then
        raise exception 'CURRENCY_RATE_BELOW_SUPPORTED_PRECISION';
    end if;

    insert into public.current_rates (
        code,
        rate_to_usd,
        updated_at
    )
    values (
        v_currency_code,
        v_rate,
        now()
    )
    on conflict (code)
    do update set
        rate_to_usd = excluded.rate_to_usd,
        updated_at = excluded.updated_at;

    return jsonb_build_object(
        'code', v_currency_code,
        'rate_to_usd', v_rate
    );
end;
$function$;


REVOKE ALL ON FUNCTION
    public.fetch_fiat_price_update_currencies()
FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION
    public.fetch_fiat_price_update_currencies()
TO service_role;


REVOKE ALL ON FUNCTION
    public.upsert_fiat_currency_rate(text, numeric)
FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION
    public.upsert_fiat_currency_rate(text, numeric)
TO service_role;