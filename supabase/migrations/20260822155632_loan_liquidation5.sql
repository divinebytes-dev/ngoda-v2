/*
 * PostgREST cannot safely expose overloaded RPC functions.
 * Remove both earlier signatures and retain one numeric
 * signature only.
 */
DROP FUNCTION IF EXISTS
    public.update_gold_rate_from_ounce_price(text);

DROP FUNCTION IF EXISTS
    public.update_gold_rate_from_ounce_price(numeric);


CREATE FUNCTION public.update_gold_rate_from_ounce_price(
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
