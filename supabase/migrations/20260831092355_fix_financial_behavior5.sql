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

    -- ==========================================================
    -- MONEY IN / SOURCE OF FUNDS
    --
    -- Available Money =
    --
    -- Savings B/F
    -- + Cash In
    -- + Transfer In
    -- + Loan Disbursement
    -- + Investment Proceeds
    -- ==========================================================

    v_savings_brought_forward_usd numeric(20, 6) := 0;
    v_cash_in_usd numeric(20, 6) := 0;
    v_transfer_in_usd numeric(20, 6) := 0;
    v_loan_disbursement_cash_usd numeric(20, 6) := 0;
    v_investment_proceeds_usd numeric(20, 6) := 0;
    v_available_money_usd numeric(20, 6) := 0;

    v_money_in jsonb;

    -- ==========================================================
    -- DISTRIBUTION
    -- ==========================================================

    v_distribution_withdrawal_usd numeric(20, 6) := 0;
    v_distribution_spending_usd numeric(20, 6) := 0;
    v_distribution_investment_usd numeric(20, 6) := 0;
    v_distribution_repayment_usd numeric(20, 6) := 0;
    v_distribution_savings_usd numeric(20, 6) := 0;
    v_distribution_total_usd numeric(20, 6) := 0;

    v_distribution jsonb;

    -- ==========================================================
    -- GOLD
    -- ==========================================================

    v_gold_opening numeric(20, 6) := 0;
    v_gold_purchased numeric(20, 6) := 0;
    v_gold_sold numeric(20, 6) := 0;
    v_gold_transferred_in numeric(20, 6) := 0;
    v_gold_transferred_out numeric(20, 6) := 0;
    v_gold_closing numeric(20, 6) := 0;

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
    --
    -- The amounts returned here are also the authoritative
    -- distribution values used by the behaviour engine.
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
        ),

        COALESCE(
            fb.withdrawal_amount_usd,
            0
        ),

        COALESCE(
            fb.spending_amount_usd,
            0
        ),

        COALESCE(
            fb.investment_amount_usd,
            0
        ),

        COALESCE(
            fb.repayment_amount_usd,
            0
        ),

        COALESCE(
            fb.saving_amount_usd,
            0
        )

    INTO
        v_behavior,

        v_shopper_score_percentage,
        v_saver_score_percentage,
        v_investor_score_percentage,
        v_borrower_score_percentage,

        v_distribution_withdrawal_usd,
        v_distribution_spending_usd,
        v_distribution_investment_usd,
        v_distribution_repayment_usd,
        v_distribution_savings_usd

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

        v_distribution_withdrawal_usd := 0;
        v_distribution_spending_usd := 0;
        v_distribution_investment_usd := 0;
        v_distribution_repayment_usd := 0;
        v_distribution_savings_usd := 0;

    END IF;


    -- ==========================================================
    -- DISTRIBUTION TOTAL
    --
    -- Withdrawal participates in the complete distribution,
    -- although it does not map to a behaviour identity.
    -- ==========================================================

    v_distribution_total_usd :=
          v_distribution_withdrawal_usd
        + v_distribution_spending_usd
        + v_distribution_investment_usd
        + v_distribution_repayment_usd
        + v_distribution_savings_usd;


    v_distribution :=
        jsonb_build_object(

            'withdrawal_usd',
                v_distribution_withdrawal_usd,

            'spending_usd',
                v_distribution_spending_usd,

            'investment_usd',
                v_distribution_investment_usd,

            'repayment_usd',
                v_distribution_repayment_usd,

            'savings_usd',
                v_distribution_savings_usd,

            'total_usd',
                v_distribution_total_usd
        );


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
    -- SAVINGS BROUGHT FORWARD
    --
    -- For each currency:
    --
    -- 1. Use the opening savings of the first financial pot in
    --    the fiscal year when that position exists.
    --
    -- 2. Historical installations may have initial_savings_seed
    --    events created before those seeds were treated as opening
    --    balances. In that case, use the seed as brought forward.
    --
    -- This prevents initial savings from appearing as Cash In.
    -- ==========================================================

    WITH first_currency_pot AS (

        SELECT
            fp.currency_code,
            fp.opening_savings_usd,

            ROW_NUMBER() OVER (
                PARTITION BY fp.currency_code
                ORDER BY fp.period ASC
            ) AS row_number

        FROM public.financial_pot AS fp

        WHERE fp.user_id =
              v_user_id

          AND fp.fiscal_year =
              v_fiscal_year

    ),

    currency_opening AS (

        SELECT
            fcp.currency_code,

            COALESCE(
                fcp.opening_savings_usd,
                0
            ) AS opening_savings_usd

        FROM first_currency_pot AS fcp

        WHERE fcp.row_number = 1

    ),

    seed_opening AS (

        SELECT
            e.currency_code,

            COALESCE(
                SUM(
                    COALESCE(
                        NULLIF(
                            e.cash_amount_usd,
                            0
                        ),
                        e.amount_usd,
                        0
                    )
                ),
                0
            ) AS seed_savings_usd

        FROM public.financial_pot_event AS e

        WHERE e.user_id =
              v_user_id

          AND e.fiscal_year =
              v_fiscal_year

          AND lower(e.transaction_type) =
              'initial_savings_seed'

        GROUP BY
            e.currency_code

    ),

    source_currencies AS (

        SELECT
            co.currency_code
        FROM currency_opening AS co

        UNION

        SELECT
            so.currency_code
        FROM seed_opening AS so

    )

    SELECT
        COALESCE(
            SUM(
                CASE

                    WHEN COALESCE(
                        co.opening_savings_usd,
                        0
                    ) > 0
                    THEN
                        co.opening_savings_usd

                    ELSE
                        COALESCE(
                            so.seed_savings_usd,
                            0
                        )

                END
            ),
            0
        )

    INTO
        v_savings_brought_forward_usd

    FROM source_currencies AS sc

    LEFT JOIN currency_opening AS co
        ON co.currency_code =
           sc.currency_code

    LEFT JOIN seed_opening AS so
        ON so.currency_code =
           sc.currency_code;


    -- ==========================================================
    -- MONEY IN
    --
    -- Important:
    --
    -- Use cash_amount_usd because Money In represents the actual
    -- amount of usable cash received by the user.
    --
    -- amount_usd is the business/principal amount and may differ
    -- because of fees or spreads.
    --
    -- initial_* events are opening-state reconstruction and are
    -- excluded from current fiscal-year inflows.
    -- ==========================================================

    SELECT

        -- ------------------------------------------------------
        -- CASH IN
        --
        -- Deposit activity except incoming transfers and seeds.
        --
        -- This includes genuine cash/deposit transaction types
        -- such as cash_deposit, credit_agent_cash_deposit and
        -- customer_direct_deposit.
        -- ------------------------------------------------------

        COALESCE(
            SUM(
                CASE

                    WHEN e.activity_type =
                        'deposit'::public.financial_activity_type

                     AND lower(e.transaction_type) <>
                         'cash_transfer'

                     AND lower(e.transaction_type)
                         NOT LIKE 'initial\_%' ESCAPE '\'

                    THEN
                        COALESCE(
                            NULLIF(
                                e.cash_amount_usd,
                                0
                            ),
                            e.amount_usd,
                            0
                        )

                    ELSE 0

                END
            ),
            0
        ),


        -- ------------------------------------------------------
        -- TRANSFER IN
        -- ------------------------------------------------------

        COALESCE(
            SUM(
                CASE

                    WHEN e.activity_type =
                        'deposit'::public.financial_activity_type

                     AND lower(e.transaction_type) =
                         'cash_transfer'

                    THEN
                        COALESCE(
                            NULLIF(
                                e.cash_amount_usd,
                                0
                            ),
                            e.amount_usd,
                            0
                        )

                    ELSE 0

                END
            ),
            0
        ),


        -- ------------------------------------------------------
        -- LOAN DISBURSEMENT
        --
        -- Actual wallet cash received, not loan principal.
        --
        -- Example:
        -- principal       $5.00
        -- wallet received $4.95
        --
        -- Money In = $4.95
        -- ------------------------------------------------------

        COALESCE(
            SUM(
                CASE

                    WHEN e.activity_type =
                        'loan_disbursement'::public.financial_activity_type

                     AND lower(e.transaction_type)
                         NOT LIKE 'initial\_%' ESCAPE '\'

                    THEN
                        COALESCE(
                            NULLIF(
                                e.cash_amount_usd,
                                0
                            ),
                            e.amount_usd,
                            0
                        )

                    ELSE 0

                END
            ),
            0
        ),


        -- ------------------------------------------------------
        -- INVESTMENT PROCEEDS
        --
        -- Gold/investment sale converts an investment back into
        -- usable money.
        --
        -- Use actual cash proceeds after spread/charges rather
        -- than the gross investment sale amount.
        -- ------------------------------------------------------

        COALESCE(
            SUM(
                CASE

                    WHEN e.activity_type =
                        'investment_sell'::public.financial_activity_type

                     AND lower(e.transaction_type)
                         NOT LIKE 'initial\_%' ESCAPE '\'

                    THEN
                        COALESCE(
                            NULLIF(
                                e.cash_amount_usd,
                                0
                            ),
                            e.amount_usd,
                            0
                        )

                    ELSE 0

                END
            ),
            0
        )

    INTO
        v_cash_in_usd,
        v_transfer_in_usd,
        v_loan_disbursement_cash_usd,
        v_investment_proceeds_usd

    FROM public.financial_pot_event AS e

    WHERE e.user_id =
          v_user_id

      AND e.fiscal_year =
          v_fiscal_year;


    -- ==========================================================
    -- AVAILABLE MONEY
    -- ==========================================================

    v_available_money_usd :=
          v_savings_brought_forward_usd
        + v_cash_in_usd
        + v_transfer_in_usd
        + v_loan_disbursement_cash_usd
        + v_investment_proceeds_usd;


    v_money_in :=
        jsonb_build_object(

            'savings_brought_forward_usd',
                v_savings_brought_forward_usd,

            'cash_in_usd',
                v_cash_in_usd,

            'transfer_in_usd',
                v_transfer_in_usd,

            'loan_disbursement_usd',
                v_loan_disbursement_cash_usd,

            'investment_proceeds_usd',
                v_investment_proceeds_usd,

            'total_usd',
                v_available_money_usd
        );


    -- ==========================================================
    -- CURRENCY SUMMARY
    --
    -- Existing response structure is preserved.
    --
    -- These fields continue to represent the detailed financial
    -- positions/activity. They are not used to infer Money In.
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

          AND fp.fiscal_year =
              v_fiscal_year

    ),

    currency_summary AS (

        SELECT
            cp.currency_code,

            -- ==================================================
            -- DEPOSIT
            -- ==================================================

            SUM(
                cp.deposit_amount
            ) AS deposit_amount,

            SUM(
                cp.deposit_amount_usd
            ) AS deposit_amount_usd,


            -- ==================================================
            -- WITHDRAWAL
            -- ==================================================

            SUM(
                cp.withdrawal_amount
            ) AS withdrawal_amount,

            SUM(
                cp.withdrawal_amount_usd
            ) AS withdrawal_amount_usd,


            -- ==================================================
            -- SPENDING
            -- ==================================================

            SUM(
                cp.spending_amount
            ) AS spending_amount,

            SUM(
                cp.spending_amount_usd
            ) AS spending_amount_usd,


            -- ==================================================
            -- SAVINGS ACTIVITY
            -- ==================================================

            SUM(
                cp.savings_inflow
            ) AS savings_inflow,

            SUM(
                cp.savings_inflow_usd
            ) AS savings_inflow_usd,

            SUM(
                cp.savings_outflow
            ) AS savings_outflow,

            SUM(
                cp.savings_outflow_usd
            ) AS savings_outflow_usd,

            SUM(
                cp.saving_amount
            ) AS saving_amount,

            SUM(
                cp.saving_amount_usd
            ) AS saving_amount_usd,


            -- ==================================================
            -- SAVINGS POSITION
            -- ==================================================

            MAX(
                cp.opening_savings
            )
            FILTER (
                WHERE cp.first_period_row = 1
            ) AS opening_savings,

            MAX(
                cp.opening_savings_usd
            )
            FILTER (
                WHERE cp.first_period_row = 1
            ) AS opening_savings_usd,

            MAX(
                cp.closing_savings
            )
            FILTER (
                WHERE cp.last_period_row = 1
            ) AS closing_savings,

            MAX(
                cp.closing_savings_usd
            )
            FILTER (
                WHERE cp.last_period_row = 1
            ) AS closing_savings_usd,


            -- ==================================================
            -- INVESTMENT
            -- ==================================================

            SUM(
                cp.investment_purchase_amount
            ) AS investment_purchase_amount,

            SUM(
                cp.investment_purchase_amount_usd
            ) AS investment_purchase_amount_usd,

            SUM(
                cp.investment_sale_amount
            ) AS investment_sale_amount,

            SUM(
                cp.investment_sale_amount_usd
            ) AS investment_sale_amount_usd,


            -- ==================================================
            -- LOAN ACTIVITY
            -- ==================================================

            SUM(
                cp.loan_disbursed_amount
            ) AS loan_disbursed_amount,

            SUM(
                cp.loan_disbursed_amount_usd
            ) AS loan_disbursed_amount_usd,

            SUM(
                cp.loan_repayment_amount
            ) AS loan_repayment_amount,

            SUM(
                cp.loan_repayment_amount_usd
            ) AS loan_repayment_amount_usd,

            SUM(
                cp.loan_principal_repaid
            ) AS loan_principal_repaid,

            SUM(
                cp.loan_principal_repaid_usd
            ) AS loan_principal_repaid_usd,

            SUM(
                cp.loan_interest_repaid
            ) AS loan_interest_repaid,

            SUM(
                cp.loan_interest_repaid_usd
            ) AS loan_interest_repaid_usd,

            SUM(
                cp.loan_interest_accrued
            ) AS loan_interest_accrued,

            SUM(
                cp.loan_interest_accrued_usd
            ) AS loan_interest_accrued_usd,


            -- ==================================================
            -- LOAN POSITION
            -- ==================================================

            MAX(
                cp.opening_loan_balance
            )
            FILTER (
                WHERE cp.first_period_row = 1
            ) AS opening_loan_balance,

            MAX(
                cp.opening_loan_balance_usd
            )
            FILTER (
                WHERE cp.first_period_row = 1
            ) AS opening_loan_balance_usd,

            MAX(
                cp.closing_loan_balance
            )
            FILTER (
                WHERE cp.last_period_row = 1
            ) AS closing_loan_balance,

            MAX(
                cp.closing_loan_balance_usd
            )
            FILTER (
                WHERE cp.last_period_row = 1
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

    WHERE e.user_id =
          v_user_id

      AND e.fiscal_year =
          v_fiscal_year;


    -- ==========================================================
    -- GOLD OPENING POSITION
    -- ==========================================================

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

    WHERE e.user_id =
          v_user_id

      AND e.fiscal_year <
          v_fiscal_year;


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


        -- ======================================================
        -- SOURCE OF MONEY
        --
        -- Savings B/F
        -- + Cash In
        -- + Transfer In
        -- + Loan Disbursement
        -- + Investment Proceeds
        -- ======================================================

        'money_in',
            v_money_in,


        -- ======================================================
        -- DISTRIBUTION OF AVAILABLE MONEY
        -- ======================================================

        'distribution',
            v_distribution,


        -- ======================================================
        -- FISCAL-YEAR CONSOLIDATED BEHAVIOR
        -- ======================================================

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


        -- ======================================================
        -- CURRENT PERIOD CONSOLIDATED BEHAVIOR
        -- ======================================================

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


        -- ======================================================
        -- EXISTING RESPONSE FIELDS
        -- ======================================================

        'currencies',
            v_currencies,

        'gold',
            v_gold

    );

END;
$function$;