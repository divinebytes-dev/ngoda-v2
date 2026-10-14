CREATE OR REPLACE FUNCTION public.get_wallet_balances(
    p_user_id text
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path TO ''
AS $function$
DECLARE
    v_missing_currency text;
    v_result jsonb;
BEGIN
    /*
     * Validate exchange rates.
     *
     * USD:
     *   USD value = balance
     *
     * GOLD:
     *   USD value = balance * rate_to_usd
     *
     * Other fiat:
     *   USD value = balance / rate_to_usd
     */

    SELECT lower(btrim(w.currency_code))
    INTO v_missing_currency
    FROM public.wallet w
    LEFT JOIN public.current_rates r
        ON lower(btrim(r.code)) =
           lower(btrim(w.currency_code))
    WHERE w.user_id = p_user_id
      AND lower(btrim(w.currency_code)) <> 'usd'
      AND (
          r.code IS NULL
          OR r.rate_to_usd IS NULL
          OR r.rate_to_usd <= 0
      )
    LIMIT 1;

    IF FOUND THEN
        RAISE EXCEPTION
            'MISSING_RATE_FOR_CURRENCY_%',
            upper(v_missing_currency);
    END IF;

    WITH wallet_values AS (
        SELECT
            w.id AS wallet_id,

            lower(btrim(w.currency_code))
                AS currency_code,

            NULLIF(
                lower(btrim(w.blockchain_code)),
                ''
            ) AS blockchain_code,

            coalesce(w.balance, 0)::numeric
                AS balance,

            CASE
                WHEN lower(btrim(w.currency_code)) = 'usd'
                THEN coalesce(w.balance, 0)::numeric

                WHEN lower(btrim(w.currency_code)) = 'gold'
                THEN
                    coalesce(w.balance, 0)::numeric *
                    r.rate_to_usd::numeric

                ELSE
                    coalesce(w.balance, 0)::numeric /
                    r.rate_to_usd::numeric
            END AS usd_value

        FROM public.wallet w

        LEFT JOIN public.current_rates r
            ON lower(btrim(r.code)) =
               lower(btrim(w.currency_code))

        WHERE w.user_id = p_user_id
    ),

    /*
     * Consolidated balances per currency.
     */
    currency_totals AS (
        SELECT
            currency_code,
            sum(balance) AS balance,
            sum(usd_value) AS usd_value
        FROM wallet_values
        GROUP BY currency_code
    ),

    /*
     * Blockchain-specific balances.
     */
    blockchain_totals AS (
        SELECT
            blockchain_code,
            currency_code,
            sum(balance) AS balance,
            sum(usd_value) AS usd_value
        FROM wallet_values
        WHERE blockchain_code IS NOT NULL
        GROUP BY
            blockchain_code,
            currency_code
    )

    SELECT jsonb_build_object(
        'balances',
        (
            SELECT coalesce(
                jsonb_object_agg(
                    c.currency_code,
                    jsonb_build_object(
                        'balance', c.balance::text,
                        'usd_value', c.usd_value::text
                    )
                    ORDER BY c.currency_code
                ),
                '{}'::jsonb
            )
            FROM currency_totals c
        ),

        'blockchain_balances',
        (
            SELECT coalesce(
                jsonb_agg(
                    jsonb_build_object(
                        'blockchain_code', b.blockchain_code,
                        'currency_code', b.currency_code,
                        'balance', b.balance::text,
                        'usd_value', b.usd_value::text
                    )
                    ORDER BY
                        b.blockchain_code,
                        b.currency_code
                ),
                '[]'::jsonb
            )
            FROM blockchain_totals b
        )
    )
    INTO v_result;

    RETURN v_result;
END;
$function$;


CREATE OR REPLACE FUNCTION public.get_my_wallet_balances()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
    v_user_id text;
BEGIN
    /*
     * Authentication.
     */
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION USING
            ERRCODE = '42501',
            MESSAGE = 'UNAUTHORIZED';
    END IF;

    /*
     * Required-role validation.
     */
    SELECT u.id
    INTO v_user_id
    FROM public.users u
    JOIN public.user_role r
        ON r.id = u.role_id
    WHERE u.id = auth.uid()::text
      AND u.status = 'active'::public."UserStatus"
      AND lower(r.name::text) IN (
          'treasury',
          'customer'
      )
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION USING
            ERRCODE = '42501',
            MESSAGE = 'WALLET_BALANCES_NOT_AUTHORIZED';
    END IF;

    /*
     * Shared wallet balance function.
     */
    RETURN public.get_wallet_balances(
        v_user_id
    );
END;
$function$;