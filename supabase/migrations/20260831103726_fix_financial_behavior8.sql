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
     * FINANCIAL POT VALUES BY PERIOD / CURRENCY
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
     * AUTHORITATIVE CASH MOVEMENTS FROM EVENTS
     * ==========================================================
     *
     * amount / amount_usd represent business activity.
     *
     * cash_amount / cash_amount_usd represent the actual amount
     * entering or leaving savings.
     *
     * There is deliberately NO:
     *
     *     NULLIF(cash_amount, 0) -> amount
     *
     * fallback here.
     * ==========================================================
     */

    event_cash_rows AS (

        SELECT
            e.period,

            lower(
                e.currency_code
            ) AS currency_code,


            /*
             * --------------------------------------------------
             * INITIAL SAVINGS / BROUGHT FORWARD
             * --------------------------------------------------
             */

            COALESCE(
                SUM(
                    CASE
                        WHEN e.transaction_type =
                             'initial_savings_seed'
                        THEN e.cash_amount
                        ELSE 0
                    END
                ),
                0
            ) AS initial_savings_seed,

            COALESCE(
                SUM(
                    CASE
                        WHEN e.transaction_type =
                             'initial_savings_seed'
                        THEN e.cash_amount_usd
                        ELSE 0
                    END
                ),
                0
            ) AS initial_savings_seed_usd,


            /*
             * --------------------------------------------------
             * CASH IN
             * --------------------------------------------------
             */

            COALESCE(
                SUM(
                    CASE
                        WHEN e.activity_type =
                             'deposit'::public.financial_activity_type

                         AND e.transaction_type IN (
                             'cash_deposit',
                             'credit_agent_cash_deposit',
                             'customer_direct_deposit'
                         )

                        THEN e.cash_amount
                        ELSE 0
                    END
                ),
                0
            ) AS cash_in,

            COALESCE(
                SUM(
                    CASE
                        WHEN e.activity_type =
                             'deposit'::public.financial_activity_type

                         AND e.transaction_type IN (
                             'cash_deposit',
                             'credit_agent_cash_deposit',
                             'customer_direct_deposit'
                         )

                        THEN e.cash_amount_usd
                        ELSE 0
                    END
                ),
                0
            ) AS cash_in_usd,


            /*
             * --------------------------------------------------
             * TRANSFER IN
             * --------------------------------------------------
             */

            COALESCE(
                SUM(
                    CASE
                        WHEN e.activity_type =
                             'deposit'::public.financial_activity_type

                         AND e.transaction_type =
                             'cash_transfer'

                        THEN e.cash_amount
                        ELSE 0
                    END
                ),
                0
            ) AS transfer_in,

            COALESCE(
                SUM(
                    CASE
                        WHEN e.activity_type =
                             'deposit'::public.financial_activity_type

                         AND e.transaction_type =
                             'cash_transfer'

                        THEN e.cash_amount_usd
                        ELSE 0
                    END
                ),
                0
            ) AS transfer_in_usd,


            /*
             * --------------------------------------------------
             * LOAN DISBURSEMENT
             * --------------------------------------------------
             */

            COALESCE(
                SUM(
                    CASE
                        WHEN e.activity_type =
                             'loan_disbursement'
                                 ::public.financial_activity_type

                         AND e.transaction_type <>
                             'initial_loan_seed'

                        THEN e.cash_amount
                        ELSE 0
                    END
                ),
                0
            ) AS loan_disbursement,

            COALESCE(
                SUM(
                    CASE
                        WHEN e.activity_type =
                             'loan_disbursement'
                                 ::public.financial_activity_type

                         AND e.transaction_type <>
                             'initial_loan_seed'

                        THEN e.cash_amount_usd
                        ELSE 0
                    END
                ),
                0
            ) AS loan_disbursement_usd,


            /*
             * --------------------------------------------------
             * INVESTMENT PROCEEDS
             * --------------------------------------------------
             */

            COALESCE(
                SUM(
                    CASE
                        WHEN e.activity_type =
                             'investment_sell'
                                 ::public.financial_activity_type

                        THEN e.cash_amount
                        ELSE 0
                    END
                ),
                0
            ) AS investment_proceeds,

            COALESCE(
                SUM(
                    CASE
                        WHEN e.activity_type =
                             'investment_sell'
                                 ::public.financial_activity_type

                        THEN e.cash_amount_usd
                        ELSE 0
                    END
                ),
                0
            ) AS investment_proceeds_usd,


            /*
             * --------------------------------------------------
             * WITHDRAWAL CASH OUT
             * --------------------------------------------------
             */

            COALESCE(
                SUM(
                    CASE
                        WHEN e.activity_type =
                             'withdrawal'
                                 ::public.financial_activity_type

                        THEN e.cash_amount
                        ELSE 0
                    END
                ),
                0
            ) AS withdrawal,

            COALESCE(
                SUM(
                    CASE
                        WHEN e.activity_type =
                             'withdrawal'
                                 ::public.financial_activity_type

                        THEN e.cash_amount_usd
                        ELSE 0
                    END
                ),
                0
            ) AS withdrawal_usd,


            /*
             * --------------------------------------------------
             * SPENDING CASH OUT
             * --------------------------------------------------
             */

            COALESCE(
                SUM(
                    CASE
                        WHEN e.activity_type =
                             'spending'
                                 ::public.financial_activity_type

                        THEN e.cash_amount
                        ELSE 0
                    END
                ),
                0
            ) AS spending,

            COALESCE(
                SUM(
                    CASE
                        WHEN e.activity_type =
                             'spending'
                                 ::public.financial_activity_type

                        THEN e.cash_amount_usd
                        ELSE 0
                    END
                ),
                0
            ) AS spending_usd,


            /*
             * --------------------------------------------------
             * INVESTMENT CASH OUT
             * --------------------------------------------------
             */

            COALESCE(
                SUM(
                    CASE
                        WHEN e.activity_type =
                             'investment_buy'
                                 ::public.financial_activity_type

                        THEN e.cash_amount
                        ELSE 0
                    END
                ),
                0
            ) AS investment,

            COALESCE(
                SUM(
                    CASE
                        WHEN e.activity_type =
                             'investment_buy'
                                 ::public.financial_activity_type

                        THEN e.cash_amount_usd
                        ELSE 0
                    END
                ),
                0
            ) AS investment_usd,


            /*
             * --------------------------------------------------
             * LOAN REPAYMENT CASH OUT
             * --------------------------------------------------
             */

            COALESCE(
                SUM(
                    CASE
                        WHEN e.activity_type =
                             'loan_repayment'
                                 ::public.financial_activity_type

                         AND e.transaction_type <>
                             'initial_loan_repayment_seed'

                        THEN e.cash_amount
                        ELSE 0
                    END
                ),
                0
            ) AS repayment,

            COALESCE(
                SUM(
                    CASE
                        WHEN e.activity_type =
                             'loan_repayment'
                                 ::public.financial_activity_type

                         AND e.transaction_type <>
                             'initial_loan_repayment_seed'

                        THEN e.cash_amount_usd
                        ELSE 0
                    END
                ),
                0
            ) AS repayment_usd

        FROM public.financial_pot_event AS e

        WHERE e.user_id = v_user_id
          AND e.country_code = v_country_code
          AND e.fiscal_year = v_fiscal_year

        GROUP BY
            e.period,
            lower(e.currency_code)

    ),

    /*
     * ==========================================================
     * AUTHORITATIVE MONEY FLOW BY PERIOD / CURRENCY
     * ==========================================================
     *
     * Savings B/F:
     *
     * - normal period -> financial_pot.opening_savings
     * - first FI initialization -> initial_savings_seed
     *
     * We use the seed only when opening_savings is zero so the
     * same brought-forward balance can never be counted twice.
     * ==========================================================
     */

    money_currency_rows AS (

        SELECT
            cr.period,
            cr.currency_code,

            CASE
                WHEN cr.opening_savings <> 0
                THEN cr.opening_savings

                ELSE COALESCE(
                    ec.initial_savings_seed,
                    0
                )
            END AS savings_brought_forward,

            CASE
                WHEN cr.opening_savings_usd <> 0
                THEN cr.opening_savings_usd

                ELSE COALESCE(
                    ec.initial_savings_seed_usd,
                    0
                )
            END AS savings_brought_forward_usd,

            COALESCE(
                ec.cash_in,
                0
            ) AS cash_in,

            COALESCE(
                ec.cash_in_usd,
                0
            ) AS cash_in_usd,

            COALESCE(
                ec.transfer_in,
                0
            ) AS transfer_in,

            COALESCE(
                ec.transfer_in_usd,
                0
            ) AS transfer_in_usd,

            COALESCE(
                ec.loan_disbursement,
                0
            ) AS loan_disbursement,

            COALESCE(
                ec.loan_disbursement_usd,
                0
            ) AS loan_disbursement_usd,

            COALESCE(
                ec.investment_proceeds,
                0
            ) AS investment_proceeds,

            COALESCE(
                ec.investment_proceeds_usd,
                0
            ) AS investment_proceeds_usd,

            COALESCE(
                ec.withdrawal,
                0
            ) AS withdrawal,

            COALESCE(
                ec.withdrawal_usd,
                0
            ) AS withdrawal_usd,

            COALESCE(
                ec.spending,
                0
            ) AS spending,

            COALESCE(
                ec.spending_usd,
                0
            ) AS spending_usd,

            COALESCE(
                ec.investment,
                0
            ) AS investment,

            COALESCE(
                ec.investment_usd,
                0
            ) AS investment_usd,

            COALESCE(
                ec.repayment,
                0
            ) AS repayment,

            COALESCE(
                ec.repayment_usd,
                0
            ) AS repayment_usd,

            cr.closing_savings AS savings,

            cr.closing_savings_usd AS savings_usd

        FROM currency_rows AS cr

        LEFT JOIN event_cash_rows AS ec
            ON ec.period = cr.period
           AND ec.currency_code = cr.currency_code

    ),

    /*
     * ==========================================================
     * ALL-CURRENCY PERIOD MONEY FLOW
     * ==========================================================
     *
     * Consolidated values are USD equivalent.
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
     * Kept for backward compatibility.
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
                 *
                 * Preserved for compatibility.
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
                 * NEW: CONSOLIDATED MONEY IN
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
                 * NEW: CONSOLIDATED DISTRIBUTION
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
                 * NEW: MONEY FLOW BY CURRENCY
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


        /*
         * Overall fiscal-year financial behavior.
         */
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