DO $$
DECLARE
    v_wallet record;

    v_fiscal_year integer;
    v_period integer;

    v_reference text;

BEGIN

    /*
     * ==========================================================
     * TEST BOOTSTRAP
     * ==========================================================
     *
     * Seed current customer GOLD wallet balances into
     * Financial Intelligence.
     *
     * IMPORTANT:
     *
     * Existing wallet gold is NOT treated as investment_buy.
     *
     * We do not know from the wallet balance whether the gold
     * was:
     *
     * - purchased
     * - transferred in
     * - otherwise acquired
     *
     * Therefore we bootstrap it as investment_transfer_in.
     *
     * This establishes the gold position without incorrectly
     * awarding Investor behaviour / badges.
     * ==========================================================
     */

    FOR v_wallet IN

        SELECT
            w.user_id,
            lower(w.country_code) AS country_code,
            SUM(w.balance) AS gold_balance

        FROM public.wallet AS w

        WHERE w.owner_type = 'customer'
          AND w.is_active = true
          AND lower(w.currency_code) = 'gold'
          AND w.balance > 0

        GROUP BY
            w.user_id,
            lower(w.country_code)

        ORDER BY
            w.user_id

    LOOP

        /*
         * Resolve fiscal period using the wallet country.
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
                'Skipping gold for user %, fiscal period not found for country %',
                v_wallet.user_id,
                v_wallet.country_code;

            CONTINUE;

        END IF;


        /*
         * Deterministic reference makes the bootstrap idempotent.
         */
        v_reference :=
              'INITIAL-GOLD-'
            || v_wallet.user_id;


        /*
         * Establish current gold position.
         *
         * No fiat amount is recorded because this is not being
         * classified as an investment purchase.
         */
        PERFORM public.record_financial_activity(
            p_reference :=
                v_reference,

            p_user_id :=
                v_wallet.user_id,

            p_country_code :=
                v_wallet.country_code,

            /*
             * Gold itself is the position being affected.
             */
            p_currency_code :=
                'gold',

            p_fiscal_year :=
                v_fiscal_year,

            p_period :=
                v_period,

            p_transaction_type :=
                'initial_gold_seed',

            p_activity_type :=
                'investment_transfer_in'::public.financial_activity_type,

            p_amount :=
                0,

            p_amount_usd :=
                0,

            p_cash_amount :=
                0,

            p_cash_amount_usd :=
                0,

            p_gold_quantity :=
                v_wallet.gold_balance,

            p_investment_cost_usd :=
                0,

            p_principal_amount :=
                0,

            p_principal_amount_usd :=
                0,

            p_interest_amount :=
                0,

            p_interest_amount_usd :=
                0
        );


        RAISE NOTICE
            'Seeded gold: user=%, quantity=%',
            v_wallet.user_id,
            v_wallet.gold_balance;

    END LOOP;

END;
$$;