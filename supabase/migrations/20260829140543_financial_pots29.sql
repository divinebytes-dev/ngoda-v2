DO $$
DECLARE
    v_loan record;

    v_rate numeric;
    v_principal_usd numeric(20, 2);

    v_reference text;

BEGIN

    /*
     * ==========================================================
     * TEST BOOTSTRAP
     * ==========================================================
     *
     * Seed existing loans into Financial Intelligence.
     *
     * We establish the borrowing position using loan.principal.
     *
     * IMPORTANT:
     *
     * cash_amount = 0
     *
     * because current wallet balances have already been
     * bootstrapped separately into Savings.
     *
     * We must not increase Savings a second time.
     * ==========================================================
     */

    FOR v_loan IN

        SELECT
            l.id,
            l.user_id,
            lower(l.country_code) AS country_code,
            lower(l.currency_code) AS currency_code,
            l.fiscal_year,
            l.period,
            l.document_number,
            l.reference,
            l.principal

        FROM public.loan AS l

        WHERE l.status IN (
            'active'
        )
          AND l.principal > 0

        ORDER BY
            l.user_id,
            l.created_at

    LOOP

        /*
         * ======================================================
         * USD CONVERSION
         * ======================================================
         */

        IF v_loan.currency_code = 'usd' THEN

            v_principal_usd :=
                round(
                    v_loan.principal,
                    2
                );

        ELSE

            /*
             * Existing rate convention:
             *
             * rate_to_usd represents local units per USD.
             *
             * Example:
             *
             * 1 USD = 13.402226 BWP
             *
             * Therefore:
             *
             * USD = local / rate
             */
            SELECT
                cr.rate_to_usd
            INTO
                v_rate
            FROM public.current_rates AS cr
            WHERE lower(cr.code) =
                v_loan.currency_code
            LIMIT 1;


            IF NOT FOUND
               OR v_rate IS NULL
               OR v_rate <= 0 THEN

                RAISE NOTICE
                    'Skipping loan %, rate not found for %',
                    v_loan.id,
                    v_loan.currency_code;

                CONTINUE;

            END IF;


            v_principal_usd :=
                round(
                    v_loan.principal / v_rate,
                    2
                );

        END IF;


        /*
         * Use the loan ID so every loan gets a unique,
         * deterministic bootstrap reference.
         */
        v_reference :=
              'INITIAL-LOAN-'
            || v_loan.id::text;


        PERFORM public.record_financial_activity(
            p_reference :=
                v_reference,

            p_user_id :=
                v_loan.user_id,

            p_country_code :=
                v_loan.country_code,

            p_currency_code :=
                v_loan.currency_code,

            p_fiscal_year :=
                v_loan.fiscal_year,

            p_period :=
                v_loan.period,

            p_transaction_type :=
                'initial_loan_seed',

            p_activity_type :=
                'loan_disbursement'::public.financial_activity_type,

            /*
             * Loan position.
             */
            p_amount :=
                v_loan.principal,

            p_amount_usd :=
                v_principal_usd,

            /*
             * Do NOT increase Savings during migration.
             */
            p_cash_amount :=
                0,

            p_cash_amount_usd :=
                0,

            p_gold_quantity :=
                0,

            p_investment_cost_usd :=
                0,

            p_principal_amount :=
                v_loan.principal,

            p_principal_amount_usd :=
                v_principal_usd,

            p_interest_amount :=
                0,

            p_interest_amount_usd :=
                0
        );


        RAISE NOTICE
            'Seeded loan: id=%, user=%, principal=% %, usd=%',
            v_loan.id,
            v_loan.user_id,
            v_loan.principal,
            v_loan.currency_code,
            v_principal_usd;

    END LOOP;

END;
$$;