DO $$
DECLARE
    v_entry record;

    v_rate numeric;

    v_principal_amount numeric(20, 6);
    v_interest_amount numeric(20, 6);
    v_total_amount numeric(20, 6);

    v_principal_usd numeric(20, 2);
    v_interest_usd numeric(20, 2);
    v_total_usd numeric(20, 2);

    v_activity_type public.financial_activity_type;
    v_reference text;

BEGIN

    /*
     * ==========================================================
     * REPLAY EXISTING LOAN ENTRIES
     * ==========================================================
     *
     * Supported:
     *
     * interest_accrual
     * repayment
     *
     * The loan table provides user ownership.
     * ==========================================================
     */

    FOR v_entry IN

        SELECT
            le.id,
            le.loan_id,
            le.fiscal_year,
            le.period,
            lower(le.country_code) AS country_code,
            lower(le.currency_code) AS currency_code,
            le.document_number,
            le.reference,
            le.entry_type,

            COALESCE(
                le.debit_principal,
                0
            ) AS debit_principal,

            COALESCE(
                le.credit_principal,
                0
            ) AS credit_principal,

            COALESCE(
                le.debit_interest,
                0
            ) AS debit_interest,

            COALESCE(
                le.credit_interest,
                0
            ) AS credit_interest,

            l.user_id

        FROM public.loan_entry AS le

        JOIN public.loan AS l
            ON l.id = le.loan_id

        WHERE le.entry_type IN (
            'interest_accrual',
            'repayment'
        )

        ORDER BY
            le.created_at,
            le.id

    LOOP

        /*
         * ======================================================
         * DETERMINE ACTIVITY
         * ======================================================
         */

        IF v_entry.entry_type = 'interest_accrual' THEN

            v_activity_type :=
                'loan_interest_accrual'::public.financial_activity_type;

            /*
             * Interest accrual increases outstanding interest.
             */
            v_principal_amount := 0;

            v_interest_amount :=
                GREATEST(
                    v_entry.debit_interest
                    - v_entry.credit_interest,
                    0
                );


        ELSIF v_entry.entry_type = 'repayment' THEN

            v_activity_type :=
                'loan_repayment'::public.financial_activity_type;

            /*
             * Credits reduce loan principal / interest.
             */
            v_principal_amount :=
                GREATEST(
                    v_entry.credit_principal
                    - v_entry.debit_principal,
                    0
                );

            v_interest_amount :=
                GREATEST(
                    v_entry.credit_interest
                    - v_entry.debit_interest,
                    0
                );

        ELSE

            CONTINUE;

        END IF;


        v_total_amount :=
              v_principal_amount
            + v_interest_amount;


        IF v_total_amount <= 0 THEN
            CONTINUE;
        END IF;


        /*
         * ======================================================
         * USD CONVERSION
         * ======================================================
         */

        IF v_entry.currency_code = 'usd' THEN

            v_principal_usd :=
                round(
                    v_principal_amount,
                    2
                );

            v_interest_usd :=
                round(
                    v_interest_amount,
                    2
                );

        ELSE

            SELECT
                cr.rate_to_usd
            INTO
                v_rate
            FROM public.current_rates AS cr
            WHERE lower(cr.code) =
                v_entry.currency_code
            LIMIT 1;


            IF NOT FOUND
               OR v_rate IS NULL
               OR v_rate <= 0 THEN

                RAISE NOTICE
                    'Skipping loan entry %, rate not found for %',
                    v_entry.id,
                    v_entry.currency_code;

                CONTINUE;

            END IF;


            v_principal_usd :=
                round(
                    v_principal_amount / v_rate,
                    2
                );

            v_interest_usd :=
                round(
                    v_interest_amount / v_rate,
                    2
                );

        END IF;


        v_total_usd :=
              v_principal_usd
            + v_interest_usd;


        /*
         * Deterministic reference.
         *
         * loan_entry.reference can be NULL, as shown by the
         * interest accrual sample, so use the entry ID.
         */
        v_reference :=
              'INITIAL-LOAN-ENTRY-'
            || v_entry.id::text;


        PERFORM public.record_financial_activity(
            p_reference :=
                v_reference,

            p_user_id :=
                v_entry.user_id,

            p_country_code :=
                v_entry.country_code,

            p_currency_code :=
                v_entry.currency_code,

            p_fiscal_year :=
                v_entry.fiscal_year,

            p_period :=
                v_entry.period,

            p_transaction_type :=
                CASE
                    WHEN v_activity_type =
                        'loan_interest_accrual'::public.financial_activity_type
                    THEN 'initial_loan_interest_seed'

                    ELSE 'initial_loan_repayment_seed'
                END,

            p_activity_type :=
                v_activity_type,

            p_amount :=
                v_total_amount,

            p_amount_usd :=
                v_total_usd,

            /*
             * Existing wallet balance already represents the
             * current savings position.
             *
             * Therefore historical repayments must NOT reduce
             * Savings again during bootstrap.
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
                v_principal_amount,

            p_principal_amount_usd :=
                v_principal_usd,

            p_interest_amount :=
                v_interest_amount,

            p_interest_amount_usd :=
                v_interest_usd
        );


        RAISE NOTICE
            'Seeded loan entry: id=%, type=%, principal=%, interest=%',
            v_entry.id,
            v_entry.entry_type,
            v_principal_amount,
            v_interest_amount;

    END LOOP;

END;
$$;