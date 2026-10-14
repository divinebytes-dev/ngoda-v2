create or replace function public.approve_my_credit_agent(
    p_merchant_identifier text,
    p_currency_code text
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
    v_currency_code text;

    v_account
        public.credit_agent_account%rowtype;

    v_stage text := 'initialization';
    v_error_state text;
    v_error_message text;
    v_error_detail text;
    v_error_hint text;
    v_error_context text;
begin
    /*
     * Authenticate and authorize treasury.
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
     * Validate request.
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

    v_currency_code :=
        lower(
            nullif(
                btrim(p_currency_code),
                ''
            )
        );

    if v_currency_code is null then
        raise exception
            'CURRENCY_REQUIRED';
    end if;

    if v_currency_code = 'gold' then
        raise exception
            'CREDIT_AGENT_CURRENCY_MUST_BE_FIAT';
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
     * Find active merchant in treasury's country.
     *
     * Agent and vendor roles do not qualify.
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
     * Validate currency for the country.
     */
    v_stage := 'validate country currency';

    perform 1
    from public.country_currencies
        currency_record
    where currency_record.country_code =
              v_approver.country_code

      and lower(
          currency_record.currency_code
      ) =
          v_currency_code

      and currency_record.is_active =
          true
    limit 1;

    if not found then
        raise exception
            'CURRENCY_NOT_ACTIVE_FOR_COUNTRY';
    end if;

    /*
     * Create the facility account or reactivate an existing one.
     *
     * Existing balances are never reset.
     */
    v_stage := 'create credit agent account';

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
    values (
        v_merchant.id,
        v_approver.country_code,
        v_currency_code,
        0,
        0,
        true,
        v_approver.id,
        now(),
        now()
    )
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
            now()
    returning *
    into v_account;

    return jsonb_build_object(
        'success',
        true,

        'credit_agent_account_id',
        v_account.id,

        'merchant_id',
        v_merchant.id,

        'merchant_email',
        v_merchant.email,

        'merchant_phone',
        v_merchant.phone,

        'country_code',
        v_account.country_code,

        'currency_code',
        v_account.currency_code,

        'receivable_balance',
        v_account.receivable_balance::text,

        'cash_holding_balance',
        v_account.cash_holding_balance::text,

        'is_active',
        v_account.is_active,

        'approved_by',
        v_account.approved_by,

        'created_at',
        v_account.created_at,

        'updated_at',
        v_account.updated_at
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
        text,
        text
    )
from public;

revoke all on function
    public.approve_my_credit_agent(
        text,
        text
    )
from anon;

grant execute on function
    public.approve_my_credit_agent(
        text,
        text
    )
to authenticated;