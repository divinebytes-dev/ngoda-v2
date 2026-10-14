DO $$
DECLARE
    v_wallet record;

    v_fiscal_year integer;
    v_period integer;

    v_balance numeric(20, 6);
    v_balance_usd numeric(20, 2);

    v_rate_to_usd numeric;
    v_reference text;
BEGIN

    FOR v_wallet IN

        SELECT
            w.user_id,
            lower(w.country_code) AS country_code,
            lower(w.currency_code) AS currency_code,
            w.balance

        FROM public.wallet AS w

        WHERE w.owner_type = 'customer'
          AND w.is_active = true
          AND w.balance > 0
          AND lower(w.currency_code) <> 'gold'

        ORDER BY
            w.user_id,
            lower(w.currency_code)

    LOOP

        /*
         * Resolve fiscal period.
         */
        SELECT
            fiscal_period.fiscal_year,
            fiscal_period.period
        INTO
            v_fiscal_year,
            v_period
        FROM public.fetch_fiscal_period(
            v_wallet.country_code
        ) AS fiscal_period;

        IF NOT FOUND THEN
            RAISE NOTICE
                'FISCAL_PERIOD_NOT_FOUND user=% country=%',
                v_wallet.user_id,
                v_wallet.country_code;

            CONTINUE;
        END IF;


        v_balance := v_wallet.balance;


        /*
         * Convert to USD.
         */
        IF v_wallet.currency_code = 'usd' THEN

            v_rate_to_usd := 1;

            v_balance_usd :=
                ROUND(
                    v_balance::numeric,
                    2
                );

        ELSE

            SELECT
                r.rate_to_usd
            INTO
                v_rate_to_usd
            FROM public.current_rates AS r
            WHERE lower(r.code) =
                v_wallet.currency_code
            ORDER BY
                r.updated_at DESC
            LIMIT 1;

            IF NOT FOUND
               OR v_rate_to_usd IS NULL
               OR v_rate_to_usd <= 0 THEN

                RAISE NOTICE
                    'RATE_NOT_FOUND user=% currency=%',
                    v_wallet.user_id,
                    v_wallet.currency_code;

                CONTINUE;
            END IF;

            v_balance_usd :=
                ROUND(
                    (
                        v_balance /
                        v_rate_to_usd
                    )::numeric,
                    2
                );

        END IF;


        /*
         * One bootstrap event per user + currency.
         */
        v_reference :=
            'INITIAL-SAVINGS-' ||
            v_wallet.user_id ||
            '-' ||
            v_wallet.currency_code;


        RAISE NOTICE
            'Processing user=% currency=% native=% usd=%',
            v_wallet.user_id,
            v_wallet.currency_code,
            v_balance,
            v_balance_usd;


        PERFORM public.record_financial_activity(
            p_reference =>
                v_reference,

            p_user_id =>
                v_wallet.user_id,

            p_country_code =>
                v_wallet.country_code,

            p_currency_code =>
                v_wallet.currency_code,

            p_fiscal_year =>
                v_fiscal_year,

            p_period =>
                v_period,

            p_transaction_type =>
                'initial_savings_seed',

            p_activity_type =>
                'deposit'::public.financial_activity_type,

            p_amount =>
                v_balance,

            p_amount_usd =>
                v_balance_usd,

            p_cash_amount =>
                v_balance,

            p_cash_amount_usd =>
                v_balance_usd,

            p_gold_quantity =>
                0,

            p_investment_cost_usd =>
                0,

            p_principal_amount =>
                0,

            p_principal_amount_usd =>
                0,

            p_interest_amount =>
                0,

            p_interest_amount_usd =>
                0
        );


        RAISE NOTICE
            'SEEDED user=% currency=%',
            v_wallet.user_id,
            v_wallet.currency_code;

    END LOOP;

END;
$$;