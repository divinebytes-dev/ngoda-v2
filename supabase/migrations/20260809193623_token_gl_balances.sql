create or replace function public.fetch_my_current_token_gl_balance()
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
    v_user public.users%rowtype;

    v_country_code text;

    v_fiscal_year integer;
    v_period integer;

    v_accounts jsonb :=
        '[]'::jsonb;

    v_total_opening numeric := 0;
    v_total_debit numeric := 0;
    v_total_credit numeric := 0;
    v_total_closing numeric := 0;
begin
    /*
     * Authenticate.
     */
    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHENTICATED';
    end if;

    /*
     * Preserve the existing treasury-role requirement.
     */
    if not public.has_role(
        array[
            'treasury'
        ]::text[]
    ) then
        raise exception using
            errcode = '42501',
            message = 'FORBIDDEN';
    end if;

    /*
     * Fetch trusted user context.
     */
    v_user :=
        public.fetch_user_by_id(
            auth.uid()::text
        );

    if v_user.id is null then
        raise exception
            'TREASURY_USER_NOT_FOUND';
    end if;

    v_country_code :=
        lower(
            nullif(
                btrim(
                    v_user.country_code
                ),
                ''
            )
        );

    if v_country_code is null then
        raise exception
            'USER_COUNTRY_NOT_CONFIGURED';
    end if;

    /*
     * Fetch current fiscal period.
     */
    select
        fiscal_period.fiscal_year,
        fiscal_period.period
    into
        v_fiscal_year,
        v_period
    from public.fetch_fiscal_period(
        v_country_code
    ) as fiscal_period;

    if not found then
        raise exception
            'FISCAL_PERIOD_NOT_FOUND';
    end if;

    /*
     * Build all token GL rows.
     *
     * For each configured token GL:
     * - use the current snapshot when available;
     * - otherwise carry forward the latest earlier closing
     *   balance;
     * - otherwise start from zero.
     */
    with token_accounts as (
        select
            btrim(
                gl_record.code
            ) as gl_account_code,

            coalesce(
                btrim(
                    gl_record.description
                ),
                ''
            ) as description
        from public.gl_account
            gl_record
        where gl_record.type =
              'token'::public."GlType"
    ),
    enriched_accounts as (
        select
            token_account.gl_account_code,
            token_account.description,

            case
                when current_snapshot.gl_account_code is not null
                then
                    coalesce(
                        current_snapshot.opening_balance,
                        0
                    )
                else
                    coalesce(
                        previous_snapshot.closing_balance,
                        0
                    )
            end as opening_balance,

            coalesce(
                current_snapshot.debit,
                0
            ) as debit,

            coalesce(
                current_snapshot.credit,
                0
            ) as credit,

            case
                when current_snapshot.gl_account_code is not null
                then
                    coalesce(
                        current_snapshot.closing_balance,
                        0
                    )
                else
                    coalesce(
                        previous_snapshot.closing_balance,
                        0
                    )
            end as closing_balance
        from token_accounts
            token_account

        left join lateral (
            select snapshot_record.*
            from public.gl_balance_snapshot
                snapshot_record
            where snapshot_record.country_code =
                  v_country_code

              and lower(
                  snapshot_record.currency_code
              ) =
                  'gold'

              and snapshot_record.gl_account_code =
                  token_account.gl_account_code

              and snapshot_record.fiscal_year =
                  v_fiscal_year

              and snapshot_record.period =
                  v_period
            limit 1
        ) as current_snapshot
          on true

        left join lateral (
            select snapshot_record.*
            from public.gl_balance_snapshot
                snapshot_record
            where snapshot_record.country_code =
                  v_country_code

              and lower(
                  snapshot_record.currency_code
              ) =
                  'gold'

              and snapshot_record.gl_account_code =
                  token_account.gl_account_code

              and (
                  snapshot_record.fiscal_year <
                      v_fiscal_year

                  or (
                      snapshot_record.fiscal_year =
                          v_fiscal_year

                      and snapshot_record.period <
                          v_period
                  )
              )
            order by
                snapshot_record.fiscal_year desc,
                snapshot_record.period desc
            limit 1
        ) as previous_snapshot
          on true
    )
    select
        coalesce(
            jsonb_agg(
                jsonb_build_object(
                    'currency',
                    'gold',

                    'gl_account_code',
                    enriched_account.gl_account_code,

                    'description',
                    enriched_account.description,

                    'gl_type',
                    'token',

                    'opening_balance',
                    enriched_account.opening_balance,

                    'debit',
                    enriched_account.debit,

                    'credit',
                    enriched_account.credit,

                    'closing_balance',
                    enriched_account.closing_balance
                )
                order by
                    enriched_account.gl_account_code
            ),
            '[]'::jsonb
        ),

        coalesce(
            sum(
                enriched_account.opening_balance
            ),
            0
        ),

        coalesce(
            sum(
                enriched_account.debit
            ),
            0
        ),

        coalesce(
            sum(
                enriched_account.credit
            ),
            0
        ),

        coalesce(
            sum(
                enriched_account.closing_balance
            ),
            0
        )
    into
        v_accounts,
        v_total_opening,
        v_total_debit,
        v_total_credit,
        v_total_closing
    from enriched_accounts
        enriched_account;

    return jsonb_build_object(
        'fiscalYear',
        v_fiscal_year,

        'period',
        v_period,

        'currency',
        'gold',

        'totals',
        jsonb_build_object(
            'opening',
            v_total_opening,

            'debit',
            v_total_debit,

            'credit',
            v_total_credit,

            'closing',
            v_total_closing
        ),

        'accounts',
        v_accounts
    );
end;
$function$;


revoke all on function
    public.fetch_my_current_token_gl_balance()
from public;

revoke all on function
    public.fetch_my_current_token_gl_balance()
from anon;

grant execute on function
    public.fetch_my_current_token_gl_balance()
to authenticated;

notify pgrst, 'reload schema';