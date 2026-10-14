CREATE OR REPLACE FUNCTION public.record_financial_activity(
    p_reference text,
    p_user_id text,
    p_country_code text,
    p_currency_code text,
    p_transaction_type text,
    p_activity_type public.financial_activity_type,
    p_amount numeric DEFAULT 0,
    p_amount_usd numeric DEFAULT 0,
    p_cash_amount numeric DEFAULT 0,
    p_cash_amount_usd numeric DEFAULT 0,
    p_gold_quantity numeric DEFAULT 0,
    p_investment_cost_usd numeric DEFAULT 0,
    p_principal_amount numeric DEFAULT 0,
    p_principal_amount_usd numeric DEFAULT 0,
    p_interest_amount numeric DEFAULT 0,
    p_interest_amount_usd numeric DEFAULT 0
)
RETURNS public.financial_pot
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
    v_event_id uuid;

    v_fiscal_year integer;
    v_period integer;

    v_country_code text;
    v_currency_code text;
    v_transaction_type text;

    v_is_seed boolean := false;

    v_cash_amount numeric(20, 6) := 0;
    v_cash_amount_usd numeric(20, 6) := 0;

    v_opening_savings numeric(20, 6) := 0;
    v_opening_savings_usd numeric(20, 6) := 0;

    v_opening_gold_quantity numeric(20, 6) := 0;
    v_opening_investment_usd numeric(20, 6) := 0;

    v_opening_loan_balance numeric(20, 6) := 0;
    v_opening_loan_balance_usd numeric(20, 6) := 0;

    v_result public.financial_pot;
