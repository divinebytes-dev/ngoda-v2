CREATE OR REPLACE FUNCTION public.get_my_financial_summary()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
    v_user_id text;
    v_country_code text;

    v_fiscal_year integer;
    v_period integer;

    v_currencies jsonb;
    v_money_by_currency jsonb;
    v_money_in jsonb;
    v_distribution jsonb;
    v_gold jsonb;

    -- ==========================================================
    -- FISCAL YEAR BEHAVIOR
    -- ==========================================================

    v_behavior public.financial_behavior_type :=
        'neutral'::public.financial_behavior_type;

    v_shopper_score_percentage numeric := 0;
    v_saver_score_percentage numeric := 0;
    v_investor_score_percentage numeric := 0;
    v_borrower_score_percentage numeric := 0;

    -- ==========================================================
    -- CURRENT PERIOD BEHAVIOR
    -- ==========================================================

    v_current_period_behavior public.financial_behavior_type :=
        'neutral'::public.financial_behavior_type;

    v_current_period_shopper_score_percentage numeric := 0;
    v_current_period_saver_score_percentage numeric := 0;
    v_current_period_investor_score_percentage numeric := 0;
    v_current_period_borrower_score_percentage numeric := 0;

BEGIN

    -- ==========================================================
    -- AUTHENTICATION
    -- ==========================================================

    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION USING
            ERRCODE = '42501',
            MESSAGE = 'UNAUTHORIZED';
    END IF;


    -- ==========================================================
    -- AUTHORIZED USER + COUNTRY
    -- ==========================================================

    SELECT
        u.id,
        lower(u.country_code)
    INTO
        v_user_id,
        v_country_code
    FROM public.users AS u

    JOIN public.user_role AS r
        ON r.id = u.role_id

    WHERE u.id = auth.uid()::text

      AND u.status =
          'active'::public."UserStatus"

      AND lower(r.name::text) IN (
          'customer',
          'vendor',
          'agent'
      )

    LIMIT 1;


    IF NOT FOUND THEN
        RAISE EXCEPTION USING
            ERRCODE = '42501',
            MESSAGE =
                'FINANCIAL_BEHAVIOUR_NOT_AUTHORIZED';
    END IF;


    IF v_country_code IS NULL
       OR trim(v_country_code) = ''
    THEN
        RAISE EXCEPTION USING
            ERRCODE = 'P0001',
            MESSAGE =
                'USER_COUNTRY_NOT_FOUND';
    END IF;


    -- ==========================================================
    -- CURRENT FISCAL PERIOD
    -- ==========================================================

    SELECT
        fiscal_period.fiscal_year,
        fiscal_period.period
    INTO
        v_fiscal_year,
        v_period
    FROM public.fetch_fiscal_period(
        v_country_code
    ) AS fiscal_period;


    IF NOT FOUND
       OR v_fiscal_year IS NULL
       OR v_period IS NULL
    THEN
        RAISE EXCEPTION USING
            ERRCODE = 'P0001',
            MESSAGE =
                'FISCAL_PERIOD_NOT_FOUND';
    END IF;


    -- ==========================================================
    -- FISCAL YEAR CONSOLIDATED BEHAVIOR
    -- ==========================================================

    SELECT
        fb.behavior,

        COALESCE(
            fb.shopper_score_percentage,
            0
        ),

        COALESCE(
            fb.saver_score_percentage,
            0
        ),

        COALESCE(
            fb.investor_score_percentage,
            0
        ),

        COALESCE(
            fb.borrower_score_percentage,
            0
        )

    INTO
        v_behavior,
        v_shopper_score_percentage,
        v_saver_score_percentage,
        v_investor_score_percentage,
        v_borrower_score_percentage

    FROM public.financial_behavior AS fb

    WHERE fb.user_id =
          v_user_id

      AND fb.country_code =
          v_country_code

      AND fb.fiscal_year =
          v_fiscal_year

      AND fb.scope =
          'fiscal_year'::public.financial_behavior_scope

      AND fb.period IS NULL

      AND fb.currency_code IS NULL

    LIMIT 1;


    IF NOT FOUND THEN

        v_behavior :=
            'neutral'::public.financial_behavior_type;

        v_shopper_score_percentage := 0;
        v_saver_score_percentage := 0;
        v_investor_score_percentage := 0;
        v_borrower_score_percentage := 0;

    END IF;


    -- ==========================================================
    -- CURRENT PERIOD CONSOLIDATED BEHAVIOR
    -- ==========================================================

    SELECT
        fb.behavior,

        COALESCE(
            fb.shopper_score_percentage,
            0
        ),

        COALESCE(
            fb.saver_score_percentage,
            0
        ),

        COALESCE(
            fb.investor_score_percentage,
            0
        ),

        COALESCE(
            fb.borrower_score_percentage,
            0
        )

    INTO
        v_current_period_behavior,
        v_current_period_shopper_score_percentage,
        v_current_period_saver_score_percentage,
        v_current_period_investor_score_percentage,
        v_current_period_borrower_score_percentage

    FROM public.financial_behavior AS fb

    WHERE fb.user_id =
          v_user_id

      AND fb.country_code =
          v_country_code

      AND fb.fiscal_year =
          v_fiscal_year

      AND fb.period =
          v_period

      AND fb.scope =
          'period'::public.financial_behavior_scope

      AND fb.currency_code IS NULL

    LIMIT 1;


    IF NOT FOUND THEN

        v_current_period_behavior :=
            'neutral'::public.financial_behavior_type;

        v_current_period_shopper_score_percentage := 0;
        v_current_period_saver_score_percentage := 0;
        v_current_period_investor_score_percentage := 0;
        v_current_period_borrower_score_percentage := 0;

    END IF;


    -- ==========================================================
    -- FY-TO-DATE MONEY BY CURRENCY
    --
    -- financial_pot is the reporting source of truth.
    --
    -- Period flows are summed.
    --
    -- Savings B/F is taken ONLY from the first period.
    -- Closing savings is taken ONLY from the latest period.
    -- ==========================================================

    WITH pot_ranked AS (

        SELECT
            fp.*,

            ROW_NUMBER() OVER (
                PARTITION BY fp.currency_code
                ORDER BY fp.period ASC
            ) AS first_period_row,

            ROW_NUMBER() OVER (
                PARTITION BY fp.currency_code
                ORDER BY fp.period DESC
            ) AS last_period_row

        FROM public.financial_pot AS fp

        WHERE fp.user_id =
              v_user_id

          AND fp.country_code =
              v_country_code

          AND fp.fiscal_year =
              v_fiscal_year

          AND fp.period <=
              v_period
    ),

    currency_money AS (

        SELECT
            pr.currency_code,

            -- --------------------------------------------------
            -- POSITION: FIRST PERIOD ONLY
            -- --------------------------------------------------

            COALESCE(
                MAX(pr.opening_savings)
                FILTER (
                    WHERE pr.first_period_row = 1
                ),
                0
            ) AS savings_brought_forward,

            COALESCE(
                MAX(pr.opening_savings_usd)
                FILTER (
                    WHERE pr.first_period_row = 1
                ),
                0
            ) AS savings_brought_forward_usd,

            -- --------------------------------------------------
            -- MONEY IN FLOWS: SUM ALL PERIODS
            -- --------------------------------------------------

            COALESCE(
                SUM(pr.cash_in_amount),
                0
            ) AS cash_in,

            COALESCE(
                SUM(pr.cash_in_amount_usd),
                0
            ) AS cash_in_usd,

            COALESCE(
                SUM(pr.transfer_in_amount),
                0
            ) AS transfer_in,

            COALESCE(
                SUM(pr.transfer_in_amount_usd),
                0
            ) AS transfer_in_usd,

            COALESCE(
                SUM(pr.loan_disbursed_amount),
                0
            ) AS loan_disbursement,

            COALESCE(
                SUM(pr.loan_disbursed_amount_usd),
                0
            ) AS loan_disbursement_usd,

            COALESCE(
                SUM(pr.investment_proceeds_amount),
                0
            ) AS investment_proceeds,

            COALESCE(
                SUM(pr.investment_proceeds_amount_usd),
                0
            ) AS investment_proceeds_usd,

            -- --------------------------------------------------
            -- DISTRIBUTION FLOWS: SUM ALL PERIODS
            -- --------------------------------------------------

            COALESCE(
                SUM(pr.withdrawal_cash_amount),
                0
            ) AS withdrawal,

            COALESCE(
                SUM(pr.withdrawal_cash_amount_usd),
                0
            ) AS withdrawal_usd,

            COALESCE(
                SUM(pr.spending_cash_amount),
                0
            ) AS spending,

            COALESCE(
                SUM(pr.spending_cash_amount_usd),
                0
            ) AS spending_usd,

            COALESCE(
                SUM(pr.investment_cash_amount),
                0
            ) AS investment,

            COALESCE(
                SUM(pr.investment_cash_amount_usd),
                0
            ) AS investment_usd,

            COALESCE(
                SUM(pr.repayment_cash_amount),
                0
            ) AS repayment,

            COALESCE(
                SUM(pr.repayment_cash_amount_usd),
                0
            ) AS repayment_usd,

            -- --------------------------------------------------
            -- POSITION: LATEST PERIOD ONLY
            -- --------------------------------------------------

            COALESCE(
                MAX(pr.closing_savings)
                FILTER (
                    WHERE pr.last_period_row = 1
                ),
                0
            ) AS savings,

            COALESCE(
                MAX(pr.closing_savings_usd)
                FILTER (
                    WHERE pr.last_period_row = 1
                ),
                0
            ) AS savings_usd

        FROM pot_ranked AS pr

        GROUP BY
            pr.currency_code
    ),

    currency_totals AS (

        SELECT
            cm.*,

            (
                  cm.savings_brought_forward
                + cm.cash_in
                + cm.transfer_in
                + cm.loan_disbursement
                + cm.investment_proceeds
            ) AS available_money,

            (
                  cm.savings_brought_forward_usd
                + cm.cash_in_usd
                + cm.transfer_in_usd
                + cm.loan_disbursement_usd
                + cm.investment_proceeds_usd
            ) AS available_money_usd,

            (
                  cm.withdrawal
                + cm.spending
                + cm.investment
                + cm.repayment
                + cm.savings
            ) AS distribution_total,

            (
                  cm.withdrawal_usd
                + cm.spending_usd
                + cm.investment_usd
                + cm.repayment_usd
                + cm.savings_usd
            ) AS distribution_total_usd

        FROM currency_money AS cm
    )

    SELECT
        COALESCE(
            jsonb_agg(
                jsonb_build_object(

                    'currency_code',
                        ct.currency_code,

                    'money_in',
                        jsonb_build_object(

                            'savings_brought_forward',
                                ct.savings_brought_forward,

                            'savings_brought_forward_usd',
                                ct.savings_brought_forward_usd,

                            'cash_in',
                                ct.cash_in,

                            'cash_in_usd',
                                ct.cash_in_usd,

                            'transfer_in',
                                ct.transfer_in,

                            'transfer_in_usd',
                                ct.transfer_in_usd,

                            'loan_disbursement',
                                ct.loan_disbursement,

                            'loan_disbursement_usd',
                                ct.loan_disbursement_usd,

                            'investment_proceeds',
                                ct.investment_proceeds,

                            'investment_proceeds_usd',
                                ct.investment_proceeds_usd,

                            'total',
                                ct.available_money,

                            'total_usd',
                                ct.available_money_usd
                        ),

                    'distribution',
                        jsonb_build_object(

                            'withdrawal',
                                ct.withdrawal,

                            'withdrawal_usd',
                                ct.withdrawal_usd,

                            'spending',
                                ct.spending,

                            'spending_usd',
                                ct.spending_usd,

                            'investment',
                                ct.investment,

                            'investment_usd',
                                ct.investment_usd,

                            'repayment',
                                ct.repayment,

                            'repayment_usd',
                                ct.repayment_usd,

                            'savings',
                                ct.savings,

                            'savings_usd',
                                ct.savings_usd,

                            'total',
                                ct.distribution_total,

                            'total_usd',
                                ct.distribution_total_usd
                        )
                )
                ORDER BY
                    ct.currency_code
            ),
            '[]'::jsonb
        )

    INTO
        v_money_by_currency

    FROM currency_totals AS ct;


    -- ==========================================================
    -- CONSOLIDATED FY-TO-DATE MONEY IN
    --
    -- Currency values have already been consolidated from
    -- financial_pot. We only consolidate currencies into USD.
    -- ==========================================================

    WITH source AS (

        SELECT
            item

        FROM jsonb_array_elements(
            v_money_by_currency
        ) AS item
    ),

    totals AS (

        SELECT
            COALESCE(
                SUM(
                    (
                        item
                        -> 'money_in'
                        ->> 'savings_brought_forward_usd'
                    )::numeric
                ),
                0
            ) AS savings_brought_forward_usd,

            COALESCE(
                SUM(
                    (
                        item
                        -> 'money_in'
                        ->> 'cash_in_usd'
                    )::numeric
                ),
                0
            ) AS cash_in_usd,

            COALESCE(
                SUM(
                    (
                        item
                        -> 'money_in'
                        ->> 'transfer_in_usd'
                    )::numeric
                ),
                0
            ) AS transfer_in_usd,

            COALESCE(
                SUM(
                    (
                        item
                        -> 'money_in'
                        ->> 'loan_disbursement_usd'
                    )::numeric
                ),
                0
            ) AS loan_disbursement_usd,

            COALESCE(
                SUM(
                    (
                        item
                        -> 'money_in'
                        ->> 'investment_proceeds_usd'
                    )::numeric
                ),
                0
            ) AS investment_proceeds_usd

        FROM source
    )

    SELECT
        jsonb_build_object(

            'savings_brought_forward_usd',
                t.savings_brought_forward_usd,

            'cash_in_usd',
                t.cash_in_usd,

            'transfer_in_usd',
                t.transfer_in_usd,

            'loan_disbursement_usd',
                t.loan_disbursement_usd,

            'investment_proceeds_usd',
                t.investment_proceeds_usd,

            'total_usd',
                  t.savings_brought_forward_usd
                + t.cash_in_usd
                + t.transfer_in_usd
                + t.loan_disbursement_usd
                + t.investment_proceeds_usd
        )

    INTO
        v_money_in

    FROM totals AS t;


    -- ==========================================================
    -- CONSOLIDATED FY-TO-DATE DISTRIBUTION
    -- ==========================================================

    WITH source AS (

        SELECT
            item

        FROM jsonb_array_elements(
            v_money_by_currency
        ) AS item
    ),

    totals AS (

        SELECT
            COALESCE(
                SUM(
                    (
                        item
                        -> 'distribution'
                        ->> 'withdrawal_usd'
                    )::numeric
                ),
                0
            ) AS withdrawal_usd,

            COALESCE(
                SUM(
                    (
                        item
                        -> 'distribution'
                        ->> 'spending_usd'
                    )::numeric
                ),
                0
            ) AS spending_usd,

            COALESCE(
                SUM(
                    (
                        item
                        -> 'distribution'
                        ->> 'investment_usd'
                    )::numeric
                ),
                0
            ) AS investment_usd,

            COALESCE(
                SUM(
                    (
                        item
                        -> 'distribution'
                        ->> 'repayment_usd'
                    )::numeric
                ),
                0
            ) AS repayment_usd,

            COALESCE(
                SUM(
                    (
                        item
                        -> 'distribution'
                        ->> 'savings_usd'
                    )::numeric
                ),
                0
            ) AS savings_usd

        FROM source
    )

    SELECT
        jsonb_build_object(

            'withdrawal_usd',
                t.withdrawal_usd,

            'spending_usd',
                t.spending_usd,

            'investment_usd',
                t.investment_usd,

            'repayment_usd',
                t.repayment_usd,

            'savings_usd',
                t.savings_usd,

            'total_usd',
                  t.withdrawal_usd
                + t.spending_usd
                + t.investment_usd
                + t.repayment_usd
                + t.savings_usd
        )

    INTO
        v_distribution

    FROM totals AS t;


    -- ==========================================================
    -- FY-TO-DATE CURRENCY SUMMARY
    --
    -- All activity values are summed across periods.
    --
    -- Opening positions come from the first period.
    -- Closing positions come from the latest period.
    -- ==========================================================

    WITH currency_periods AS (

        SELECT
            fp.*,

            ROW_NUMBER() OVER (
                PARTITION BY fp.currency_code
                ORDER BY fp.period ASC
            ) AS first_period_row,

            ROW_NUMBER() OVER (
                PARTITION BY fp.currency_code
                ORDER BY fp.period DESC
            ) AS last_period_row

        FROM public.financial_pot AS fp

        WHERE fp.user_id =
              v_user_id

          AND fp.country_code =
              v_country_code

          AND fp.fiscal_year =
              v_fiscal_year

          AND fp.period <=
              v_period
    ),

    currency_summary AS (

        SELECT
            cp.currency_code,

            COALESCE(
                SUM(cp.deposit_amount),
                0
            ) AS deposit_amount,

            COALESCE(
                SUM(cp.deposit_amount_usd),
                0
            ) AS deposit_amount_usd,

            COALESCE(
                SUM(cp.withdrawal_amount),
                0
            ) AS withdrawal_amount,

            COALESCE(
                SUM(cp.withdrawal_amount_usd),
                0
            ) AS withdrawal_amount_usd,

            COALESCE(
                SUM(cp.spending_amount),
                0
            ) AS spending_amount,

            COALESCE(
                SUM(cp.spending_amount_usd),
                0
            ) AS spending_amount_usd,

            COALESCE(
                SUM(cp.savings_inflow),
                0
            ) AS savings_inflow,

            COALESCE(
                SUM(cp.savings_inflow_usd),
                0
            ) AS savings_inflow_usd,

            COALESCE(
                SUM(cp.savings_outflow),
                0
            ) AS savings_outflow,

            COALESCE(
                SUM(cp.savings_outflow_usd),
                0
            ) AS savings_outflow_usd,

            COALESCE(
                SUM(cp.saving_amount),
                0
            ) AS saving_amount,

            COALESCE(
                SUM(cp.saving_amount_usd),
                0
            ) AS saving_amount_usd,

            COALESCE(
                MAX(cp.opening_savings)
                FILTER (
                    WHERE cp.first_period_row = 1
                ),
                0
            ) AS opening_savings,

            COALESCE(
                MAX(cp.opening_savings_usd)
                FILTER (
                    WHERE cp.first_period_row = 1
                ),
                0
            ) AS opening_savings_usd,

            COALESCE(
                MAX(cp.closing_savings)
                FILTER (
                    WHERE cp.last_period_row = 1
                ),
                0
            ) AS closing_savings,

            COALESCE(
                MAX(cp.closing_savings_usd)
                FILTER (
                    WHERE cp.last_period_row = 1
                ),
                0
            ) AS closing_savings_usd,

            COALESCE(
                SUM(cp.investment_purchase_amount),
                0
            ) AS investment_purchase_amount,

            COALESCE(
                SUM(cp.investment_purchase_amount_usd),
                0
            ) AS investment_purchase_amount_usd,

            COALESCE(
                SUM(cp.investment_sale_amount),
                0
            ) AS investment_sale_amount,

            COALESCE(
                SUM(cp.investment_sale_amount_usd),
                0
            ) AS investment_sale_amount_usd,

            COALESCE(
                SUM(cp.loan_disbursed_amount),
                0
            ) AS loan_disbursed_amount,

            COALESCE(
                SUM(cp.loan_disbursed_amount_usd),
                0
            ) AS loan_disbursed_amount_usd,

            COALESCE(
                SUM(cp.loan_repayment_amount),
                0
            ) AS loan_repayment_amount,

            COALESCE(
                SUM(cp.loan_repayment_amount_usd),
                0
            ) AS loan_repayment_amount_usd,

            COALESCE(
                SUM(cp.loan_principal_repaid),
                0
            ) AS loan_principal_repaid,

            COALESCE(
                SUM(cp.loan_principal_repaid_usd),
                0
            ) AS loan_principal_repaid_usd,

            COALESCE(
                SUM(cp.loan_interest_repaid),
                0
            ) AS loan_interest_repaid,

            COALESCE(
                SUM(cp.loan_interest_repaid_usd),
                0
            ) AS loan_interest_repaid_usd,

            COALESCE(
                SUM(cp.loan_interest_accrued),
                0
            ) AS loan_interest_accrued,

            COALESCE(
                SUM(cp.loan_interest_accrued_usd),
                0
            ) AS loan_interest_accrued_usd,

            COALESCE(
                MAX(cp.opening_loan_balance)
                FILTER (
                    WHERE cp.first_period_row = 1
                ),
                0
            ) AS opening_loan_balance,

            COALESCE(
                MAX(cp.opening_loan_balance_usd)
                FILTER (
                    WHERE cp.first_period_row = 1
                ),
                0
            ) AS opening_loan_balance_usd,

            COALESCE(
                MAX(cp.closing_loan_balance)
                FILTER (
                    WHERE cp.last_period_row = 1
                ),
                0
            ) AS closing_loan_balance,

            COALESCE(
                MAX(cp.closing_loan_balance_usd)
                FILTER (
                    WHERE cp.last_period_row = 1
                ),
                0
            ) AS closing_loan_balance_usd

        FROM currency_periods AS cp

        GROUP BY
            cp.currency_code
    )

    SELECT
        COALESCE(
            jsonb_agg(
                jsonb_build_object(

                    'currency_code',
                        cs.currency_code,

                    'deposit',
                        jsonb_build_object(

                            'amount',
                                cs.deposit_amount,

                            'amount_usd',
                                cs.deposit_amount_usd
                        ),

                    'withdrawal',
                        jsonb_build_object(

                            'amount',
                                cs.withdrawal_amount,

                            'amount_usd',
                                cs.withdrawal_amount_usd
                        ),

                    'spending',
                        jsonb_build_object(

                            'amount',
                                cs.spending_amount,

                            'amount_usd',
                                cs.spending_amount_usd
                        ),

                    'savings',
                        jsonb_build_object(

                            'opening',
                                cs.opening_savings,

                            'opening_usd',
                                cs.opening_savings_usd,

                            'inflow',
                                cs.savings_inflow,

                            'inflow_usd',
                                cs.savings_inflow_usd,

                            'outflow',
                                cs.savings_outflow,

                            'outflow_usd',
                                cs.savings_outflow_usd,

                            'saved',
                                cs.saving_amount,

                            'saved_usd',
                                cs.saving_amount_usd,

                            'closing',
                                cs.closing_savings,

                            'closing_usd',
                                cs.closing_savings_usd
                        ),

                    'investment',
                        jsonb_build_object(

                            'purchased',
                                cs.investment_purchase_amount,

                            'purchased_usd',
                                cs.investment_purchase_amount_usd,

                            'sold',
                                cs.investment_sale_amount,

                            'sold_usd',
                                cs.investment_sale_amount_usd
                        ),

                    'loan',
                        jsonb_build_object(

                            'opening_balance',
                                cs.opening_loan_balance,

                            'opening_balance_usd',
                                cs.opening_loan_balance_usd,

                            'disbursed',
                                cs.loan_disbursed_amount,

                            'disbursed_usd',
                                cs.loan_disbursed_amount_usd,

                            'repaid',
                                cs.loan_repayment_amount,

                            'repaid_usd',
                                cs.loan_repayment_amount_usd,

                            'principal_repaid',
                                cs.loan_principal_repaid,

                            'principal_repaid_usd',
                                cs.loan_principal_repaid_usd,

                            'interest_repaid',
                                cs.loan_interest_repaid,

                            'interest_repaid_usd',
                                cs.loan_interest_repaid_usd,

                            'interest_accrued',
                                cs.loan_interest_accrued,

                            'interest_accrued_usd',
                                cs.loan_interest_accrued_usd,

                            'closing_balance',
                                cs.closing_loan_balance,

                            'closing_balance_usd',
                                cs.closing_loan_balance_usd
                        )
                )
                ORDER BY
                    cs.currency_code
            ),
            '[]'::jsonb
        )

    INTO
        v_currencies

    FROM currency_summary AS cs;


    -- ==========================================================
    -- GOLD FY-TO-DATE
    --
    -- Gold also comes entirely from financial_pot.
    --
    -- Opening position = first period.
    -- Activity = sum of period activity.
    -- Closing position = latest period.
    -- ==========================================================

    WITH gold_periods AS (

        SELECT
            fp.*,

            ROW_NUMBER() OVER (
                ORDER BY fp.period ASC
            ) AS first_period_row,

            ROW_NUMBER() OVER (
                ORDER BY fp.period DESC
            ) AS last_period_row

        FROM public.financial_pot AS fp

        WHERE fp.user_id =
              v_user_id

          AND fp.country_code =
              v_country_code

          AND fp.currency_code =
              'gold'

          AND fp.fiscal_year =
              v_fiscal_year

          AND fp.period <=
              v_period
    ),

    gold_summary AS (

        SELECT

            COALESCE(
                MAX(gp.opening_gold_quantity)
                FILTER (
                    WHERE gp.first_period_row = 1
                ),
                0
            ) AS opening_quantity,

            COALESCE(
                SUM(gp.gold_purchased),
                0
            ) AS purchased,

            COALESCE(
                SUM(gp.gold_sold),
                0
            ) AS sold,

            COALESCE(
                SUM(gp.gold_transferred_in),
                0
            ) AS transferred_in,

            COALESCE(
                SUM(gp.gold_transferred_out),
                0
            ) AS transferred_out,

            COALESCE(
                MAX(gp.closing_gold_quantity)
                FILTER (
                    WHERE gp.last_period_row = 1
                ),
                0
            ) AS closing_quantity

        FROM gold_periods AS gp
    )

    SELECT
        jsonb_build_object(

            'opening_quantity',
                gs.opening_quantity,

            'purchased',
                gs.purchased,

            'sold',
                gs.sold,

            'transferred_in',
                gs.transferred_in,

            'transferred_out',
                gs.transferred_out,

            'closing_quantity',
                gs.closing_quantity
        )

    INTO
        v_gold

    FROM gold_summary AS gs;


    -- ==========================================================
    -- RESPONSE
    -- ==========================================================

    RETURN jsonb_build_object(

        'fiscal_year',
            v_fiscal_year,

        'current_period',
            v_period,

        'money_in',
            v_money_in,

        'distribution',
            v_distribution,

        'money_by_currency',
            v_money_by_currency,

        'behavior',
            v_behavior,

        'behavior_scores',
            jsonb_build_object(

                'shopper_percentage',
                    v_shopper_score_percentage,

                'saver_percentage',
                    v_saver_score_percentage,

                'investor_percentage',
                    v_investor_score_percentage,

                'borrower_percentage',
                    v_borrower_score_percentage
            ),

        'current_period_behavior',
            v_current_period_behavior,

        'current_period_behavior_scores',
            jsonb_build_object(

                'shopper_percentage',
                    v_current_period_shopper_score_percentage,

                'saver_percentage',
                    v_current_period_saver_score_percentage,

                'investor_percentage',
                    v_current_period_investor_score_percentage,

                'borrower_percentage',
                    v_current_period_borrower_score_percentage
            ),

        'currencies',
            v_currencies,

        'gold',
            v_gold
    );

END;
$function$;