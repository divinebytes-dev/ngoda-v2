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

    v_spending_usd numeric(20, 2) := 0;
    v_saving_usd numeric(20, 2) := 0;
    v_investment_usd numeric(20, 2) := 0;
    v_borrowing_usd numeric(20, 2) := 0;

    v_metric_value numeric(20, 2) := 0;
    v_inserted boolean := false;
BEGIN

    /*
     * SHOPPER
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
      AND e.activity_type =
          'spending'::public.financial_activity_type;


    /*
     * INVESTOR
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
      AND e.activity_type =
          'investment_buy'::public.financial_activity_type;


    /*
     * BORROWER
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
      AND e.activity_type =
          'loan_disbursement'::public.financial_activity_type;


    /*
     * SAVER
     *
     * Use all-currency period behaviour rows only.
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
      AND fb.scope =
          'period'::public.financial_behavior_scope
      AND fb.currency_code IS NULL;


    /*
     * Evaluate all active badge thresholds.
     */
    FOR v_badge IN

        SELECT
            b.id,
            b.code,
            b.name,
            b.metric,
            b.level,
            b.threshold_usd
        FROM public.financial_badge AS b
        WHERE b.is_active = true
        ORDER BY
            b.metric,
            b.level

    LOOP

        /*
         * Determine the lifetime value for this
         * badge metric.
         */
        CASE v_badge.metric

            WHEN 'spending'::public.financial_badge_metric THEN
                v_metric_value :=
                    v_spending_usd;

            WHEN 'saving'::public.financial_badge_metric THEN
                v_metric_value :=
                    v_saving_usd;

            WHEN 'investment'::public.financial_badge_metric THEN
                v_metric_value :=
                    v_investment_usd;

            WHEN 'borrowing'::public.financial_badge_metric THEN
                v_metric_value :=
                    v_borrowing_usd;

            ELSE
                v_metric_value := 0;

        END CASE;


        /*
         * Badge threshold not reached.
         */
        IF v_metric_value < v_badge.threshold_usd THEN
            CONTINUE;
        END IF;


        /*
         * Award badge.
         *
         * IMPORTANT:
         *
         * Do not use:
         *
         * ON CONFLICT (user_id, badge_id)
         *
         * because badge_id is also an output variable
         * of this PL/pgSQL function.
         *
         * We check explicitly instead.
         */
        IF NOT EXISTS (
            SELECT
                1
            FROM public.user_financial_badge AS ufb
            WHERE ufb.user_id = p_user_id
              AND ufb.badge_id = v_badge.id
        ) THEN

            INSERT INTO public.user_financial_badge (
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
            );

            v_inserted := true;

        ELSE

            v_inserted := false;

        END IF;


        /*
         * Populate return row.
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
            v_inserted;

        RETURN NEXT;

    END LOOP;

    RETURN;

END;
$function$;