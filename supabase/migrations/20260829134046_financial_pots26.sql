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
    v_gold jsonb;

    v_gold_opening numeric(20, 6) := 0;
    v_gold_purchased numeric(20, 6) := 0;
    v_gold_sold numeric(20, 6) := 0;
    v_gold_transferred_in numeric(20, 6) := 0;
    v_gold_transferred_out numeric(20, 6) := 0;
    v_gold_closing numeric(20, 6) := 0;

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

    /*
     * Validate:
     *
     * - authenticated user exists
     * - user is active
     * - user has customer role
     *
     * Country is retrieved here only so that the
     * current fiscal period can be resolved.
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
          'customer'
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
    -- FETCH CURRENT FISCAL PERIOD
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


    IF NOT FOUND THEN
        RAISE EXCEPTION USING
            ERRCODE = 'P0001',
            MESSAGE = 'FISCAL_PERIOD_NOT_FOUND';
    END IF;


    -- ==========================================================
    -- CURRENCY SUMMARY
    -- ==========================================================

    /*
     * Important:
     *
     * We do NOT filter financial_pot by country_code.
     *
     * country_code above is only used to determine
     * the current fiscal year / period.
     *
     * Financial behaviour follows the user across
     * all countries.
     */
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

        WHERE fp.user_id = v_user_id
          AND fp.fiscal_year = v_fiscal_year

    ),

    currency_summary AS (

        SELECT
            cp.currency_code,


            -- ==================================================
            -- DEPOSIT
            -- ==================================================

            SUM(cp.deposit_amount)
                AS deposit_amount,

            SUM(cp.deposit_amount_usd)
                AS deposit_amount_usd,


            -- ==================================================
            -- WITHDRAWAL
            -- ==================================================

            SUM(cp.withdrawal_amount)
                AS withdrawal_amount,

            SUM(cp.withdrawal_amount_usd)
                AS withdrawal_amount_usd,


            -- ==================================================
            -- SPENDING
            -- ==================================================

            SUM(cp.spending_amount)
                AS spending_amount,

            SUM(cp.spending_amount_usd)
                AS spending_amount_usd,


            -- ==================================================
            -- SAVINGS ACTIVITY
            -- ==================================================

            SUM(cp.savings_inflow)
                AS savings_inflow,

            SUM(cp.savings_inflow_usd)
                AS savings_inflow_usd,

            SUM(cp.savings_outflow)
                AS savings_outflow,

            SUM(cp.savings_outflow_usd)
                AS savings_outflow_usd,

            SUM(cp.saving_amount)
                AS saving_amount,

            SUM(cp.saving_amount_usd)
                AS saving_amount_usd,


            -- ==================================================
            -- SAVINGS POSITION
            -- ==================================================

            MAX(cp.opening_savings)
                FILTER (
                    WHERE cp.first_period_row = 1
                )
                AS opening_savings,

            MAX(cp.opening_savings_usd)
                FILTER (
                    WHERE cp.first_period_row = 1
                )
                AS opening_savings_usd,

            MAX(cp.closing_savings)
                FILTER (
                    WHERE cp.last_period_row = 1
                )
                AS closing_savings,

            MAX(cp.closing_savings_usd)
                FILTER (
                    WHERE cp.last_period_row = 1
                )
                AS closing_savings_usd,


            -- ==================================================
            -- INVESTMENT
            -- ==================================================

            SUM(cp.investment_purchase_amount)
                AS investment_purchase_amount,

            SUM(cp.investment_purchase_amount_usd)
                AS investment_purchase_amount_usd,

            SUM(cp.investment_sale_amount)
                AS investment_sale_amount,

            SUM(cp.investment_sale_amount_usd)
                AS investment_sale_amount_usd,


            -- ==================================================
            -- LOAN ACTIVITY
            -- ==================================================

            SUM(cp.loan_disbursed_amount)
                AS loan_disbursed_amount,

            SUM(cp.loan_disbursed_amount_usd)
                AS loan_disbursed_amount_usd,

            SUM(cp.loan_repayment_amount)
                AS loan_repayment_amount,

            SUM(cp.loan_repayment_amount_usd)
                AS loan_repayment_amount_usd,

            SUM(cp.loan_principal_repaid)
                AS loan_principal_repaid,

            SUM(cp.loan_principal_repaid_usd)
                AS loan_principal_repaid_usd,

            SUM(cp.loan_interest_repaid)
                AS loan_interest_repaid,

            SUM(cp.loan_interest_repaid_usd)
                AS loan_interest_repaid_usd,

            SUM(cp.loan_interest_accrued)
                AS loan_interest_accrued,

            SUM(cp.loan_interest_accrued_usd)
                AS loan_interest_accrued_usd,


            -- ==================================================
            -- LOAN POSITION
            -- ==================================================

            MAX(cp.opening_loan_balance)
                FILTER (
                    WHERE cp.first_period_row = 1
                )
                AS opening_loan_balance,

            MAX(cp.opening_loan_balance_usd)
                FILTER (
                    WHERE cp.first_period_row = 1
                )
                AS opening_loan_balance_usd,

            MAX(cp.closing_loan_balance)
                FILTER (
                    WHERE cp.last_period_row = 1
                )
                AS closing_loan_balance,

            MAX(cp.closing_loan_balance_usd)
                FILTER (
                    WHERE cp.last_period_row = 1
                )
                AS closing_loan_balance_usd

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


                    -- ==========================================
                    -- DEPOSIT
                    -- ==========================================

                    'deposit',
                        jsonb_build_object(
                            'amount',
                                COALESCE(
                                    cs.deposit_amount,
                                    0
                                ),

                            'amount_usd',
                                COALESCE(
                                    cs.deposit_amount_usd,
                                    0
                                )
                        ),


                    -- ==========================================
                    -- WITHDRAWAL
                    -- ==========================================

                    'withdrawal',
                        jsonb_build_object(
                            'amount',
                                COALESCE(
                                    cs.withdrawal_amount,
                                    0
                                ),

                            'amount_usd',
                                COALESCE(
                                    cs.withdrawal_amount_usd,
                                    0
                                )
                        ),


                    -- ==========================================
                    -- SPENDING
                    -- ==========================================

                    'spending',
                        jsonb_build_object(
                            'amount',
                                COALESCE(
                                    cs.spending_amount,
                                    0
                                ),

                            'amount_usd',
                                COALESCE(
                                    cs.spending_amount_usd,
                                    0
                                )
                        ),


                    -- ==========================================
                    -- SAVINGS
                    -- ==========================================

                    'savings',
                        jsonb_build_object(

                            'opening',
                                COALESCE(
                                    cs.opening_savings,
                                    0
                                ),

                            'opening_usd',
                                COALESCE(
                                    cs.opening_savings_usd,
                                    0
                                ),

                            'inflow',
                                COALESCE(
                                    cs.savings_inflow,
                                    0
                                ),

                            'inflow_usd',
                                COALESCE(
                                    cs.savings_inflow_usd,
                                    0
                                ),

                            'outflow',
                                COALESCE(
                                    cs.savings_outflow,
                                    0
                                ),

                            'outflow_usd',
                                COALESCE(
                                    cs.savings_outflow_usd,
                                    0
                                ),

                            'saved',
                                COALESCE(
                                    cs.saving_amount,
                                    0
                                ),

                            'saved_usd',
                                COALESCE(
                                    cs.saving_amount_usd,
                                    0
                                ),

                            'closing',
                                COALESCE(
                                    cs.closing_savings,
                                    0
                                ),

                            'closing_usd',
                                COALESCE(
                                    cs.closing_savings_usd,
                                    0
                                )
                        ),


                    -- ==========================================
                    -- INVESTMENT
                    -- ==========================================

                    'investment',
                        jsonb_build_object(

                            'purchased',
                                COALESCE(
                                    cs.investment_purchase_amount,
                                    0
                                ),

                            'purchased_usd',
                                COALESCE(
                                    cs.investment_purchase_amount_usd,
                                    0
                                ),

                            'sold',
                                COALESCE(
                                    cs.investment_sale_amount,
                                    0
                                ),

                            'sold_usd',
                                COALESCE(
                                    cs.investment_sale_amount_usd,
                                    0
                                )
                        ),


                    -- ==========================================
                    -- LOAN
                    -- ==========================================

                    'loan',
                        jsonb_build_object(

                            'opening_balance',
                                COALESCE(
                                    cs.opening_loan_balance,
                                    0
                                ),

                            'opening_balance_usd',
                                COALESCE(
                                    cs.opening_loan_balance_usd,
                                    0
                                ),

                            'disbursed',
                                COALESCE(
                                    cs.loan_disbursed_amount,
                                    0
                                ),

                            'disbursed_usd',
                                COALESCE(
                                    cs.loan_disbursed_amount_usd,
                                    0
                                ),

                            'repaid',
                                COALESCE(
                                    cs.loan_repayment_amount,
                                    0
                                ),

                            'repaid_usd',
                                COALESCE(
                                    cs.loan_repayment_amount_usd,
                                    0
                                ),

                            'principal_repaid',
                                COALESCE(
                                    cs.loan_principal_repaid,
                                    0
                                ),

                            'principal_repaid_usd',
                                COALESCE(
                                    cs.loan_principal_repaid_usd,
                                    0
                                ),

                            'interest_repaid',
                                COALESCE(
                                    cs.loan_interest_repaid,
                                    0
                                ),

                            'interest_repaid_usd',
                                COALESCE(
                                    cs.loan_interest_repaid_usd,
                                    0
                                ),

                            'interest_accrued',
                                COALESCE(
                                    cs.loan_interest_accrued,
                                    0
                                ),

                            'interest_accrued_usd',
                                COALESCE(
                                    cs.loan_interest_accrued_usd,
                                    0
                                ),

                            'closing_balance',
                                COALESCE(
                                    cs.closing_loan_balance,
                                    0
                                ),

                            'closing_balance_usd',
                                COALESCE(
                                    cs.closing_loan_balance_usd,
                                    0
                                )
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
    -- GOLD ACTIVITY - CURRENT FISCAL YEAR
    -- ==========================================================

    SELECT

        COALESCE(
            SUM(
                CASE
                    WHEN e.activity_type =
                        'investment_buy'::public.financial_activity_type
                    THEN e.gold_quantity

                    ELSE 0
                END
            ),
            0
        ),

        COALESCE(
            SUM(
                CASE
                    WHEN e.activity_type =
                        'investment_sell'::public.financial_activity_type
                    THEN e.gold_quantity

                    ELSE 0
                END
            ),
            0
        ),

        COALESCE(
            SUM(
                CASE
                    WHEN e.activity_type =
                        'investment_transfer_in'::public.financial_activity_type
                    THEN e.gold_quantity

                    ELSE 0
                END
            ),
            0
        ),

        COALESCE(
            SUM(
                CASE
                    WHEN e.activity_type =
                        'investment_transfer_out'::public.financial_activity_type
                    THEN e.gold_quantity

                    ELSE 0
                END
            ),
            0
        )

    INTO
        v_gold_purchased,
        v_gold_sold,
        v_gold_transferred_in,
        v_gold_transferred_out

    FROM public.financial_pot_event AS e

    WHERE e.user_id = v_user_id
      AND e.fiscal_year = v_fiscal_year;


    -- ==========================================================
    -- GOLD OPENING POSITION
    -- ==========================================================

    /*
     * Net gold position before the current fiscal year.
     */
    SELECT
        COALESCE(
            SUM(
                CASE

                    WHEN e.activity_type IN (
                        'investment_buy'::public.financial_activity_type,
                        'investment_transfer_in'::public.financial_activity_type
                    )
                    THEN e.gold_quantity

                    WHEN e.activity_type IN (
                        'investment_sell'::public.financial_activity_type,
                        'investment_transfer_out'::public.financial_activity_type
                    )
                    THEN -e.gold_quantity

                    ELSE 0

                END
            ),
            0
        )

    INTO
        v_gold_opening

    FROM public.financial_pot_event AS e

    WHERE e.user_id = v_user_id
      AND e.fiscal_year < v_fiscal_year;


    -- ==========================================================
    -- GOLD CLOSING POSITION
    -- ==========================================================

    v_gold_closing :=
          v_gold_opening
        + v_gold_purchased
        + v_gold_transferred_in
        - v_gold_sold
        - v_gold_transferred_out;


    v_gold :=
        jsonb_build_object(

            'opening_quantity',
                v_gold_opening,

            'purchased',
                v_gold_purchased,

            'sold',
                v_gold_sold,

            'transferred_in',
                v_gold_transferred_in,

            'transferred_out',
                v_gold_transferred_out,

            'closing_quantity',
                v_gold_closing

        );


    -- ==========================================================
    -- RESPONSE
    -- ==========================================================

    RETURN jsonb_build_object(

        'fiscal_year',
            v_fiscal_year,

        'current_period',
            v_period,

        'currencies',
            v_currencies,

        'gold',
            v_gold

    );

END;
$function$;


-- ==========================================================
-- PERMISSIONS
-- ==========================================================

REVOKE ALL
ON FUNCTION public.get_my_financial_summary()
FROM PUBLIC;


GRANT EXECUTE
ON FUNCTION public.get_my_financial_summary()
TO authenticated;