CREATE OR REPLACE FUNCTION public.get_my_financial_periods()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
    v_user_id text;
    v_country_code text;

    v_fiscal_year integer;
    v_current_period integer;

    v_periods jsonb;

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
            MESSAGE = 'FINANCIAL_BEHAVIOUR_NOT_AUTHORIZED';
    END IF;


    IF v_country_code IS NULL
       OR trim(v_country_code) = '' THEN

        RAISE EXCEPTION USING
            ERRCODE = 'P0001',
            MESSAGE = 'USER_COUNTRY_NOT_FOUND';

    END IF;


    -- ==========================================================
    -- CURRENT FISCAL YEAR / PERIOD
    -- ==========================================================

    SELECT
        fiscal_period.fiscal_year,
        fiscal_period.period
    INTO
        v_fiscal_year,
        v_current_period
    FROM public.fetch_fiscal_period(
        v_country_code
    ) AS fiscal_period;


    IF NOT FOUND THEN
        RAISE EXCEPTION USING
            ERRCODE = 'P0001',
            MESSAGE = 'FISCAL_PERIOD_NOT_FOUND';
    END IF;


    -- ==========================================================
    -- BUILD PERIOD RESPONSE
    -- ==========================================================

    WITH periods AS (

        /*
         * Always return P1 - P12.
         */
        SELECT
            generate_series(1, 12) AS period

    ),

    currency_rows AS (

        SELECT
            fp.period,
            lower(fp.currency_code) AS currency_code,

            -- Deposit
            COALESCE(
                SUM(fp.deposit_amount),
                0
            ) AS deposit_amount,

            COALESCE(
                SUM(fp.deposit_amount_usd),
                0
            ) AS deposit_amount_usd,

            -- Withdrawal
            COALESCE(
                SUM(fp.withdrawal_amount),
                0
            ) AS withdrawal_amount,

            COALESCE(
                SUM(fp.withdrawal_amount_usd),
                0
            ) AS withdrawal_amount_usd,

            -- Spending
            COALESCE(
                SUM(fp.spending_amount),
                0
            ) AS spending_amount,

            COALESCE(
                SUM(fp.spending_amount_usd),
                0
            ) AS spending_amount_usd,

            -- Savings
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

            -- Investment
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

            -- Loan
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
          AND fp.fiscal_year = v_fiscal_year

        GROUP BY
            fp.period,
            lower(fp.currency_code)

    ),

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

    period_currency_json AS (

        SELECT
            cr.period,

            jsonb_agg(
                jsonb_build_object(

                    'currency_code',
                        cr.currency_code,

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

        GROUP BY
            cr.period

    )

    SELECT
        jsonb_agg(
            jsonb_build_object(

                'period',
                    p.period,

                'is_current_period',
                    p.period = v_current_period,

                'has_activity',
                    pt.period IS NOT NULL,

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

                'currencies',
                    COALESCE(
                        pcj.currencies,
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

    LEFT JOIN period_currency_json AS pcj
        ON pcj.period = p.period;


    -- ==========================================================
    -- RESPONSE
    -- ==========================================================

    RETURN jsonb_build_object(

        'fiscal_year',
            v_fiscal_year,

        'current_period',
            v_current_period,

        'periods',
            COALESCE(
                v_periods,
                '[]'::jsonb
            )

    );

END;
$function$