BEGIN

    -- ==========================================================
    -- NORMALIZE
    -- ==========================================================

    v_country_code :=
        lower(trim(p_country_code));

    v_currency_code :=
        lower(trim(p_currency_code));

    v_transaction_type :=
        lower(trim(p_transaction_type));

    v_is_seed :=
        v_transaction_type LIKE 'initial\_%' ESCAPE '\';


    -- ==========================================================
    -- VALIDATION
    -- ==========================================================

    IF p_reference IS NULL
       OR trim(p_reference) = '' THEN
        RAISE EXCEPTION
            'FINANCIAL_ACTIVITY_REFERENCE_REQUIRED';
    END IF;

    IF p_user_id IS NULL
       OR trim(p_user_id) = '' THEN
        RAISE EXCEPTION
            'FINANCIAL_ACTIVITY_USER_REQUIRED';
    END IF;

    IF p_country_code IS NULL
       OR trim(p_country_code) = '' THEN
        RAISE EXCEPTION
            'FINANCIAL_ACTIVITY_COUNTRY_REQUIRED';
    END IF;

    IF p_currency_code IS NULL
       OR trim(p_currency_code) = '' THEN
        RAISE EXCEPTION
            'FINANCIAL_ACTIVITY_CURRENCY_REQUIRED';
    END IF;

    IF p_transaction_type IS NULL
       OR trim(p_transaction_type) = '' THEN
        RAISE EXCEPTION
            'FINANCIAL_ACTIVITY_TRANSACTION_TYPE_REQUIRED';
    END IF;

    IF p_activity_type IS NULL THEN
        RAISE EXCEPTION
            'FINANCIAL_ACTIVITY_TYPE_REQUIRED';
    END IF;

    IF COALESCE(p_amount, 0) < 0
       OR COALESCE(p_amount_usd, 0) < 0
       OR COALESCE(p_cash_amount, 0) < 0
       OR COALESCE(p_cash_amount_usd, 0) < 0
       OR COALESCE(p_gold_quantity, 0) < 0
       OR COALESCE(p_investment_cost_usd, 0) < 0
       OR COALESCE(p_principal_amount, 0) < 0
       OR COALESCE(p_principal_amount_usd, 0) < 0
       OR COALESCE(p_interest_amount, 0) < 0
       OR COALESCE(p_interest_amount_usd, 0) < 0
    THEN
        RAISE EXCEPTION
            'FINANCIAL_ACTIVITY_NEGATIVE_VALUE';
    END IF;


    -- ==========================================================
    -- CASH FLOW VALUE
    --
    -- cash_amount is authoritative when supplied.
    --
    -- For older callers that supplied zero, fall back to amount
    -- for normal cash-moving activities.
    --
    -- Seed events intentionally do not use this fallback because
    -- they represent brought-forward/opening state.
    -- ==========================================================

    IF NOT v_is_seed
       AND p_activity_type IN (
           'deposit'::public.financial_activity_type,
           'withdrawal'::public.financial_activity_type,
           'spending'::public.financial_activity_type,
           'investment_buy'::public.financial_activity_type,
           'investment_sell'::public.financial_activity_type,
           'loan_disbursement'::public.financial_activity_type,
           'loan_repayment'::public.financial_activity_type
       )
    THEN
        v_cash_amount :=
            CASE
                WHEN COALESCE(p_cash_amount, 0) > 0
                    THEN p_cash_amount
                ELSE COALESCE(p_amount, 0)
            END;

        v_cash_amount_usd :=
            CASE
                WHEN COALESCE(p_cash_amount_usd, 0) > 0
                    THEN p_cash_amount_usd
                ELSE COALESCE(p_amount_usd, 0)
            END;
    ELSE
        v_cash_amount :=
            COALESCE(
                p_cash_amount,
                0
            );

        v_cash_amount_usd :=
            COALESCE(
                p_cash_amount_usd,
                0
            );
    END IF;


    -- ==========================================================
    -- FISCAL PERIOD
    -- ==========================================================

    SELECT
        fp.fiscal_year,
        fp.period
    INTO
        v_fiscal_year,
        v_period
    FROM public.fetch_fiscal_period(
        v_country_code
    ) AS fp;

    IF NOT FOUND
       OR v_fiscal_year IS NULL
       OR v_period IS NULL THEN
        RAISE EXCEPTION
            'FISCAL_PERIOD_NOT_FOUND';
    END IF;

    IF v_period < 1
       OR v_period > 12 THEN
        RAISE EXCEPTION
            'FINANCIAL_ACTIVITY_INVALID_PERIOD';
    END IF;


    -- ==========================================================
    -- EVENT
    -- ==========================================================

    INSERT INTO public.financial_pot_event (
        reference,
        user_id,
        country_code,
        currency_code,
        fiscal_year,
        period,
        transaction_type,
        activity_type,

        amount,
        amount_usd,

        cash_amount,
        cash_amount_usd,

        gold_quantity,
        investment_cost_usd,

        principal_amount,
        principal_amount_usd,

        interest_amount,
        interest_amount_usd
    )
    VALUES (
        p_reference,
        p_user_id,
        v_country_code,
        v_currency_code,
        v_fiscal_year,
        v_period,
        v_transaction_type,
        p_activity_type,

        COALESCE(p_amount, 0),
        COALESCE(p_amount_usd, 0),

        v_cash_amount,
        v_cash_amount_usd,

        COALESCE(p_gold_quantity, 0),
        COALESCE(p_investment_cost_usd, 0),

        COALESCE(p_principal_amount, 0),
        COALESCE(p_principal_amount_usd, 0),

        COALESCE(p_interest_amount, 0),
        COALESCE(p_interest_amount_usd, 0)
    )

    ON CONFLICT (
        reference,
        user_id,
        activity_type
    )
    DO NOTHING

    RETURNING id
    INTO v_event_id;


    -- ==========================================================
    -- ALREADY RECORDED
    -- ==========================================================

    IF v_event_id IS NULL THEN

        PERFORM public.calculate_financial_behavior(
            p_user_id,
            v_country_code,
            v_currency_code,
            v_fiscal_year,
            v_period
        );

        PERFORM *
        FROM public.evaluate_financial_badges(
            p_user_id,
            v_country_code,
            v_fiscal_year,
            v_period
        );

        SELECT *
        INTO v_result
        FROM public.financial_pot
        WHERE user_id = p_user_id
          AND currency_code = v_currency_code
          AND fiscal_year = v_fiscal_year
          AND period = v_period;

        RETURN v_result;
    END IF;


    -- ==========================================================
    -- PREVIOUS POSITION
    -- ==========================================================

    SELECT
        closing_savings,
        closing_savings_usd,

        closing_gold_quantity,
        closing_investment_usd,

        closing_loan_balance,
        closing_loan_balance_usd

    INTO
        v_opening_savings,
        v_opening_savings_usd,

        v_opening_gold_quantity,
        v_opening_investment_usd,

        v_opening_loan_balance,
        v_opening_loan_balance_usd

    FROM public.financial_pot

    WHERE user_id = p_user_id
      AND currency_code = v_currency_code

      AND (
            fiscal_year < v_fiscal_year
            OR (
                fiscal_year = v_fiscal_year
                AND period < v_period
            )
      )

    ORDER BY
        fiscal_year DESC,
        period DESC

    LIMIT 1;


    v_opening_savings :=
        COALESCE(v_opening_savings, 0);

    v_opening_savings_usd :=
        COALESCE(v_opening_savings_usd, 0);

    v_opening_gold_quantity :=
        COALESCE(v_opening_gold_quantity, 0);

    v_opening_investment_usd :=
        COALESCE(v_opening_investment_usd, 0);

    v_opening_loan_balance :=
        COALESCE(v_opening_loan_balance, 0);

    v_opening_loan_balance_usd :=
        COALESCE(v_opening_loan_balance_usd, 0);


    -- ==========================================================
    -- CREATE CURRENT POT
    -- ==========================================================

    INSERT INTO public.financial_pot (
        user_id,
        country_code,
        currency_code,

        fiscal_year,
        period,

        opening_savings,
        opening_savings_usd,

        closing_savings,
        closing_savings_usd,

        opening_gold_quantity,
        closing_gold_quantity,

        opening_investment_usd,
        closing_investment_usd,

        opening_loan_balance,
        opening_loan_balance_usd,

        closing_loan_balance,
        closing_loan_balance_usd
    )
    VALUES (
        p_user_id,
        v_country_code,
        v_currency_code,

        v_fiscal_year,
        v_period,

        v_opening_savings,
        v_opening_savings_usd,

        v_opening_savings,
        v_opening_savings_usd,

        v_opening_gold_quantity,
        v_opening_gold_quantity,

        v_opening_investment_usd,
        v_opening_investment_usd,

        v_opening_loan_balance,
        v_opening_loan_balance_usd,

        v_opening_loan_balance,
        v_opening_loan_balance_usd
    )

    ON CONFLICT (
        user_id,
        currency_code,
        fiscal_year,
        period
    )
    DO NOTHING;


    -- ==========================================================
    -- INITIAL / BROUGHT-FORWARD EVENTS
    --
    -- Seeds establish opening positions. They are NOT current
    -- period deposits, borrowing, repayments or investments.
    -- ==========================================================

    IF v_is_seed THEN

        CASE v_transaction_type

            WHEN 'initial_savings_seed' THEN

                UPDATE public.financial_pot
                SET
                    opening_savings =
                        opening_savings
                        + COALESCE(p_amount, 0),

                    opening_savings_usd =
                        opening_savings_usd
                        + COALESCE(p_amount_usd, 0),

                    updated_at = now()

                WHERE user_id = p_user_id
                  AND currency_code = v_currency_code
                  AND fiscal_year = v_fiscal_year
                  AND period = v_period;


            WHEN 'initial_gold_seed' THEN

                UPDATE public.financial_pot
                SET
                    opening_gold_quantity =
                        opening_gold_quantity
                        + COALESCE(p_gold_quantity, 0),

                    opening_investment_usd =
                        opening_investment_usd
                        + COALESCE(
                            p_investment_cost_usd,
                            0
                        ),

                    updated_at = now()

                WHERE user_id = p_user_id
                  AND currency_code = v_currency_code
                  AND fiscal_year = v_fiscal_year
                  AND period = v_period;


            WHEN 'initial_loan_seed' THEN

                UPDATE public.financial_pot
                SET
                    opening_loan_balance =
                        opening_loan_balance
                        + COALESCE(
                            NULLIF(
                                p_principal_amount,
                                0
                            ),
                            p_amount,
                            0
                        ),

                    opening_loan_balance_usd =
                        opening_loan_balance_usd
                        + COALESCE(
                            NULLIF(
                                p_principal_amount_usd,
                                0
                            ),
                            p_amount_usd,
                            0
                        ),

                    updated_at = now()

                WHERE user_id = p_user_id
                  AND currency_code = v_currency_code
                  AND fiscal_year = v_fiscal_year
                  AND period = v_period;


            WHEN 'initial_loan_interest_seed' THEN

                UPDATE public.financial_pot
                SET
                    opening_loan_balance =
                        opening_loan_balance
                        + COALESCE(
                            p_interest_amount,
                            0
                        ),

                    opening_loan_balance_usd =
                        opening_loan_balance_usd
                        + COALESCE(
                            p_interest_amount_usd,
                            0
                        ),

                    updated_at = now()

                WHERE user_id = p_user_id
                  AND currency_code = v_currency_code
                  AND fiscal_year = v_fiscal_year
                  AND period = v_period;


            WHEN 'initial_loan_repayment_seed' THEN

                UPDATE public.financial_pot
                SET
                    opening_loan_balance =
                        GREATEST(
                            opening_loan_balance
                            - COALESCE(
                                p_principal_amount,
                                0
                            )
                            - COALESCE(
                                p_interest_amount,
                                0
                            ),
                            0
                        ),

                    opening_loan_balance_usd =
                        GREATEST(
                            opening_loan_balance_usd
                            - COALESCE(
                                p_principal_amount_usd,
                                0
                            )
                            - COALESCE(
                                p_interest_amount_usd,
                                0
                            ),
                            0
                        ),

                    updated_at = now()

                WHERE user_id = p_user_id
                  AND currency_code = v_currency_code
                  AND fiscal_year = v_fiscal_year
                  AND period = v_period;


            ELSE
                NULL;

        END CASE;


    ELSE

        -- ======================================================
        -- NORMAL CURRENT-PERIOD ACTIVITY
        -- ======================================================

        CASE p_activity_type

            WHEN 'deposit' THEN

                UPDATE public.financial_pot
                SET
                    deposit_amount =
                        deposit_amount
                        + COALESCE(p_amount, 0),

                    deposit_amount_usd =
                        deposit_amount_usd
                        + COALESCE(p_amount_usd, 0),

                    savings_inflow =
                        savings_inflow
                        + v_cash_amount,

                    savings_inflow_usd =
                        savings_inflow_usd
                        + v_cash_amount_usd,

                    updated_at = now()

                WHERE user_id = p_user_id
                  AND currency_code = v_currency_code
                  AND fiscal_year = v_fiscal_year
                  AND period = v_period;


            WHEN 'withdrawal' THEN

                UPDATE public.financial_pot
                SET
                    withdrawal_amount =
                        withdrawal_amount
                        + COALESCE(p_amount, 0),

                    withdrawal_amount_usd =
                        withdrawal_amount_usd
                        + COALESCE(p_amount_usd, 0),

                    savings_outflow =
                        savings_outflow
                        + v_cash_amount,

                    savings_outflow_usd =
                        savings_outflow_usd
                        + v_cash_amount_usd,

                    updated_at = now()

                WHERE user_id = p_user_id
                  AND currency_code = v_currency_code
                  AND fiscal_year = v_fiscal_year
                  AND period = v_period;


            WHEN 'spending' THEN

                UPDATE public.financial_pot
                SET
                    spending_amount =
                        spending_amount
                        + COALESCE(p_amount, 0),

                    spending_amount_usd =
                        spending_amount_usd
                        + COALESCE(p_amount_usd, 0),

                    savings_outflow =
                        savings_outflow
                        + v_cash_amount,

                    savings_outflow_usd =
                        savings_outflow_usd
                        + v_cash_amount_usd,

                    updated_at = now()

                WHERE user_id = p_user_id
                  AND currency_code = v_currency_code
                  AND fiscal_year = v_fiscal_year
                  AND period = v_period;


            WHEN 'investment_buy' THEN

                UPDATE public.financial_pot
                SET
                    investment_purchase_amount =
                        investment_purchase_amount
                        + COALESCE(p_amount, 0),

                    investment_purchase_amount_usd =
                        investment_purchase_amount_usd
                        + COALESCE(p_amount_usd, 0),

                    gold_purchased =
                        gold_purchased
                        + COALESCE(p_gold_quantity, 0),

                    investment_inflow_usd =
                        investment_inflow_usd
                        + COALESCE(
                            p_investment_cost_usd,
                            0
                        ),

                    savings_outflow =
                        savings_outflow
                        + v_cash_amount,

                    savings_outflow_usd =
                        savings_outflow_usd
                        + v_cash_amount_usd,

                    updated_at = now()

                WHERE user_id = p_user_id
                  AND currency_code = v_currency_code
                  AND fiscal_year = v_fiscal_year
                  AND period = v_period;


            WHEN 'investment_sell' THEN

                UPDATE public.financial_pot
                SET
                    investment_sale_amount =
                        investment_sale_amount
                        + COALESCE(p_amount, 0),

                    investment_sale_amount_usd =
                        investment_sale_amount_usd
                        + COALESCE(p_amount_usd, 0),

                    gold_sold =
                        gold_sold
                        + COALESCE(p_gold_quantity, 0),

                    investment_outflow_usd =
                        investment_outflow_usd
                        + COALESCE(
                            p_investment_cost_usd,
                            0
                        ),

                    deposit_amount =
                        deposit_amount
                        + v_cash_amount,

                    deposit_amount_usd =
                        deposit_amount_usd
                        + v_cash_amount_usd,

                    savings_inflow =
                        savings_inflow
                        + v_cash_amount,

                    savings_inflow_usd =
                        savings_inflow_usd
                        + v_cash_amount_usd,

                    updated_at = now()

                WHERE user_id = p_user_id
                  AND currency_code = v_currency_code
                  AND fiscal_year = v_fiscal_year
                  AND period = v_period;


            WHEN 'investment_transfer_in' THEN

                UPDATE public.financial_pot
                SET
                    gold_transferred_in =
                        gold_transferred_in
                        + COALESCE(
                            p_gold_quantity,
                            0
                        ),

                    investment_inflow_usd =
                        investment_inflow_usd
                        + COALESCE(
                            p_investment_cost_usd,
                            0
                        ),

                    updated_at = now()

                WHERE user_id = p_user_id
                  AND currency_code = v_currency_code
                  AND fiscal_year = v_fiscal_year
                  AND period = v_period;


            WHEN 'investment_transfer_out' THEN

                UPDATE public.financial_pot
                SET
                    gold_transferred_out =
                        gold_transferred_out
                        + COALESCE(
                            p_gold_quantity,
                            0
                        ),

                    investment_outflow_usd =
                        investment_outflow_usd
                        + COALESCE(
                            p_investment_cost_usd,
                            0
                        ),

                    updated_at = now()

                WHERE user_id = p_user_id
                  AND currency_code = v_currency_code
                  AND fiscal_year = v_fiscal_year
                  AND period = v_period;


            WHEN 'loan_disbursement' THEN

                UPDATE public.financial_pot
                SET
                    loan_disbursed_amount =
                        loan_disbursed_amount
                        + COALESCE(p_amount, 0),

                    loan_disbursed_amount_usd =
                        loan_disbursed_amount_usd
                        + COALESCE(p_amount_usd, 0),

                    deposit_amount =
                        deposit_amount
                        + v_cash_amount,

                    deposit_amount_usd =
                        deposit_amount_usd
                        + v_cash_amount_usd,

                    savings_inflow =
                        savings_inflow
                        + v_cash_amount,

                    savings_inflow_usd =
                        savings_inflow_usd
                        + v_cash_amount_usd,

                    updated_at = now()

                WHERE user_id = p_user_id
                  AND currency_code = v_currency_code
                  AND fiscal_year = v_fiscal_year
                  AND period = v_period;


            WHEN 'loan_repayment' THEN

                UPDATE public.financial_pot
                SET
                    loan_repayment_amount =
                        loan_repayment_amount
                        + COALESCE(p_amount, 0),

                    loan_repayment_amount_usd =
                        loan_repayment_amount_usd
                        + COALESCE(p_amount_usd, 0),

                    loan_principal_repaid =
                        loan_principal_repaid
                        + COALESCE(
                            p_principal_amount,
                            0
                        ),

                    loan_principal_repaid_usd =
                        loan_principal_repaid_usd
                        + COALESCE(
                            p_principal_amount_usd,
                            0
                        ),

                    loan_interest_repaid =
                        loan_interest_repaid
                        + COALESCE(
                            p_interest_amount,
                            0
                        ),

                    loan_interest_repaid_usd =
                        loan_interest_repaid_usd
                        + COALESCE(
                            p_interest_amount_usd,
                            0
                        ),

                    savings_outflow =
                        savings_outflow
                        + v_cash_amount,

                    savings_outflow_usd =
                        savings_outflow_usd
                        + v_cash_amount_usd,

                    updated_at = now()

                WHERE user_id = p_user_id
                  AND currency_code = v_currency_code
                  AND fiscal_year = v_fiscal_year
                  AND period = v_period;


            WHEN 'loan_interest_accrual' THEN

                UPDATE public.financial_pot
                SET
                    loan_interest_accrued =
                        loan_interest_accrued
                        + COALESCE(
                            p_interest_amount,
                            0
                        ),

                    loan_interest_accrued_usd =
                        loan_interest_accrued_usd
                        + COALESCE(
                            p_interest_amount_usd,
                            0
                        ),

                    updated_at = now()

                WHERE user_id = p_user_id
                  AND currency_code = v_currency_code
                  AND fiscal_year = v_fiscal_year
                  AND period = v_period;

        END CASE;

    END IF;


    -- ==========================================================
    -- RECALCULATE POSITIONS
    -- ==========================================================

    UPDATE public.financial_pot
    SET
        closing_savings =
            GREATEST(
                opening_savings
                + savings_inflow
                - savings_outflow,
                0
            ),

        closing_savings_usd =
            GREATEST(
                opening_savings_usd
                + savings_inflow_usd
                - savings_outflow_usd,
                0
            ),

        saving_amount =
            GREATEST(
                savings_inflow
                - savings_outflow,
                0
            ),

        saving_amount_usd =
            GREATEST(
                savings_inflow_usd
                - savings_outflow_usd,
                0
            ),

        closing_gold_quantity =
            GREATEST(
                opening_gold_quantity
                + gold_purchased
                + gold_transferred_in
                - gold_sold
                - gold_transferred_out,
                0
            ),

        closing_investment_usd =
            GREATEST(
                opening_investment_usd
                + investment_inflow_usd
                - investment_outflow_usd,
                0
            ),

        closing_loan_balance =
            GREATEST(
                opening_loan_balance
                + loan_disbursed_amount
                + loan_interest_accrued
                - loan_principal_repaid
                - loan_interest_repaid,
                0
            ),

        closing_loan_balance_usd =
            GREATEST(
                opening_loan_balance_usd
                + loan_disbursed_amount_usd
                + loan_interest_accrued_usd
                - loan_principal_repaid_usd
                - loan_interest_repaid_usd,
                0
            ),

        updated_at = now()

    WHERE user_id = p_user_id
      AND currency_code = v_currency_code
      AND fiscal_year = v_fiscal_year
      AND period = v_period;


    -- ==========================================================
    -- DERIVED INTELLIGENCE
    -- ==========================================================

    PERFORM public.calculate_financial_behavior(
        p_user_id,
        v_country_code,
        v_currency_code,
        v_fiscal_year,
        v_period
    );

    PERFORM *
    FROM public.evaluate_financial_badges(
        p_user_id,
        v_country_code,
        v_fiscal_year,
        v_period
    );


    -- ==========================================================
    -- RESULT
    -- ==========================================================

    SELECT *
    INTO v_result
    FROM public.financial_pot
    WHERE user_id = p_user_id
      AND currency_code = v_currency_code
      AND fiscal_year = v_fiscal_year
      AND period = v_period;

    RETURN v_result;

END;
$function$;