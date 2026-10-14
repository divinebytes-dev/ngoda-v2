drop function if exists
    public.approve_my_credit_agent(
        text,
        text
    );


create or replace function public.approve_my_credit_agent(
    p_merchant_identifier text
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
    v_approver public.users%rowtype;
    v_merchant public.users%rowtype;

    v_identifier text;

    v_currency_count integer;

    v_accounts jsonb;
    v_currencies jsonb;

    v_stage text := 'initialization';
    v_error_state text;
    v_error_message text;
    v_error_detail text;
    v_error_hint text;
    v_error_context text;
begin
    /*
     * Authenticate treasury.
     */
    v_stage := 'authorize treasury user';

    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHENTICATED';
    end if;

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
     * Validate merchant identifier.
     */
    v_stage := 'validate input';

    v_identifier :=
        nullif(
            btrim(p_merchant_identifier),
            ''
        );

    if v_identifier is null then
        raise exception
            'MERCHANT_IDENTIFIER_REQUIRED';
    end if;

    /*
     * Fetch treasury approver.
     */
    v_stage := 'fetch treasury user';

    v_approver :=
        public.fetch_user_by_id(
            auth.uid()::text
        );

    if v_approver.id is null then
        raise exception
            'TREASURY_USER_NOT_FOUND';
    end if;

    if v_approver.country_code is null then
        raise exception
            'USER_COUNTRY_NOT_CONFIGURED';
    end if;

    /*
     * Only an active merchant can become a credit agent.
     */
    v_stage := 'fetch merchant';

    select user_record.*
    into v_merchant
    from public.users user_record
    join public.user_role role_record
      on role_record.id =
         user_record.role_id
    where user_record.country_code =
              v_approver.country_code

      and user_record.status =
              'active'::public."UserStatus"

      and lower(
          role_record.name::text
      ) =
              'merchant'

      and (
          lower(
              user_record.email
          ) =
              lower(v_identifier)

          or user_record.phone =
              v_identifier
      )
    limit 1;

    if not found then
        raise exception
            'ACTIVE_MERCHANT_NOT_FOUND';
    end if;

    /*
     * Ensure the country has active fiat currencies.
     */
    v_stage := 'fetch active fiat currencies';

    select count(*)
    into v_currency_count
    from public.country_currencies
        currency_record
    where currency_record.country_code =
              v_approver.country_code

      and currency_record.is_active =
              true

      and lower(
          currency_record.currency_code
      ) <>
              'gold';

    if v_currency_count = 0 then
        raise exception
            'ACTIVE_FIAT_CURRENCIES_NOT_FOUND';
    end if;

    /*
     * Approve the merchant for every active fiat currency.
     *
     * Existing balances are never reset.
     */
    v_stage := 'create credit agent accounts';

    insert into public.credit_agent_account (
        merchant_id,
        country_code,
        currency_code,
        receivable_balance,
        cash_holding_balance,
        is_active,
        approved_by,
        created_at,
        updated_at
    )
    select
        v_merchant.id,
        v_approver.country_code,
        lower(
            currency_record.currency_code
        ),
        0,
        0,
        true,
        v_approver.id,
        now(),
        now()
    from public.country_currencies
        currency_record
    where currency_record.country_code =
              v_approver.country_code

      and currency_record.is_active =
              true

      and lower(
          currency_record.currency_code
      ) <>
              'gold'

    on conflict (
        merchant_id,
        country_code,
        currency_code
    )
    do update
    set
        is_active =
            true,

        approved_by =
            excluded.approved_by,

        updated_at =
            now();

    /*
     * Return all active credit-agent accounts.
     */
    v_stage := 'fetch approved accounts';

    select
        coalesce(
            jsonb_agg(
                jsonb_build_object(
                    'credit_agent_account_id',
                    account_record.id,

                    'currency_code',
                    account_record.currency_code,

                    'receivable_balance',
                    account_record.receivable_balance::text,

                    'cash_holding_balance',
                    account_record.cash_holding_balance::text,

                    'is_active',
                    account_record.is_active
                )
                order by
                    account_record.currency_code
            ),
            '[]'::jsonb
        )
    into v_accounts
    from public.credit_agent_account
        account_record
    where account_record.merchant_id =
              v_merchant.id

      and account_record.country_code =
              v_approver.country_code

      and account_record.is_active =
              true;

    select
        coalesce(
            jsonb_agg(
                account_record.currency_code
                order by
                    account_record.currency_code
            ),
            '[]'::jsonb
        )
    into v_currencies
    from public.credit_agent_account
        account_record
    where account_record.merchant_id =
              v_merchant.id

      and account_record.country_code =
              v_approver.country_code

      and account_record.is_active =
              true;

    return jsonb_build_object(
        'success',
        true,

        'is_credit_agent',
        true,

        'merchant_id',
        v_merchant.id,

        'merchant_email',
        v_merchant.email,

        'merchant_phone',
        v_merchant.phone,

        'country_code',
        v_approver.country_code,

        'credit_agent_currencies',
        v_currencies,

        'credit_agent_accounts',
        v_accounts,

        'approved_by',
        v_approver.id
    );

exception
    when others then
        get stacked diagnostics
            v_error_state = returned_sqlstate,
            v_error_message = message_text,
            v_error_detail = pg_exception_detail,
            v_error_hint = pg_exception_hint,
            v_error_context = pg_exception_context;

        raise exception using
            errcode = v_error_state,

            message = format(
                'CREDIT_AGENT_APPROVAL_FAILED at [%s]: %s',
                v_stage,
                v_error_message
            ),

            detail = concat_ws(
                E'\n',
                nullif(v_error_detail, ''),
                nullif(v_error_context, '')
            ),

            hint = coalesce(
                nullif(v_error_hint, ''),
                'Check the Credit Agent Approval stage reported in the error'
            );
end;
$function$;


revoke all on function
    public.approve_my_credit_agent(
        text
    )
from public;

revoke all on function
    public.approve_my_credit_agent(
        text
    )
from anon;

grant execute on function
    public.approve_my_credit_agent(
        text
    )
to authenticated;