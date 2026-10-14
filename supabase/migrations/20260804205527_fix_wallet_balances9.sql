create or replace function public.get_my_multi_wallet_balances()
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
    v_user_id text;
    v_result jsonb;

    v_agent_balances jsonb :=
        '{}'::jsonb;

    v_customer_balances jsonb :=
        '{}'::jsonb;

    v_merchant_balances jsonb :=
        '{}'::jsonb;
begin
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
     * Existing internal report.
     */
    v_result :=
        public.get_multi_wallet_balances(
            v_user_id
        );

    /*
     * Convert agent wallet_balances:
     *
     * [
     *   {
     *     currency_code: "usd",
     *     balance: ...,
     *     usd_value: ...
     *   }
     * ]
     *
     * Into:
     *
     * {
     *   usd: {
     *     balance: ...,
     *     usd_value: ...
     *   }
     * }
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
    ) is not null;

    /*
     * Customer balances.
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
    ) is not null;

    /*
     * Merchant balances.
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
    ) is not null;

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
            coalesce(
                v_result #>
                    '{customerWallet,total_usd_value}',
                '0'::jsonb
            )
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

