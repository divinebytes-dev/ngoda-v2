CREATE OR REPLACE FUNCTION public.evaluate_financial_badges(
    p_user_id text,
    p_country_code text,
    p_fiscal_year integer,
    p_period integer
)
RETURNS TABLE (
    badge_id uuid,
    badge_code text,
    badge_name text,
    metric public.financial_badge_metric,
    achieved_value_usd numeric,
    newly_awarded boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_badge record;

    v_spending_usd numeric := 0;
    v_saving_usd numeric := 0;
    v_investment_usd numeric := 0;
    v_borrowing_usd numeric := 0;

    v_metric_value numeric := 0;
    v_newly_awarded boolean := false;
BEGIN

    /*
     * Shopper lifetime activity.
     */
    SELECT
        COALESCE(
            SUM(e.amount_usd),
            0
        )
    INTO
        v_spending_usd
    FROM public.financial_pot_event AS e
    WHERE e.user_id = p_user_id
      AND e.activity_type = 'spending';


    /*
     * Investor lifetime activity.
     */
    SELECT
        COALESCE(
            SUM(e.amount_usd),
            0
        )
    INTO
        v_investment_usd
    FROM public.financial_pot_event AS e
    WHERE e.user_id = p_user_id
      AND e.activity_type = 'investment_buy';


    /*
     * Borrower lifetime activity.
     */
    SELECT
        COALESCE(
            SUM(e.amount_usd),
            0
        )
    INTO
        v_borrowing_usd
    FROM public.financial_pot_event AS e
    WHERE e.user_id = p_user_id
      AND e.activity_type = 'loan_disbursement';


    /*
     * Saver lifetime qualifying amount.
     *
     * Use all-currency period behaviour snapshots so we do not
     * count the same period once per currency.
     */
    SELECT
        COALESCE(
            SUM(fb.saving_amount_usd),
            0
        )
    INTO
        v_saving_usd
    FROM public.financial_behavior AS fb
    WHERE fb.user_id = p_user_id
      AND fb.scope = 'period'
      AND fb.currency_code IS NULL;


    /*
     * Evaluate configured badges.
     */
    FOR v_badge IN

        SELECT
            b.id,
            b.code,
            b.name,
            b.metric,
            b.threshold_usd
        FROM public.financial_badge AS b
        WHERE b.is_active = true
        ORDER BY
            b.metric,
            b.level

    LOOP

        CASE v_badge.metric

            WHEN 'spending' THEN
                v_metric_value := v_spending_usd;

            WHEN 'saving' THEN
                v_metric_value := v_saving_usd;

            WHEN 'investment' THEN
                v_metric_value := v_investment_usd;

            WHEN 'borrowing' THEN
                v_metric_value := v_borrowing_usd;

            ELSE
                v_metric_value := 0;

        END CASE;


        /*
         * Threshold not yet reached.
         */
        IF v_metric_value < v_badge.threshold_usd THEN
            CONTINUE;
        END IF;


        /*
         * Award permanently.
         */
        INSERT INTO public.user_financial_badge AS ufb (
            user_id,
            badge_id,
            achieved_value_usd,
            fiscal_year,
            period,
            achieved_at,
            created_at
        )
        VALUES (
            p_user_id,
            v_badge.id,
            v_metric_value,
            p_fiscal_year,
            p_period,
            now(),
            now()
        )
        ON CONFLICT (
            user_id,
            badge_id
        )
        DO NOTHING;


        /*
         * Determine whether this execution inserted it.
         */
        v_newly_awarded := FOUND;


        /*
         * Explicitly assign the RETURNS TABLE columns.
         *
         * Notice we never use an unqualified table badge_id.
         */
        badge_id :=
            v_badge.id;

        badge_code :=
            v_badge.code;

        badge_name :=
            v_badge.name;

        metric :=
            v_badge.metric;

        achieved_value_usd :=
            v_metric_value;

        newly_awarded :=
            v_newly_awarded;

        RETURN NEXT;

    END LOOP;

    RETURN;

END;
$function$;