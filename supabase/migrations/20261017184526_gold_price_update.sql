CREATE OR REPLACE FUNCTION public.update_gold_rate_from_ounce_price(
    p_price_per_ounce numeric
)
RETURNS numeric
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
declare
    v_price_per_gram numeric(20, 6);
    v_saved_rate numeric;
begin
    if coalesce(auth.role(), '') <> 'service_role' then
        raise exception using
            errcode = '42501',
            message = 'SERVICE_ROLE_REQUIRED';
    end if;

    if p_price_per_ounce is null
       or p_price_per_ounce::text in (
           'NaN',
           'Infinity',
           '-Infinity'
       )
       or p_price_per_ounce <= 0
    then
        raise exception 'INVALID_GOLD_PRICE_PER_OUNCE';
    end if;

    /*
     * Recheck GOLD configuration when saving.
     * Keep it active until this transaction completes.
     */
    perform 1
    from public.supported_currency c
    where c.currency_code = 'gold'
      and c.is_active = true
    for share;

    if not found then
        raise exception 'ACTIVE_GOLD_CURRENCY_NOT_FOUND';
    end if;

    /*
     * Convert USD per troy ounce to USD per gram.
     * Preserve the existing six-decimal truncation.
     */
    v_price_per_gram :=
        trunc(
            p_price_per_ounce / 31.1034768,
            6
        );

    if v_price_per_gram <= 0 then
        raise exception 'INVALID_GOLD_PRICE_PER_GRAM';
    end if;

    insert into public.current_rates (
        code,
        rate_to_usd,
        updated_at
    )
    values (
        'gold',
        v_price_per_gram,
        now()
    )
    on conflict (code)
    do update set
        rate_to_usd = excluded.rate_to_usd,
        updated_at = excluded.updated_at
    returning rate_to_usd
    into v_saved_rate;

    return v_saved_rate;
end;
$function$;


REVOKE ALL ON FUNCTION
    public.fetch_gold_rate_api()
FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION
    public.fetch_gold_rate_api()
TO service_role;


REVOKE ALL ON FUNCTION
    public.update_gold_rate_from_ounce_price(numeric)
FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION
    public.update_gold_rate_from_ounce_price(numeric)
TO service_role;