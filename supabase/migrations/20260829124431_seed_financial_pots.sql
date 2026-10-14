DO $$
DECLARE
    v_wallet record;

    v_fiscal_year integer;
    v_period integer;

    v_balance numeric(20, 6);
    v_balance_usd numeric(20, 2);

    v_rate_to_usd numeric;
BEGIN

    FOR v_wallet IN

        SELECT
            w.user_id,
            w.country_code,
            lower(w.currency_code) AS currency_code,
            w.balance

        FROM public.wallet w

        WHERE w.owner_type = 'customer'
          AND w.is_active = true
          AND w.balance > 0

    LOOP

        /*
         * Fetch fiscal period using the wallet country.
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


        /*
         * Native wallet balance.
         */
        v_balance := v_wallet.balance;


        /*
         * USD does not require conversion.
         */
        IF v_wallet.currency_code = 'usd' THEN

            v_rate_to_usd := 1;

            v_balance_usd :=
                ROUND(
                    v_balance::numeric,
                    2
                );

        ELSE

            /*
             * Fetch latest/current fiat rate.
             *
             * Example:
             * 1 USD = 13.402226 BWP
             */
            SELECT
                r.rate_to_usd

            INTO
                v_rate_to_usd

            FROM public.current_rates r

            WHERE lower(r.code) =
                v_wallet.currency_code

            ORDER BY r.updated_at DESC

            LIMIT 1;


            IF NOT FOUND
               OR v_rate_to_usd IS NULL
               OR v_rate_to_usd <= 0 THEN

                RAISE NOTICE
                    'RATE_NOT_FOUND currency=% user=%',
                    v_wallet.currency_code,
                    v_wallet.user_id;

                CONTINUE;

            END IF;


            /*
             * rate_to_usd represents:
             *
             * 1 USD = rate_to_usd units of currency.
             *
             * Therefore:
             *
             * currency / rate = USD
             */
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
         * Seed Financial Intelligence.
         *
         * TEST DATA:
         *
         * We are treating the current wallet balance as if it
         * were savings accumulated during the current period.
         *
         * Production transactions will populate these values
         * through record_financial_activity().
         */
        INSERT INTO public.financial_pot (
            user_id,
            country_code,
            currency_code,
            fiscal_year,
            period,

            opening_savings,
            savings_inflow,
            savings_outflow,
            closing_savings,

            opening_savings_usd,
            savings_inflow_usd,
            savings_outflow_usd,
            closing_savings_usd,

            saving_amount,
            saving_amount_usd,

            created_at,
            updated_at
        )
        VALUES (
            v_wallet.user_id,
            v_wallet.country_code,
            v_wallet.currency_code,
            v_fiscal_year,
            v_period,

            0,
            v_balance,
            0,
            v_balance,

            0,
            v_balance_usd,
            0,
            v_balance_usd,

            v_balance,
            v_balance_usd,

            now(),
            now()
        )

        ON CONFLICT (
            user_id,
            currency_code,
            fiscal_year,
            period
        )

        DO UPDATE SET

            country_code =
                EXCLUDED.country_code,

            opening_savings =
                0,

            savings_inflow =
                EXCLUDED.savings_inflow,

            savings_outflow =
                0,

            closing_savings =
                EXCLUDED.closing_savings,

            opening_savings_usd =
                0,

            savings_inflow_usd =
                EXCLUDED.savings_inflow_usd,

            savings_outflow_usd =
                0,

            closing_savings_usd =
                EXCLUDED.closing_savings_usd,

            saving_amount =
                EXCLUDED.saving_amount,

            saving_amount_usd =
                EXCLUDED.saving_amount_usd,

            updated_at =
                now();


        RAISE NOTICE
            'Seeded user=% currency=% balance=% usd=% rate=% FY=% period=%',
            v_wallet.user_id,
            v_wallet.currency_code,
            v_balance,
            v_balance_usd,
            v_rate_to_usd,
            v_fiscal_year,
            v_period;

    END LOOP;

END;
$$;