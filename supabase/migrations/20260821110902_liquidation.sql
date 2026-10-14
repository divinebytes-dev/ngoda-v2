CREATE OR REPLACE FUNCTION public.update_gold_rate_from_ounce_price(
    p_price_per_ounce numeric
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
declare
    v_grams_per_ounce constant numeric :=
        31.1034768;

    v_price_per_gram numeric;
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

    if p_price_per_ounce is null
       or p_price_per_ounce <= 0
    then
        raise exception
            'INVALID_GOLD_PRICE_PER_OUNCE';
    end if;

    v_price_per_gram :=
        trunc(
            p_price_per_ounce /
            v_grams_per_ounce,
            8
        );

    if v_price_per_gram <= 0 then
        raise exception
            'INVALID_GOLD_PRICE_PER_GRAM';
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
    on conflict (
        code
    )
    do update
    set
        rate_to_usd =
            excluded.rate_to_usd,

        updated_at =
            excluded.updated_at;

    return trim_scale(
        v_price_per_gram
    )::text;
end;
$function$;