CREATE OR REPLACE FUNCTION public.calculate_financial_behavior(
    p_user_id text,
    p_country_code text,
    p_currency_code text,
    p_fiscal_year integer,
    p_period integer
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
    v_country_code text;
    v_currency_code text;

    v_pot public.financial_pot;

    v_period_currency public.financial_behavior;
    v_period_all public.financial_behavior;

    v_year_currency public.financial_behavior;
    v_year_all public.financial_behavior;
BEGIN

    -- ==========================================================
    -- NORMALIZE
    -- ==========================================================

    v_country_code :=
        lower(trim(p_country_code));

    v_currency_code :=
        lower(trim(p_currency_code));


    -- ==========================================================
    -- CURRENT POT DISTRIBUTION
    -- ==========================================================

    SELECT *
    INTO v_pot
    FROM public.calculate_financial_pot_percentages(
        p_user_id,
        v_currency_code,
        p_fiscal_year,
        p_period
    );


    -- ==========================================================
    -- CURRENT PERIOD / CURRENT CURRENCY
    -- ==========================================================

    SELECT *
    INTO v_period_currency
    FROM public.calculate_financial_behavior_snapshot(
        p_user_id,
        v_country_code,
        v_currency_code,
        p_fiscal_year,
        p_period,
        'period'::public.financial_behavior_scope
    );


    -- ==========================================================
    -- CURRENT PERIOD / ALL CURRENCIES
    -- ==========================================================

    SELECT *
    INTO v_period_all
    FROM public.calculate_financial_behavior_snapshot(
        p_user_id,
        v_country_code,
        NULL,
        p_fiscal_year,
        p_period,
        'period'::public.financial_behavior_scope
    );


    -- ==========================================================
    -- FISCAL YEAR / CURRENT CURRENCY
    -- ==========================================================

    SELECT *
    INTO v_year_currency
    FROM public.calculate_financial_behavior_snapshot(
        p_user_id,
        v_country_code,
        v_currency_code,
        p_fiscal_year,
        NULL,
        'fiscal_year'::public.financial_behavior_scope
    );


    -- ==========================================================
    -- FISCAL YEAR / ALL CURRENCIES
    -- ==========================================================

    SELECT *
    INTO v_year_all
    FROM public.calculate_financial_behavior_snapshot(
        p_user_id,
        v_country_code,
        NULL,
        p_fiscal_year,
        NULL,
        'fiscal_year'::public.financial_behavior_scope
    );


    RETURN jsonb_build_object(

        'pot',
            to_jsonb(v_pot),

        'period',
            jsonb_build_object(

                'currency',
                    to_jsonb(v_period_currency),

                'all_currencies',
                    to_jsonb(v_period_all)
            ),

        'fiscal_year',
            jsonb_build_object(

                'currency',
                    to_jsonb(v_year_currency),

                'all_currencies',
                    to_jsonb(v_year_all)
            )
    );

END;
$function$;