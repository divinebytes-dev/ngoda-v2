CREATE OR REPLACE FUNCTION public.get_my_financial_periods()
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
    v_current_period integer;

    v_fiscal_year_behavior
        public.financial_behavior_type :=
            'neutral'::public.financial_behavior_type;

    v_fiscal_year_shopper_score numeric := 0;
    v_fiscal_year_saver_score numeric := 0;
    v_fiscal_year_investor_score numeric := 0;
    v_fiscal_year_borrower_score numeric := 0;

    v_periods jsonb;

BEGIN

    /*
     * ==========================================================
     * AUTHENTICATION
     * ==========================================================
     */

    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION USING
            ERRCODE = '42501',
            MESSAGE = 'UNAUTHORIZED';
    END IF;


    /*
     * ==========================================================
     * AUTHORIZED USER + COUNTRY
     * ==========================================================
     */

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
            MESSAGE = 'FINANCIAL_BEHAVIOUR_NOT_AUTHORIZED';
    END IF;


    IF v_country_code IS NULL
       OR trim(v_country_code) = ''
    THEN
        RAISE EXCEPTION USING
            ERRCODE = 'P0001',
            MESSAGE = 'USER_COUNTRY_NOT_FOUND';
    END IF;


    /*
     * ==========================================================
     * CURRENT FISCAL YEAR / PERIOD
     * ==========================================================
     */

    SELECT
        fiscal_period.fiscal_year,
        fiscal_period.period
    INTO
        v_fiscal_year,
        v_current_period
    FROM public.fetch_fiscal_period(
        v_country_code
    ) AS fiscal_period;


    IF NOT FOUND
       OR v_fiscal_year IS NULL
       OR v_current_period IS NULL
    THEN
        RAISE EXCEPTION USING
            ERRCODE = 'P0001',
            MESSAGE = 'FISCAL_PERIOD_NOT_FOUND';
    END IF;


    /*
     * ==========================================================
     * FISCAL-YEAR / ALL-CURRENCY BEHAVIOR
     * ==========================================================
     */

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
        v_fiscal_year_behavior,
        v_fiscal_year_shopper_score,
        v_fiscal_year_saver_score,
        v_fiscal_year_investor_score,
        v_fiscal_year_borrower_score

    FROM public.financial_behavior AS fb

    WHERE fb.user_id = v_user_id

      AND fb.country_code = v_country_code

      AND fb.fiscal_year = v_fiscal_year

      AND fb.scope =
          'fiscal_year'::public.financial_behavior_scope

      AND fb.period IS NULL

      AND fb.currency_code IS NULL

    LIMIT 1;


    IF NOT FOUND THEN

        v_fiscal_year_behavior :=
            'neutral'::public.financial_behavior_type;

        v_fiscal_year_shopper_score := 0;
        v_fiscal_year_saver_score := 0;
        v_fiscal_year_investor_score := 0;
        v_fiscal_year_borrower_score := 0;

    END IF;


    /*
     * ==========================================================
     * BUILD PERIOD RESPONSE
     * ==========================================================
     */

    WITH periods AS (

        /*
         * Always return P1 - P12.
         */
        SELECT
            generate_series(
                1,
                12
            ) AS period

    ),


    /*
     * ==========================================================
     * FINANCIAL POT SNAPSHOT BY PERIOD / CURRENCY
     * ==========================================================
     *
     * financial_pot is now the reporting source of truth.
     *
     * financial_pot_event is deliberately NOT consulted by this
     * report.
     * ==========================================================
     */

    currency_rows AS (

        SELECT
            fp.period,

            lower(
                fp.currency_code
            ) AS currency_code,


            /*
             * --------------------------------------------------
             * DEPOSIT
             * --------------------------------------------------
             */

            COALESCE(
                SUM(fp.deposit_amount),
                0
            ) AS deposit_amount,

            COALESCE(
                SUM(fp.deposit_amount_usd),
                0
            ) AS deposit_amount_usd,


            /*
             * --------------------------------------------------
             * MONEY IN SNAPSHOTS
             * --------------------------------------------------
             */

            COALESCE(
                SUM(fp.cash_in_amount),
                0
            ) AS cash_in_amount,

            COALESCE(
                SUM(fp.cash_in_amount_usd),
                0
            ) AS cash_in_amount_usd,

            COALESCE(
                SUM(fp.transfer_in_amount),
                0
            ) AS transfer_in_amount,

            COALESCE(
                SUM(fp.transfer_in_amount_usd),
                0
            ) AS transfer_in_amount_usd,

            COALESCE(
                SUM(fp.investment_proceeds_amount),
                0
            ) AS investment_proceeds_amount,

            COALESCE(
                SUM(fp.investment_proceeds_amount_usd),
                0
            ) AS investment_proceeds_amount_usd,


            /*
             * --------------------------------------------------
             * WITHDRAWAL
             * --------------------------------------------------
             */

            COALESCE(
                SUM(fp.withdrawal_amount),
                0
            ) AS withdrawal_amount,

            COALESCE(
                SUM(fp.withdrawal_amount_usd),
                0
            ) AS withdrawal_amount_usd,

            COALESCE(
                SUM(fp.withdrawal_cash_amount),
                0
            ) AS withdrawal_cash_amount,

            COALESCE(
                SUM(fp.withdrawal_cash_amount_usd),
                0
            ) AS withdrawal_cash_amount_usd,


            /*
             * --------------------------------------------------
             * SPENDING
             * --------------------------------------------------
             */

            COALESCE(
                SUM(fp.spending_amount),
                0
            ) AS spending_amount,

            COALESCE(
                SUM(fp.spending_amount_usd),
                0
            ) AS spending_amount_usd,

            COALESCE(
                SUM(fp.spending_cash_amount),
                0
            ) AS spending_cash_amount,

            COALESCE(
                SUM(fp.spending_cash_amount_usd),
                0
            ) AS spending_cash_amount_usd,


            /*
             * --------------------------------------------------
             * SAVINGS
             * --------------------------------------------------
             */

            COALESCE(
                SUM(fp.opening_savings),
                0
            ) AS opening_savings,

            COALESCE(
                SUM(fp.opening_savings_usd),
                0
            ) AS opening_savings_usd,

            COALESCE(
                SUM(fp.savings_inflow),
                0
            ) AS savings_inflow,

            COALESCE(
                SUM(fp.savings_inflow_usd),
                0
            ) AS savings_inflow_usd,

            COALESCE(
                SUM(fp.savings_outflow),
                0
            ) AS savings_outflow,

            COALESCE(
                SUM(fp.savings_outflow_usd),
                0
            ) AS savings_outflow_usd,

            COALESCE(
                SUM(fp.saving_amount),
                0
            ) AS saving_amount,

            COALESCE(
                SUM(fp.saving_amount_usd),
                0
            ) AS saving_amount_usd,

            COALESCE(
                SUM(fp.closing_savings),
                0
            ) AS closing_savings,

            COALESCE(
                SUM(fp.closing_savings_usd),
                0
            ) AS closing_savings_usd,


            /*
             * --------------------------------------------------
             * INVESTMENT
             * --------------------------------------------------
             */

            COALESCE(
                SUM(fp.investment_purchase_amount),
                0
            ) AS investment_purchase_amount,

            COALESCE(
                SUM(fp.investment_purchase_amount_usd),
                0
            ) AS investment_purchase_amount_usd,

            COALESCE(
                SUM(fp.investment_sale_amount),
                0
            ) AS investment_sale_amount,

            COALESCE(
                SUM(fp.investment_sale_amount_usd),
                0
            ) AS investment_sale_amount_usd,

            COALESCE(
                SUM(fp.investment_cash_amount),
                0
            ) AS investment_cash_amount,

            COALESCE(
                SUM(fp.investment_cash_amount_usd),
                0
            ) AS investment_cash_amount_usd,


            /*
             * --------------------------------------------------
             * LOAN
             * --------------------------------------------------
             */

            COALESCE(
                SUM(fp.opening_loan_balance),
                0
            ) AS opening_loan_balance,

            COALESCE(
                SUM(fp.opening_loan_balance_usd),
                0
            ) AS opening_loan_balance_usd,

            COALESCE(
                SUM(fp.loan_disbursed_amount),
                0
            ) AS loan_disbursed_amount,

            COALESCE(
                SUM(fp.loan_disbursed_amount_usd),
                0
            ) AS loan_disbursed_amount_usd,

            COALESCE(
                SUM(fp.loan_repayment_amount),
                0
            ) AS loan_repayment_amount,

            COALESCE(
                SUM(fp.loan_repayment_amount_usd),
                0
            ) AS loan_repayment_amount_usd,

            COALESCE(
                SUM(fp.repayment_cash_amount),
                0
            ) AS repayment_cash_amount,

            COALESCE(
                SUM(fp.repayment_cash_amount_usd),
                0
            ) AS repayment_cash_amount_usd,

            COALESCE(
                SUM(fp.loan_principal_repaid),
                0
            ) AS loan_principal_repaid,

            COALESCE(
                SUM(fp.loan_principal_repaid_usd),
                0
            ) AS loan_principal_repaid_usd,

            COALESCE(
                SUM(fp.loan_interest_repaid),
                0
            ) AS loan_interest_repaid,

            COALESCE(
                SUM(fp.loan_interest_repaid_usd),
                0
            ) AS loan_interest_repaid_usd,

            COALESCE(
                SUM(fp.loan_interest_accrued),
                0
            ) AS loan_interest_accrued,

            COALESCE(
                SUM(fp.loan_interest_accrued_usd),
                0
            ) AS loan_interest_accrued_usd,

            COALESCE(
                SUM(fp.closing_loan_balance),
                0
            ) AS closing_loan_balance,

            COALESCE(
                SUM(fp.closing_loan_balance_usd),
                0
            ) AS closing_loan_balance_usd

        FROM public.financial_pot AS fp

        WHERE fp.user_id = v_user_id
          AND fp.country_code = v_country_code
          AND fp.fiscal_year = v_fiscal_year

        GROUP BY
            fp.period,
            lower(fp.currency_code)

    ),


    /*
     * ==========================================================
     * HISTORICAL SAVINGS POSITION
     * ==========================================================
     *
     * Used only when the CURRENT period has no financial_pot row.
     *
     * This remains display-only. No row is inserted by the
     * reporting function.
     * ==========================================================
     */

    historical_savings_rows AS (

        SELECT
            fp.fiscal_year,
            fp.period,

            lower(
                fp.currency_code
            ) AS currency_code,

            COALESCE(
                SUM(fp.closing_savings),
                0
            ) AS closing_savings,

            COALESCE(
                SUM(fp.closing_savings_usd),
                0
            ) AS closing_savings_usd

        FROM public.financial_pot AS fp

        WHERE fp.user_id = v_user_id
          AND fp.country_code = v_country_code

          AND (
              fp.fiscal_year < v_fiscal_year

              OR (
                  fp.fiscal_year = v_fiscal_year
                  AND fp.period < v_current_period
              )
          )

        GROUP BY
            fp.fiscal_year,
            fp.period,
            lower(fp.currency_code)

    ),


    /*
     * ==========================================================
     * LATEST PREVIOUS SAVINGS BY CURRENCY
     * ==========================================================
     *
     * We intentionally use the latest available prior period.
     *
     * Example:
     *
     * July      -> row exists
     * August    -> no transaction / no row
     * September -> no transaction yet
     *
     * September still displays July's closing savings as its
     * brought-forward position.
     * ==========================================================
     */

    latest_previous_savings AS (

        SELECT
            ranked.currency_code,
            ranked.closing_savings,
            ranked.closing_savings_usd

        FROM (

            SELECT
                hsr.currency_code,
                hsr.closing_savings,
                hsr.closing_savings_usd,

                ROW_NUMBER() OVER (
                    PARTITION BY
                        hsr.currency_code

                    ORDER BY
                        hsr.fiscal_year DESC,
                        hsr.period DESC
                ) AS row_number

            FROM historical_savings_rows AS hsr

        ) AS ranked

        WHERE ranked.row_number = 1

    ),


    /*
     * ==========================================================
     * ACTUAL MONEY FLOW BY PERIOD / CURRENCY
     * ==========================================================
     *
     * Everything here comes directly from financial_pot.
     *
     * No transaction/event history scan is needed.
     * ==========================================================
     */

    actual_money_currency_rows AS (

        SELECT
            cr.period,
            cr.currency_code,


            /*
             * --------------------------------------------------
             * MONEY IN
             * --------------------------------------------------
             */

            cr.opening_savings
                AS savings_brought_forward,

            cr.opening_savings_usd
                AS savings_brought_forward_usd,

            cr.cash_in_amount
                AS cash_in,

            cr.cash_in_amount_usd
                AS cash_in_usd,

            cr.transfer_in_amount
                AS transfer_in,

            cr.transfer_in_amount_usd
                AS transfer_in_usd,

            cr.loan_disbursed_amount
                AS loan_disbursement,

            cr.loan_disbursed_amount_usd
                AS loan_disbursement_usd,

            cr.investment_proceeds_amount
                AS investment_proceeds,

            cr.investment_proceeds_amount_usd
                AS investment_proceeds_usd,


            /*
             * --------------------------------------------------
             * DISTRIBUTION
             * --------------------------------------------------
             *
             * These use the actual CASH movement snapshots, not
             * the business/activity amounts.
             * --------------------------------------------------
             */

            cr.withdrawal_cash_amount
                AS withdrawal,

            cr.withdrawal_cash_amount_usd
                AS withdrawal_usd,

            cr.spending_cash_amount
                AS spending,

            cr.spending_cash_amount_usd
                AS spending_usd,

            cr.investment_cash_amount
                AS investment,

            cr.investment_cash_amount_usd
                AS investment_usd,

            cr.repayment_cash_amount
                AS repayment,

            cr.repayment_cash_amount_usd
                AS repayment_usd,


            /*
             * Remaining/closing savings.
             */
            cr.closing_savings
                AS savings,

            cr.closing_savings_usd
                AS savings_usd

        FROM currency_rows AS cr

    ),


    /*
     * ==========================================================
     * DISPLAY-ONLY CURRENT PERIOD CARRY FORWARD
     * ==========================================================
     *
     * If no transaction has occurred in the current period there
     * may be no financial_pot row.
     *
     * In that case:
     *
     *     Savings B/F = latest prior closing savings
     *     Savings     = latest prior closing savings
     *
     * Every current-period movement remains zero.
     *
     * Importantly, this does NOT create activity and does NOT
     * create financial behavior.
     * ==========================================================
     */

    current_period_carry_forward AS (

        SELECT
            v_current_period AS period,

            lps.currency_code,

            lps.closing_savings
                AS savings_brought_forward,

            lps.closing_savings_usd
                AS savings_brought_forward_usd,

            0::numeric AS cash_in,
            0::numeric AS cash_in_usd,

            0::numeric AS transfer_in,
            0::numeric AS transfer_in_usd,

            0::numeric AS loan_disbursement,
            0::numeric AS loan_disbursement_usd,

            0::numeric AS investment_proceeds,
            0::numeric AS investment_proceeds_usd,

            0::numeric AS withdrawal,
            0::numeric AS withdrawal_usd,

            0::numeric AS spending,
            0::numeric AS spending_usd,

            0::numeric AS investment,
            0::numeric AS investment_usd,

            0::numeric AS repayment,
            0::numeric AS repayment_usd,

            lps.closing_savings
                AS savings,

            lps.closing_savings_usd
                AS savings_usd

        FROM latest_previous_savings AS lps

        WHERE NOT EXISTS (

            SELECT
                1

            FROM currency_rows AS cr

            WHERE cr.period = v_current_period
              AND cr.currency_code = lps.currency_code

        )

    ),


    /*
     * ==========================================================
     * FINAL MONEY FLOW ROWS
     * ==========================================================
     */

    money_currency_rows AS (

        SELECT
            amcr.period,
            amcr.currency_code,

            amcr.savings_brought_forward,
            amcr.savings_brought_forward_usd,

            amcr.cash_in,
            amcr.cash_in_usd,

            amcr.transfer_in,
            amcr.transfer_in_usd,

            amcr.loan_disbursement,
            amcr.loan_disbursement_usd,

            amcr.investment_proceeds,
            amcr.investment_proceeds_usd,

            amcr.withdrawal,
            amcr.withdrawal_usd,

            amcr.spending,
            amcr.spending_usd,

            amcr.investment,
            amcr.investment_usd,

            amcr.repayment,
            amcr.repayment_usd,

            amcr.savings,
            amcr.savings_usd

        FROM actual_money_currency_rows AS amcr


        UNION ALL


        SELECT
            cpcf.period,
            cpcf.currency_code,

            cpcf.savings_brought_forward,
            cpcf.savings_brought_forward_usd,

            cpcf.cash_in,
            cpcf.cash_in_usd,

            cpcf.transfer_in,
            cpcf.transfer_in_usd,

            cpcf.loan_disbursement,
            cpcf.loan_disbursement_usd,

            cpcf.investment_proceeds,
            cpcf.investment_proceeds_usd,

            cpcf.withdrawal,
            cpcf.withdrawal_usd,

            cpcf.spending,
            cpcf.spending_usd,

            cpcf.investment,
            cpcf.investment_usd,

            cpcf.repayment,
            cpcf.repayment_usd,

            cpcf.savings,
            cpcf.savings_usd

        FROM current_period_carry_forward AS cpcf

    ),


    /*
     * ==========================================================
     * ALL-CURRENCY PERIOD MONEY FLOW
     * ==========================================================
     *
     * Consolidated values use USD equivalent.
     * ==========================================================
     */

    period_money_totals AS (

        SELECT
            mcr.period,

            COALESCE(
                SUM(mcr.savings_brought_forward_usd),
                0
            ) AS savings_brought_forward_usd,

            COALESCE(
                SUM(mcr.cash_in_usd),
                0
            ) AS cash_in_usd,

            COALESCE(
                SUM(mcr.transfer_in_usd),
                0
            ) AS transfer_in_usd,

            COALESCE(
                SUM(mcr.loan_disbursement_usd),
                0
            ) AS loan_disbursement_usd,

            COALESCE(
                SUM(mcr.investment_proceeds_usd),
                0
            ) AS investment_proceeds_usd,

            COALESCE(
                SUM(mcr.withdrawal_usd),
                0
            ) AS withdrawal_usd,

            COALESCE(
                SUM(mcr.spending_usd),
                0
            ) AS spending_usd,

            COALESCE(
                SUM(mcr.investment_usd),
                0
            ) AS investment_usd,

            COALESCE(
                SUM(mcr.repayment_usd),
                0
            ) AS repayment_usd,

            COALESCE(
                SUM(mcr.savings_usd),
                0
            ) AS savings_usd

        FROM money_currency_rows AS mcr

        GROUP BY
            mcr.period

    ),


    /*
     * ==========================================================
     * EXISTING PERIOD TOTALS
     * ==========================================================
     *
     * Preserved exactly for backward compatibility.
     * ==========================================================
     */

    period_totals AS (

        SELECT
            cr.period,

            COALESCE(
                SUM(cr.deposit_amount_usd),
                0
            ) AS deposit_usd,

            COALESCE(
                SUM(cr.withdrawal_amount_usd),
                0
            ) AS withdrawal_usd,

            COALESCE(
                SUM(cr.spending_amount_usd),
                0
            ) AS spending_usd,

            COALESCE(
                SUM(cr.savings_inflow_usd),
                0
            ) AS savings_inflow_usd,

            COALESCE(
                SUM(cr.savings_outflow_usd),
                0
            ) AS savings_outflow_usd,

            COALESCE(
                SUM(cr.saving_amount_usd),
                0
            ) AS saving_usd,

            COALESCE(
                SUM(cr.closing_savings_usd),
                0
            ) AS closing_savings_usd,

            COALESCE(
                SUM(cr.investment_purchase_amount_usd),
                0
            ) AS investment_usd,

            COALESCE(
                SUM(cr.investment_sale_amount_usd),
                0
            ) AS investment_sale_usd,

            COALESCE(
                SUM(cr.loan_disbursed_amount_usd),
                0
            ) AS borrowing_usd,

            COALESCE(
                SUM(cr.loan_repayment_amount_usd),
                0
            ) AS repayment_usd,

            COALESCE(
                SUM(cr.loan_interest_accrued_usd),
                0
            ) AS interest_accrued_usd,

            COALESCE(
                SUM(cr.closing_loan_balance_usd),
                0
            ) AS closing_loan_balance_usd

        FROM currency_rows AS cr

        GROUP BY
            cr.period

    ),


    /*
     * ==========================================================
     * PERIOD / ALL-CURRENCY BEHAVIOR
     * ==========================================================
     */

    period_behavior AS (

        SELECT
            fb.period,
            fb.behavior,

            COALESCE(
                fb.shopper_score_percentage,
                0
            ) AS shopper_score_percentage,

            COALESCE(
                fb.saver_score_percentage,
                0
            ) AS saver_score_percentage,

            COALESCE(
                fb.investor_score_percentage,
                0
            ) AS investor_score_percentage,

            COALESCE(
                fb.borrower_score_percentage,
                0
            ) AS borrower_score_percentage

        FROM public.financial_behavior AS fb

        WHERE fb.user_id = v_user_id
          AND fb.country_code = v_country_code
          AND fb.fiscal_year = v_fiscal_year

          AND fb.scope =
              'period'::public.financial_behavior_scope

          AND fb.period IS NOT NULL

          AND fb.currency_code IS NULL

    ),


    /*
     * ==========================================================
     * PERIOD / CURRENCY BEHAVIOR
     * ==========================================================
     */

    currency_behavior AS (

        SELECT
            fb.period,

            lower(
                fb.currency_code
            ) AS currency_code,

            fb.behavior,

            COALESCE(
                fb.shopper_score_percentage,
                0
            ) AS shopper_score_percentage,

            COALESCE(
                fb.saver_score_percentage,
                0
            ) AS saver_score_percentage,

            COALESCE(
                fb.investor_score_percentage,
                0
            ) AS investor_score_percentage,

            COALESCE(
                fb.borrower_score_percentage,
                0
            ) AS borrower_score_percentage

        FROM public.financial_behavior AS fb

        WHERE fb.user_id = v_user_id
          AND fb.country_code = v_country_code
          AND fb.fiscal_year = v_fiscal_year

          AND fb.scope =
              'period'::public.financial_behavior_scope

          AND fb.period IS NOT NULL

          AND fb.currency_code IS NOT NULL

    ),


    /*
     * ==========================================================
     * EXISTING CURRENCY JSON
     * ==========================================================
     *
     * Preserved for compatibility.
     *
     * This still represents actual financial_pot rows only.
     *
     * A display-only current-period carry-forward is therefore
     * intentionally not inserted into this legacy currencies[]
     * collection.
     * ==========================================================
     */

    period_currency_json AS (

        SELECT
            cr.period,

            jsonb_agg(
                jsonb_build_object(

                    'currency_code',
                        cr.currency_code,

                    'behavior',
                        COALESCE(
                            cb.behavior,
                            'neutral'::public.financial_behavior_type
                        ),

                    'behavior_scores',
                        jsonb_build_object(

                            'shopper_percentage',
                                COALESCE(
                                    cb.shopper_score_percentage,
                                    0
                                ),

                            'saver_percentage',
                                COALESCE(
                                    cb.saver_score_percentage,
                                    0
                                ),

                            'investor_percentage',
                                COALESCE(
                                    cb.investor_score_percentage,
                                    0
                                ),

                            'borrower_percentage',
                                COALESCE(
                                    cb.borrower_score_percentage,
                                    0
                                )
                        ),

                    'deposit',
                        jsonb_build_object(
                            'amount',
                                cr.deposit_amount,

                            'amount_usd',
                                cr.deposit_amount_usd
                        ),

                    'withdrawal',
                        jsonb_build_object(
                            'amount',
                                cr.withdrawal_amount,

                            'amount_usd',
                                cr.withdrawal_amount_usd
                        ),

                    'spending',
                        jsonb_build_object(
                            'amount',
                                cr.spending_amount,

                            'amount_usd',
                                cr.spending_amount_usd
                        ),

                    'savings',
                        jsonb_build_object(

                            'opening',
                                cr.opening_savings,

                            'opening_usd',
                                cr.opening_savings_usd,

                            'inflow',
                                cr.savings_inflow,

                            'inflow_usd',
                                cr.savings_inflow_usd,

                            'outflow',
                                cr.savings_outflow,

                            'outflow_usd',
                                cr.savings_outflow_usd,

                            'saved',
                                cr.saving_amount,

                            'saved_usd',
                                cr.saving_amount_usd,

                            'closing',
                                cr.closing_savings,

                            'closing_usd',
                                cr.closing_savings_usd
                        ),

                    'investment',
                        jsonb_build_object(

                            'purchased',
                                cr.investment_purchase_amount,

                            'purchased_usd',
                                cr.investment_purchase_amount_usd,

                            'sold',
                                cr.investment_sale_amount,

                            'sold_usd',
                                cr.investment_sale_amount_usd
                        ),

                    'loan',
                        jsonb_build_object(

                            'opening_balance',
                                cr.opening_loan_balance,

                            'opening_balance_usd',
                                cr.opening_loan_balance_usd,

                            'disbursed',
                                cr.loan_disbursed_amount,

                            'disbursed_usd',
                                cr.loan_disbursed_amount_usd,

                            'repaid',
                                cr.loan_repayment_amount,

                            'repaid_usd',
                                cr.loan_repayment_amount_usd,

                            'principal_repaid',
                                cr.loan_principal_repaid,

                            'principal_repaid_usd',
                                cr.loan_principal_repaid_usd,

                            'interest_repaid',
                                cr.loan_interest_repaid,

                            'interest_repaid_usd',
                                cr.loan_interest_repaid_usd,

                            'interest_accrued',
                                cr.loan_interest_accrued,

                            'interest_accrued_usd',
                                cr.loan_interest_accrued_usd,

                            'closing_balance',
                                cr.closing_loan_balance,

                            'closing_balance_usd',
                                cr.closing_loan_balance_usd
                        )

                )
                ORDER BY
                    cr.currency_code
            ) AS currencies

        FROM currency_rows AS cr

        LEFT JOIN currency_behavior AS cb
            ON cb.period = cr.period
           AND cb.currency_code = cr.currency_code

        GROUP BY
            cr.period

    ),


    /*
     * ==========================================================
     * PERIOD MONEY BY CURRENCY JSON
     * ==========================================================
     */

    period_money_currency_json AS (

        SELECT
            mcr.period,

            jsonb_agg(
                jsonb_build_object(

                    'currency_code',
                        mcr.currency_code,


                    /*
                     * ------------------------------------------
                     * MONEY IN
                     * ------------------------------------------
                     */

                    'money_in',
                        jsonb_build_object(

                            'savings_brought_forward',
                                mcr.savings_brought_forward,

                            'savings_brought_forward_usd',
                                mcr.savings_brought_forward_usd,

                            'cash_in',
                                mcr.cash_in,

                            'cash_in_usd',
                                mcr.cash_in_usd,

                            'transfer_in',
                                mcr.transfer_in,

                            'transfer_in_usd',
                                mcr.transfer_in_usd,

                            'loan_disbursement',
                                mcr.loan_disbursement,

                            'loan_disbursement_usd',
                                mcr.loan_disbursement_usd,

                            'investment_proceeds',
                                mcr.investment_proceeds,

                            'investment_proceeds_usd',
                                mcr.investment_proceeds_usd,

                            'total',
                                mcr.savings_brought_forward
                                + mcr.cash_in
                                + mcr.transfer_in
                                + mcr.loan_disbursement
                                + mcr.investment_proceeds,

                            'total_usd',
                                mcr.savings_brought_forward_usd
                                + mcr.cash_in_usd
                                + mcr.transfer_in_usd
                                + mcr.loan_disbursement_usd
                                + mcr.investment_proceeds_usd
                        ),


                    /*
                     * ------------------------------------------
                     * DISTRIBUTION
                     * ------------------------------------------
                     */

                    'distribution',
                        jsonb_build_object(

                            'withdrawal',
                                mcr.withdrawal,

                            'withdrawal_usd',
                                mcr.withdrawal_usd,

                            'spending',
                                mcr.spending,

                            'spending_usd',
                                mcr.spending_usd,

                            'investment',
                                mcr.investment,

                            'investment_usd',
                                mcr.investment_usd,

                            'repayment',
                                mcr.repayment,

                            'repayment_usd',
                                mcr.repayment_usd,

                            'savings',
                                mcr.savings,

                            'savings_usd',
                                mcr.savings_usd,

                            'total',
                                mcr.withdrawal
                                + mcr.spending
                                + mcr.investment
                                + mcr.repayment
                                + mcr.savings,

                            'total_usd',
                                mcr.withdrawal_usd
                                + mcr.spending_usd
                                + mcr.investment_usd
                                + mcr.repayment_usd
                                + mcr.savings_usd
                        )

                )
                ORDER BY
                    mcr.currency_code
            ) AS money_by_currency

        FROM money_currency_rows AS mcr

        GROUP BY
            mcr.period

    )


    /*
     * ==========================================================
     * BUILD P1 - P12
     * ==========================================================
     */

    SELECT
        jsonb_agg(
            jsonb_build_object(

                /*
                 * ----------------------------------------------
                 * PERIOD
                 * ----------------------------------------------
                 */

                'period',
                    p.period,

                'is_current_period',
                    p.period = v_current_period,

                /*
                 * Display-only carry-forward does NOT mean that
                 * the user transacted during the current period.
                 */
                'has_activity',
                    pt.period IS NOT NULL,


                /*
                 * ----------------------------------------------
                 * CONSOLIDATED PERIOD BEHAVIOR
                 * ----------------------------------------------
                 */

                'behavior',
                    COALESCE(
                        pb.behavior,
                        'neutral'::public.financial_behavior_type
                    ),

                'behavior_scores',
                    jsonb_build_object(

                        'shopper_percentage',
                            COALESCE(
                                pb.shopper_score_percentage,
                                0
                            ),

                        'saver_percentage',
                            COALESCE(
                                pb.saver_score_percentage,
                                0
                            ),

                        'investor_percentage',
                            COALESCE(
                                pb.investor_score_percentage,
                                0
                            ),

                        'borrower_percentage',
                            COALESCE(
                                pb.borrower_score_percentage,
                                0
                            )
                    ),


                /*
                 * ----------------------------------------------
                 * EXISTING ALL-CURRENCY PERIOD TOTALS
                 * ----------------------------------------------
                 */

                'all',
                    jsonb_build_object(

                        'deposit_usd',
                            COALESCE(
                                pt.deposit_usd,
                                0
                            ),

                        'withdrawal_usd',
                            COALESCE(
                                pt.withdrawal_usd,
                                0
                            ),

                        'spending_usd',
                            COALESCE(
                                pt.spending_usd,
                                0
                            ),

                        'savings_inflow_usd',
                            COALESCE(
                                pt.savings_inflow_usd,
                                0
                            ),

                        'savings_outflow_usd',
                            COALESCE(
                                pt.savings_outflow_usd,
                                0
                            ),

                        'saving_usd',
                            COALESCE(
                                pt.saving_usd,
                                0
                            ),

                        'closing_savings_usd',
                            COALESCE(
                                pt.closing_savings_usd,
                                0
                            ),

                        'investment_usd',
                            COALESCE(
                                pt.investment_usd,
                                0
                            ),

                        'investment_sale_usd',
                            COALESCE(
                                pt.investment_sale_usd,
                                0
                            ),

                        'borrowing_usd',
                            COALESCE(
                                pt.borrowing_usd,
                                0
                            ),

                        'repayment_usd',
                            COALESCE(
                                pt.repayment_usd,
                                0
                            ),

                        'interest_accrued_usd',
                            COALESCE(
                                pt.interest_accrued_usd,
                                0
                            ),

                        'closing_loan_balance_usd',
                            COALESCE(
                                pt.closing_loan_balance_usd,
                                0
                            )
                    ),


                /*
                 * ----------------------------------------------
                 * CONSOLIDATED MONEY IN
                 * ----------------------------------------------
                 */

                'money_in',
                    jsonb_build_object(

                        'savings_brought_forward_usd',
                            COALESCE(
                                pmt.savings_brought_forward_usd,
                                0
                            ),

                        'cash_in_usd',
                            COALESCE(
                                pmt.cash_in_usd,
                                0
                            ),

                        'transfer_in_usd',
                            COALESCE(
                                pmt.transfer_in_usd,
                                0
                            ),

                        'loan_disbursement_usd',
                            COALESCE(
                                pmt.loan_disbursement_usd,
                                0
                            ),

                        'investment_proceeds_usd',
                            COALESCE(
                                pmt.investment_proceeds_usd,
                                0
                            ),

                        'total_usd',
                            COALESCE(
                                pmt.savings_brought_forward_usd,
                                0
                            )
                            +
                            COALESCE(
                                pmt.cash_in_usd,
                                0
                            )
                            +
                            COALESCE(
                                pmt.transfer_in_usd,
                                0
                            )
                            +
                            COALESCE(
                                pmt.loan_disbursement_usd,
                                0
                            )
                            +
                            COALESCE(
                                pmt.investment_proceeds_usd,
                                0
                            )
                    ),


                /*
                 * ----------------------------------------------
                 * CONSOLIDATED DISTRIBUTION
                 * ----------------------------------------------
                 */

                'distribution',
                    jsonb_build_object(

                        'withdrawal_usd',
                            COALESCE(
                                pmt.withdrawal_usd,
                                0
                            ),

                        'spending_usd',
                            COALESCE(
                                pmt.spending_usd,
                                0
                            ),

                        'investment_usd',
                            COALESCE(
                                pmt.investment_usd,
                                0
                            ),

                        'repayment_usd',
                            COALESCE(
                                pmt.repayment_usd,
                                0
                            ),

                        'savings_usd',
                            COALESCE(
                                pmt.savings_usd,
                                0
                            ),

                        'total_usd',
                            COALESCE(
                                pmt.withdrawal_usd,
                                0
                            )
                            +
                            COALESCE(
                                pmt.spending_usd,
                                0
                            )
                            +
                            COALESCE(
                                pmt.investment_usd,
                                0
                            )
                            +
                            COALESCE(
                                pmt.repayment_usd,
                                0
                            )
                            +
                            COALESCE(
                                pmt.savings_usd,
                                0
                            )
                    ),


                /*
                 * ----------------------------------------------
                 * EXISTING CURRENCY BREAKDOWN
                 * ----------------------------------------------
                 */

                'currencies',
                    COALESCE(
                        pcj.currencies,
                        '[]'::jsonb
                    ),


                /*
                 * ----------------------------------------------
                 * MONEY FLOW BY CURRENCY
                 * ----------------------------------------------
                 */

                'money_by_currency',
                    COALESCE(
                        pmcj.money_by_currency,
                        '[]'::jsonb
                    )

            )
            ORDER BY
                p.period
        )

    INTO
        v_periods

    FROM periods AS p

    LEFT JOIN period_totals AS pt
        ON pt.period = p.period

    LEFT JOIN period_money_totals AS pmt
        ON pmt.period = p.period

    LEFT JOIN period_behavior AS pb
        ON pb.period = p.period

    LEFT JOIN period_currency_json AS pcj
        ON pcj.period = p.period

    LEFT JOIN period_money_currency_json AS pmcj
        ON pmcj.period = p.period;


    /*
     * ==========================================================
     * RESPONSE
     * ==========================================================
     */

    RETURN jsonb_build_object(

        'fiscal_year',
            v_fiscal_year,

        'current_period',
            v_current_period,

        'fiscal_year_behavior',
            v_fiscal_year_behavior,

        'fiscal_year_behavior_scores',
            jsonb_build_object(

                'shopper_percentage',
                    v_fiscal_year_shopper_score,

                'saver_percentage',
                    v_fiscal_year_saver_score,

                'investor_percentage',
                    v_fiscal_year_investor_score,

                'borrower_percentage',
                    v_fiscal_year_borrower_score
            ),

        'periods',
            COALESCE(
                v_periods,
                '[]'::jsonb
            )
    );

END;
$function$;