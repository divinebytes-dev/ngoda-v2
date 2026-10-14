
-- Remove the old two-argument signature after dependent
-- objects have been checked.
DROP FUNCTION IF EXISTS public.get_my_wallet_balance_snapshot(
    text,
    public."WalletOwnerType"
);

CREATE OR REPLACE FUNCTION public.get_my_wallet_balance_snapshot(
    p_currency_code text,
    p_wallet_owner public."WalletOwnerType",
    p_blockchain_code text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
declare
    v_user public.users%rowtype;
    v_currency_code text;
    v_blockchain_code text;
begin
    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHORIZED';
    end if;

    v_currency_code :=
        lower(btrim(p_currency_code));

    if v_currency_code is null
       or v_currency_code = ''
    then
        raise exception
            'CURRENCY_IS_REQUIRED';
    end if;

    if p_wallet_owner is null then
        raise exception
            'WALLET_OWNER_IS_REQUIRED';
    end if;

    v_blockchain_code :=
        nullif(
            lower(btrim(p_blockchain_code)),
            ''
        );

    if v_currency_code = 'gold'
       and v_blockchain_code is null
    then
        raise exception
            'BLOCKCHAIN_CODE_IS_REQUIRED';
    end if;

    /*
     * Authentication, active-user validation
     * and required-role validation.
     */
    select u.*
    into v_user
    from public.users u
    join public.user_role r
      on r.id = u.role_id
    where u.id = auth.uid()::text
      and u.status =
          'active'::public."UserStatus"
      and lower(r.name::text) in (
          'treasury',
          'customer',
          'agent',
          'merchant',
          'vendor'
      )
    limit 1;

    if not found then
        raise exception using
            errcode = '42501',
            message =
                'WALLET_BALANCE_SNAPSHOT_NOT_AUTHORIZED';
    end if;

    return public.get_wallet_balance_snapshot(
        p_user_id =>
            v_user.id,

        p_currency_code =>
            v_currency_code,

        p_country_code =>
            v_user.country_code,

        p_wallet_owner =>
            p_wallet_owner,

        p_blockchain_code =>
            v_blockchain_code
    );
end;
$function$;



-- Remove the old four-argument signature after dependent
-- objects have been checked.
DROP FUNCTION IF EXISTS public.get_wallet_balance_snapshot(
    text,
    text,
    text,
    public."WalletOwnerType"
);

CREATE OR REPLACE FUNCTION public.get_wallet_balance_snapshot(
    p_user_id text,
    p_currency_code text,
    p_country_code text,
    p_wallet_owner public."WalletOwnerType",
    p_blockchain_code text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
    v_fiscal_year integer;
    v_result jsonb;
    v_currency_code text;
    v_blockchain_code text;
begin
    v_currency_code :=
        lower(btrim(p_currency_code));

    if v_currency_code is null
       or v_currency_code = ''
    then
        raise exception
            'CURRENCY_IS_REQUIRED';
    end if;

    if p_wallet_owner is null then
        raise exception
            'WALLET_OWNER_IS_REQUIRED';
    end if;

    v_blockchain_code :=
        nullif(
            lower(btrim(p_blockchain_code)),
            ''
        );

    if v_currency_code = 'gold'
       and v_blockchain_code is null
    then
        raise exception
            'BLOCKCHAIN_CODE_IS_REQUIRED';
    end if;

    /*
     * Fetch the current fiscal year.
     */
    select fp.fiscal_year
    into v_fiscal_year
    from public.fetch_fiscal_period(
        p_country_code
    ) fp
    limit 1;

    with snapshots as (
        select
            s.period,
            s.opening_balance,
            s.debit,
            s.credit,
            s.closing_balance

        from public.wallet_balance_snapshot s

        where s.user_id = p_user_id
          and s.wallet_owner = p_wallet_owner
          and lower(btrim(s.currency_code)) =
              v_currency_code
          and s.fiscal_year = v_fiscal_year

          /*
           * GOLD must match the selected blockchain.
           * Fiat retains the existing behavior.
           */
          and (
              v_currency_code <> 'gold'
              or lower(btrim(s.blockchain_code)) =
                  v_blockchain_code
          )
    ),

    period_values as (
        select
            generated_period.period,

            case
                when current_snapshot.period is not null
                then current_snapshot.opening_balance

                else coalesce(
                    previous_snapshot.closing_balance,
                    0
                )
            end as opening_balance,

            case
                when current_snapshot.period is not null
                then current_snapshot.debit
                else 0
            end as debit,

            case
                when current_snapshot.period is not null
                then current_snapshot.credit
                else 0
            end as credit,

            case
                when current_snapshot.period is not null
                then abs(
                    current_snapshot.closing_balance
                )

                else coalesce(
                    previous_snapshot.closing_balance,
                    0
                )
            end as closing_balance

        from generate_series(
            1,
            12
        ) as generated_period(period)

        left join snapshots current_snapshot
            on current_snapshot.period =
               generated_period.period

        left join lateral (
            select previous.closing_balance
            from snapshots previous
            where previous.period <
                  generated_period.period
            order by previous.period desc
            limit 1
        ) previous_snapshot on true
    )

    select jsonb_build_object(
        'currency_code',
        v_currency_code,

        'blockchain_code',
        v_blockchain_code,

        'fiscalYear',
        v_fiscal_year,

        'periods',
        coalesce(
            jsonb_agg(
                jsonb_build_object(
                    'period',
                    period,

                    'opening_balance',
                    opening_balance::text,

                    'debit',
                    debit::text,

                    'credit',
                    credit::text,

                    'closing_balance',
                    closing_balance::text
                )
                order by period
            ),
            '[]'::jsonb
        )
    )
    into v_result
    from period_values;

    return v_result;
end;
$function$;
