BEGIN;

-- Remove the old two-parameter version.
DROP FUNCTION IF EXISTS
    public.build_my_treasury_dashboard(text, text);

CREATE OR REPLACE FUNCTION public.build_my_treasury_dashboard(
    p_blockchain_balances jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
    v_user public.users%rowtype;

    v_fiscal_year integer;

    v_token_supply numeric := 0;
    v_treasury_gold_balance numeric := 0;
    v_gold_reserve numeric := 0;
    v_reserve_ratio numeric := 0;

    v_blockchain jsonb;
    v_blockchain_code text;
    v_chain_id bigint;
    v_blockchain_supply numeric;
    v_blockchain_balance numeric;
    v_blockchain_gas_balance numeric;
    v_native_currency_code text;

    v_blockchain_balances jsonb := '[]'::jsonb;

    v_wallet record;
    v_balance numeric;
    v_rate numeric;
    v_usd_value numeric;

    v_wallet_balances jsonb := '[]'::jsonb;
    v_currencies jsonb := '[]'::jsonb;
BEGIN
    /*
     * 1. Authenticate Treasury user.
     */
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION USING
            ERRCODE = '42501',
            MESSAGE = 'UNAUTHORIZED';
    END IF;

    SELECT u.*
    INTO v_user
    FROM public.users u
    JOIN public.user_role r
        ON r.id = u.role_id
    WHERE u.id = auth.uid()::text
      AND u.status =
          'active'::public."UserStatus"
      AND lower(r.name::text) = 'treasury'
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION USING
            ERRCODE = '42501',
            MESSAGE = 'TREASURY_NOT_AUTHORIZED';
    END IF;

    /*
     * 2. Validate blockchain balances.
     */
    IF p_blockchain_balances IS NULL
       OR jsonb_typeof(p_blockchain_balances) <> 'array'
    THEN
        RAISE EXCEPTION USING
            MESSAGE = 'INVALID_BLOCKCHAIN_BALANCES';
    END IF;

    /*
     * 3. Process individual blockchain balances.
     *
     * token_supply:
     *   Total token supply on the blockchain.
     *
     * balance:
     *   Treasury wallet gold balance.
     *
     * gas_balance:
     *   Treasury wallet native currency balance.
     */
    FOR v_blockchain IN
        SELECT value
        FROM jsonb_array_elements(
            p_blockchain_balances
        )
    LOOP
        IF jsonb_typeof(v_blockchain) <> 'object' THEN
            RAISE EXCEPTION USING
                MESSAGE = 'INVALID_BLOCKCHAIN_BALANCE_ENTRY';
        END IF;

        v_blockchain_code :=
            nullif(
                lower(
                    btrim(
                        v_blockchain ->> 'blockchain_code'
                    )
                ),
                ''
            );

        v_native_currency_code :=
            nullif(
                upper(
                    btrim(
                        v_blockchain ->> 'native_currency_code'
                    )
                ),
                ''
            );

        IF v_blockchain_code IS NULL
           OR v_native_currency_code IS NULL
           OR nullif(v_blockchain ->> 'chain_id', '') IS NULL
           OR nullif(v_blockchain ->> 'token_supply', '') IS NULL
           OR nullif(v_blockchain ->> 'balance', '') IS NULL
           OR nullif(v_blockchain ->> 'gas_balance', '') IS NULL
        THEN
            RAISE EXCEPTION USING
                MESSAGE = 'INVALID_BLOCKCHAIN_BALANCE_ENTRY';
        END IF;

        BEGIN
            v_chain_id :=
                (v_blockchain ->> 'chain_id')::bigint;

            v_blockchain_supply :=
                (v_blockchain ->> 'token_supply')::numeric;

            v_blockchain_balance :=
                (v_blockchain ->> 'balance')::numeric;

            v_blockchain_gas_balance :=
                (v_blockchain ->> 'gas_balance')::numeric;

        EXCEPTION
            WHEN invalid_text_representation
              OR numeric_value_out_of_range
            THEN
                RAISE EXCEPTION USING
                    MESSAGE = 'INVALID_BLOCKCHAIN_BALANCE_VALUE';
        END;

        IF v_chain_id <= 0
           OR v_blockchain_supply < 0
           OR v_blockchain_balance < 0
           OR v_blockchain_gas_balance < 0
           OR v_blockchain_balance > v_blockchain_supply
        THEN
            RAISE EXCEPTION USING
                MESSAGE = 'INVALID_BLOCKCHAIN_BALANCE_VALUE';
        END IF;

        /*
         * Prevent duplicate blockchain entries.
         */
        IF EXISTS (
            SELECT 1
            FROM jsonb_array_elements(
                v_blockchain_balances
            ) AS existing(value)
            WHERE existing.value ->> 'blockchain_code'
                  = v_blockchain_code
        ) THEN
            RAISE EXCEPTION USING
                MESSAGE = 'DUPLICATE_BLOCKCHAIN_BALANCE';
        END IF;

        /*
         * Accumulate token supply across blockchains.
         */
        v_token_supply :=
            v_token_supply + v_blockchain_supply;

        /*
         * Accumulate Treasury gold balances
         * across blockchains.
         */
        v_treasury_gold_balance :=
            v_treasury_gold_balance +
            v_blockchain_balance;

        /*
         * Keep individual blockchain information.
         */
        v_blockchain_balances :=
            v_blockchain_balances ||
            jsonb_build_array(
                jsonb_build_object(
                    'blockchain_code',
                    v_blockchain_code,

                    'chain_id',
                    v_chain_id,

                    'token_supply',
                    trim_scale(
                        v_blockchain_supply
                    )::text,

                    'balance',
                    trim_scale(
                        v_blockchain_balance
                    )::text,

                    'gas_balance',
                    trim_scale(
                        v_blockchain_gas_balance
                    )::text,

                    'native_currency_code',
                    v_native_currency_code
                )
            );
    END LOOP;

    /*
     * 4. Resolve fiscal year.
     */
    SELECT fp.fiscal_year
    INTO v_fiscal_year
    FROM public.fiscal_period_config fp
    WHERE fp.country_code = 'zw'
      AND fp.opening_date <= current_date
      AND fp.closing_date >= current_date
    ORDER BY
        fp.fiscal_year DESC,
        fp.period DESC
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION USING
            MESSAGE = 'FISCAL_PERIOD_NOT_FOUND';
    END IF;

    /*
     * 5. Calculate physical gold reserve.
     *
     * Preserve existing accounting calculation.
     */
    SELECT
        coalesce(sum(ae.credit), 0) -
        coalesce(sum(ae.debit), 0)
    INTO v_gold_reserve
    FROM public.asset_entry ae
    WHERE ae.fiscal_year = v_fiscal_year;

    v_gold_reserve :=
        coalesce(v_gold_reserve, 0);

    /*
     * 6. Calculate reserve ratio.
     */
    IF v_token_supply > 0 THEN
        v_reserve_ratio :=
            v_gold_reserve / v_token_supply;
    ELSE
        v_reserve_ratio := 0;
    END IF;

    /*
     * 7. Fetch consolidated Treasury fiat balances.
     *
     * Group by currency only.
     * Do not create separate rows per blockchain.
     *
     * Exclude gold because it is calculated
     * from the blockchain balances.
     */
    FOR v_wallet IN
        SELECT
            lower(btrim(w.currency_code))
                AS currency_code,

            sum(
                coalesce(w.balance, 0)
            )::numeric AS balance

        FROM public.wallet w

        WHERE w.owner_type =
              'treasury'::public."WalletOwnerType"

          AND w.country_code =
              v_user.country_code

          AND lower(btrim(w.currency_code)) <> 'gold'

        GROUP BY
            lower(btrim(w.currency_code))

        ORDER BY
            lower(btrim(w.currency_code))
    LOOP
        v_balance := v_wallet.balance;

        /*
         * Convert fiat balance to USD.
         */
        IF v_wallet.currency_code = 'usd' THEN
            v_usd_value := v_balance;
        ELSE
            SELECT cr.rate_to_usd
            INTO v_rate
            FROM public.current_rates cr
            WHERE lower(btrim(cr.code)) =
                  v_wallet.currency_code
            LIMIT 1;

            IF NOT FOUND
               OR v_rate IS NULL
               OR v_rate <= 0
            THEN
                RAISE EXCEPTION USING
                    MESSAGE = 'MISSING_CURRENCY_RATE';
            END IF;

            v_usd_value :=
                v_balance / v_rate;
        END IF;

        v_wallet_balances :=
            v_wallet_balances ||
            jsonb_build_array(
                jsonb_build_object(
                    'currency_code',
                    v_wallet.currency_code,

                    'balance',
                    trim_scale(v_balance)::text,

                    'usd_value',
                    trim_scale(v_usd_value)::text
                )
            );
    END LOOP;

    /*
     * 8. Add ONE consolidated Treasury gold entry.
     *
     * Gold balance = sum of Treasury gold
     * balances from all supported blockchains.
     *
     * No blockchain_code is included here.
     */
    SELECT cr.rate_to_usd
    INTO v_rate
    FROM public.current_rates cr
    WHERE lower(btrim(cr.code)) = 'gold'
    LIMIT 1;

    IF NOT FOUND
       OR v_rate IS NULL
       OR v_rate <= 0
    THEN
        RAISE EXCEPTION USING
            MESSAGE = 'MISSING_GOLD_RATE';
    END IF;

    v_usd_value :=
        v_treasury_gold_balance * v_rate;

    v_wallet_balances :=
        v_wallet_balances ||
        jsonb_build_array(
            jsonb_build_object(
                'currency_code',
                'gold',

                'balance',
                trim_scale(
                    v_treasury_gold_balance
                )::text,

                'usd_value',
                trim_scale(v_usd_value)::text
            )
        );

    /*
     * 9. Supported currencies.
     */
    v_currencies :=
        public.build_country_supported_currencies(
            v_user.country_code
        );

    /*
     * 10. Return Treasury dashboard.
     */
    RETURN jsonb_build_object(
        'gold_reserve',
        v_gold_reserve,

        'token_supply',
        v_token_supply,

        'treasury_gold_balance',
        v_treasury_gold_balance,

        'reserve_ratio',
        v_reserve_ratio,

        'blockchain_balances',
        v_blockchain_balances,

        'treasury_wallet_balances',
        v_wallet_balances,

        'currencies',
        v_currencies
    );
END;
$function$;

COMMIT;