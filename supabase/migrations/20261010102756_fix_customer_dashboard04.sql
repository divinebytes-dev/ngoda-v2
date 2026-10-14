CREATE OR REPLACE FUNCTION
public.fetch_my_multi_wallet_context()
RETURNS TABLE (
    wallet_address text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
begin
    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHORIZED';
    end if;

    return query
    select
        u.wallet_address::text
    from public.users u
    join public.user_role r
      on r.id = u.role_id
    where u.id = auth.uid()::text
      and u.status =
          'active'::public."UserStatus"
      and lower(r.name::text) in (
          'agent',
          'merchant',
          'vendor'
      )
    limit 1;

    if not found then
        raise exception using
            errcode = '42501',
            message =
                'MULTI_WALLET_BALANCES_NOT_AUTHORIZED';
    end if;
end;
$function$;



CREATE OR REPLACE FUNCTION
public.get_my_multi_wallet_balances(
    p_blockchain_balances jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
declare
    v_user_id text;
    v_result jsonb;

    v_agent_balances jsonb :=
        '{}'::jsonb;

    v_customer_balances jsonb :=
        '{}'::jsonb;

    v_merchant_balances jsonb :=
        '{}'::jsonb;

    v_blockchain_balances jsonb :=
        '[]'::jsonb;

    v_blockchain record;

    v_blockchain_code text;
    v_balance numeric;
    v_usd_value numeric;

    v_total_gold numeric := 0;
    v_total_gold_usd numeric := 0;

    v_gold_price numeric := 0;

    v_customer_total_usd numeric := 0;
begin
    /*
     * 1. Authentication.
     */
    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHORIZED';
    end if;

    select u.id
    into v_user_id
    from public.users u
    join public.user_role r
      on r.id = u.role_id
    where u.id = auth.uid()::text
      and u.status =
          'active'::public."UserStatus"
      and lower(r.name::text) in (
          'agent',
          'merchant',
          'vendor'
      )
    limit 1;

    if not found then
        raise exception using
            errcode = '42501',
            message =
                'MULTI_WALLET_BALANCES_NOT_AUTHORIZED';
    end if;

    /*
     * 2. Validate blockchain input.
     */
    if p_blockchain_balances is null
       or jsonb_typeof(
           p_blockchain_balances
       ) <> 'array'
    then
        raise exception using
            message =
                'INVALID_BLOCKCHAIN_BALANCES';
    end if;

    /*
     * 3. Existing internal wallet report.
     */
    v_result :=
        public.get_multi_wallet_balances(
            v_user_id
        );

    /*
     * 4. Agent wallet.
     *
     * Exclude GOLD from legacy balances.
     */
    select coalesce(
        jsonb_object_agg(
            lower(
                btrim(
                    item ->> 'currency_code'
                )
            ),
            jsonb_build_object(
                'balance',
                item -> 'balance',
                'usd_value',
                item -> 'usd_value'
            )
        ),
        '{}'::jsonb
    )
    into v_agent_balances
    from jsonb_array_elements(
        coalesce(
            v_result #>
                '{agentWallet,wallet_balances}',
            '[]'::jsonb
        )
    ) as item
    where nullif(
        btrim(
            item ->> 'currency_code'
        ),
        ''
    ) is not null
      and lower(
          btrim(
              item ->> 'currency_code'
          )
      ) <> 'gold';

    /*
     * 5. Customer wallet.
     *
     * Existing fiat balances are preserved.
     */
    select coalesce(
        jsonb_object_agg(
            lower(
                btrim(
                    item ->> 'currency_code'
                )
            ),
            jsonb_build_object(
                'balance',
                item -> 'balance',
                'usd_value',
                item -> 'usd_value'
            )
        ),
        '{}'::jsonb
    )
    into v_customer_balances
    from jsonb_array_elements(
        coalesce(
            v_result #>
                '{customerWallet,wallet_balances}',
            '[]'::jsonb
        )
    ) as item
    where nullif(
        btrim(
            item ->> 'currency_code'
        ),
        ''
    ) is not null
      and lower(
          btrim(
              item ->> 'currency_code'
          )
      ) <> 'gold';

    /*
     * 6. Merchant wallet.
     */
    select coalesce(
        jsonb_object_agg(
            lower(
                btrim(
                    item ->> 'currency_code'
                )
            ),
            jsonb_build_object(
                'balance',
                item -> 'balance',
                'usd_value',
                item -> 'usd_value'
            )
        ),
        '{}'::jsonb
    )
    into v_merchant_balances
    from jsonb_array_elements(
        coalesce(
            v_result #>
                '{merchantWallet,wallet_balances}',
            '[]'::jsonb
        )
    ) as item
    where nullif(
        btrim(
            item ->> 'currency_code'
        ),
        ''
    ) is not null
      and lower(
          btrim(
              item ->> 'currency_code'
          )
      ) <> 'gold';

    /*
     * 7. Current GOLD USD price.
     */
    select coalesce(
        cr.rate_to_usd,
        0
    )
    into v_gold_price
    from public.current_rates cr
    where lower(cr.code::text) = 'gold'
    limit 1;

    if v_gold_price <= 0 then
        raise exception using
            message = 'GOLD_PRICE_NOT_AVAILABLE';
    end if;

    /*
     * 8. Calculate GOLD balances
     * for every blockchain.
     */
    for v_blockchain in
        select value as data
        from jsonb_array_elements(
            p_blockchain_balances
        )
    loop
        v_blockchain_code :=
            lower(
                btrim(
                    v_blockchain.data
                        ->> 'blockchain_code'
                )
            );

        if nullif(
            v_blockchain_code,
            ''
        ) is null then
            raise exception using
                message =
                    'BLOCKCHAIN_CODE_REQUIRED';
        end if;

        if jsonb_typeof(
            v_blockchain.data
        ) <> 'object' then
            raise exception using
                message =
                    'INVALID_BLOCKCHAIN_BALANCE';
        end if;

        v_balance :=
            coalesce(
                nullif(
                    v_blockchain.data
                        ->> 'balance',
                    ''
                )::numeric,
                0
            );

        if v_balance < 0 then
            raise exception using
                message =
                    'INVALID_GOLD_BALANCE';
        end if;

        v_balance :=
            trunc(v_balance, 6);

        v_usd_value :=
            round(
                v_balance * v_gold_price,
                2
            );

        v_total_gold :=
            v_total_gold + v_balance;

        v_total_gold_usd :=
            v_total_gold_usd + v_usd_value;

        v_blockchain_balances :=
            v_blockchain_balances ||
            jsonb_build_array(
                jsonb_build_object(
                    'blockchain_code',
                    v_blockchain_code,

                    'currency_code',
                    'gold',

                    'balance',
                    v_balance::text,

                    'usd_value',
                    v_usd_value::text,

                    'chain_id',
                    v_blockchain.data
                        ->> 'chain_id',

                    'gas_balance',
                    v_blockchain.data
                        ->> 'gas_balance',

                    'token_supply',
                    v_blockchain.data
                        ->> 'token_supply',

                    'native_currency_code',
                    v_blockchain.data
                        ->> 'native_currency_code'
                )
            );
    end loop;

    /*
     * 9. Add aggregated GOLD to the
     * customer wallet balances.
     */
    v_customer_balances :=
        v_customer_balances ||
        jsonb_build_object(
            'gold',
            jsonb_build_object(
                'balance',
                v_total_gold::text,

                'usd_value',
                v_total_gold_usd::text
            )
        );

    /*
     * 10. Calculate customer total USD.
     *
     * Recalculate from the normalized
     * fiat balances and blockchain GOLD
     * to avoid counting legacy GOLD twice.
     */
    select coalesce(
        sum(
            coalesce(
                nullif(
                    value ->> 'usd_value',
                    ''
                )::numeric,
                0
            )
        ),
        0
    )
    into v_customer_total_usd
    from jsonb_each(
        v_customer_balances
    );

    /*
     * 11. Return normalized wallet data.
     */
    return jsonb_build_object(
        'agentWallet',
        jsonb_build_object(
            'balances',
            v_agent_balances,

            'total_usd_value',
            coalesce(
                v_result #>
                    '{agentWallet,total_usd_value}',
                '0'::jsonb
            )
        ),

        'customerWallet',
        jsonb_build_object(
            'balances',
            v_customer_balances,

            'total_usd_value',
            v_customer_total_usd::text,

            'blockchains',
            v_blockchain_balances
        ),

        'merchantWallet',
        jsonb_build_object(
            'balances',
            v_merchant_balances,

            'total_usd_value',
            coalesce(
                v_result #>
                    '{merchantWallet,total_usd_value}',
                '0'::jsonb
            )
        )
    );
end;
$function$;