-- Remove the obsolete function that accepts blockchain balances.
DROP FUNCTION IF EXISTS
    public.get_my_multi_wallet_balances(jsonb);

CREATE OR REPLACE FUNCTION
public.get_my_multi_wallet_balances()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
    v_user_id text;
    v_missing_currency text;

    v_agent_wallet jsonb;
    v_customer_wallet jsonb;
    v_merchant_wallet jsonb;

    v_empty_wallet jsonb :=
        jsonb_build_object(
            'balances', '{}'::jsonb,
            'blockchain_balances', '[]'::jsonb,
            'total_usd_value', '0'
        );

BEGIN

    ------------------------------------------------------------
    -- 1. Authentication
    ------------------------------------------------------------

    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION USING
            ERRCODE = '42501',
            MESSAGE = 'UNAUTHORIZED';
    END IF;

    ------------------------------------------------------------
    -- 2. Validate user and role
    ------------------------------------------------------------

    SELECT u.id
    INTO v_user_id
    FROM public.users u
    JOIN public.user_role r
        ON r.id = u.role_id
    WHERE u.id = auth.uid()::text
      AND u.status = 'active'::public."UserStatus"
      AND lower(r.name::text) IN (
          'agent',
          'merchant',
          'vendor'
      )
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION USING
            ERRCODE = '42501',
            MESSAGE = 'MULTI_WALLET_BALANCES_NOT_AUTHORIZED';
    END IF;

    ------------------------------------------------------------
    -- 3. Validate currency rates
    --
    -- Same implementation as get_wallet_balances.
    ------------------------------------------------------------

    SELECT lower(btrim(w.currency_code))
    INTO v_missing_currency
    FROM public.wallet w
    LEFT JOIN public.current_rates r
        ON lower(btrim(r.code)) =
           lower(btrim(w.currency_code))
    WHERE w.user_id = v_user_id
      AND lower(btrim(w.owner_type::text)) IN (
          'agent',
          'customer',
          'merchant'
      )
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

    ------------------------------------------------------------
    -- 4. Build wallet values
    --
    -- Same conversion rules as the Single Wallet SQL,
    -- with owner_type added.
    ------------------------------------------------------------

    WITH wallet_values AS (
        SELECT
            lower(btrim(w.owner_type::text))
                AS owner_type,

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
                THEN
                    coalesce(w.balance, 0)::numeric

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

        WHERE w.user_id = v_user_id
          AND lower(btrim(w.owner_type::text)) IN (
              'agent',
              'customer',
              'merchant'
          )
    ),

    ------------------------------------------------------------
    -- 5. Consolidated balances by wallet and currency
    ------------------------------------------------------------

    currency_totals AS (
        SELECT
            owner_type,
            currency_code,
            sum(balance) AS balance,
            sum(usd_value) AS usd_value
        FROM wallet_values
        GROUP BY
            owner_type,
            currency_code
    ),

    ------------------------------------------------------------
    -- 6. Blockchain balances by wallet owner
    ------------------------------------------------------------

    blockchain_totals AS (
        SELECT
            owner_type,
            blockchain_code,
            currency_code,
            sum(balance) AS balance,
            sum(usd_value) AS usd_value
        FROM wallet_values
        WHERE blockchain_code IS NOT NULL
        GROUP BY
            owner_type,
            blockchain_code,
            currency_code
    ),

    ------------------------------------------------------------
    -- 7. Build JSON for each wallet owner
    ------------------------------------------------------------

    wallet_summaries AS (
        SELECT
            owners.owner_type,

            jsonb_build_object(
                'balances',
                (
                    SELECT coalesce(
                        jsonb_object_agg(
                            c.currency_code,
                            jsonb_build_object(
                                'balance',
                                c.balance::text,
                                'usd_value',
                                c.usd_value::text
                            )
                            ORDER BY c.currency_code
                        ),
                        '{}'::jsonb
                    )
                    FROM currency_totals c
                    WHERE c.owner_type = owners.owner_type
                ),

                'blockchain_balances',
                (
                    SELECT coalesce(
                        jsonb_agg(
                            jsonb_build_object(
                                'blockchain_code',
                                b.blockchain_code,
                                'currency_code',
                                b.currency_code,
                                'balance',
                                b.balance::text,
                                'usd_value',
                                b.usd_value::text
                            )
                            ORDER BY
                                b.blockchain_code,
                                b.currency_code
                        ),
                        '[]'::jsonb
                    )
                    FROM blockchain_totals b
                    WHERE b.owner_type = owners.owner_type
                ),

                'total_usd_value',
                (
                    SELECT
                        coalesce(
                            sum(c.usd_value),
                            0
                        )::text
                    FROM currency_totals c
                    WHERE c.owner_type = owners.owner_type
                )
            ) AS summary

        FROM (
            VALUES
                ('agent'),
                ('customer'),
                ('merchant')
        ) AS owners(owner_type)
    )

    SELECT
        max(summary) FILTER (
            WHERE owner_type = 'agent'
        ),
        max(summary) FILTER (
            WHERE owner_type = 'customer'
        ),
        max(summary) FILTER (
            WHERE owner_type = 'merchant'
        )
    INTO
        v_agent_wallet,
        v_customer_wallet,
        v_merchant_wallet
    FROM wallet_summaries;

    ------------------------------------------------------------
    -- 8. Return multi-wallet response
    ------------------------------------------------------------

    RETURN jsonb_build_object(
        'agentWallet',
        coalesce(v_agent_wallet, v_empty_wallet),

        'customerWallet',
        coalesce(v_customer_wallet, v_empty_wallet),

        'merchantWallet',
        coalesce(v_merchant_wallet, v_empty_wallet)
    );

END;
$function$;