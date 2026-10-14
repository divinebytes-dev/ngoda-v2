create or replace function
    public.create_my_credit_agent_cash_deposit_state(
        p_transaction jsonb,
        p_sender_approval jsonb
    )
returns text
language plpgsql
security definer
set search_path to ''
as $function$
declare
    v_user public.users%rowtype;
    v_provider public.users%rowtype;

    v_transaction_state_id
        public.transaction_state.id%type;

    v_reference text;
    v_provider_id text;
    v_currency_code text;
    v_version text;
    v_approval_user_id text;

    v_stage text := 'initialization';
    v_error_state text;
    v_error_message text;
    v_error_detail text;
    v_error_hint text;
    v_error_context text;
begin
    /*
     * Authentication.
     */
    v_stage := 'authenticate user';

    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHENTICATED';
    end if;

    /*
     * Validate JSON input.
     */
    v_stage := 'validate input';

    if p_transaction is null
       or p_transaction =
          'null'::jsonb
    then
        raise exception
            'TRANSACTION_DATA_MISSING';
    end if;

    if p_sender_approval is null
       or p_sender_approval =
          'null'::jsonb
    then
        raise exception
            'SENDER_APPROVAL_MISSING';
    end if;

    v_version :=
        nullif(
            btrim(
                p_transaction ->> 'v'
            ),
            ''
        );

    v_reference :=
        nullif(
            btrim(
                p_transaction ->> 'r'
            ),
            ''
        );

    v_provider_id :=
        nullif(
            btrim(
                p_transaction ->> 's'
            ),
            ''
        );

    v_currency_code :=
        lower(
            nullif(
                btrim(
                    p_transaction ->> 'c'
                ),
                ''
            )
        );

    v_approval_user_id :=
        nullif(
            btrim(
                p_sender_approval ->> 'b'
            ),
            ''
        );

    if v_version is null then
        raise exception
            'TRANSACTION_VERSION_REQUIRED';
    end if;

    if v_version <> 'v1' then
        raise exception
            'OPERATION_NOT_ALLOWED';
    end if;

    if v_reference is null then
        raise exception
            'REFERENCE_REQUIRED';
    end if;

    if v_provider_id is null then
        raise exception
            'PROVIDER_ID_REQUIRED';
    end if;

    if v_currency_code is null then
        raise exception
            'CURRENCY_REQUIRED';
    end if;

    if v_currency_code = 'gold' then
        raise exception
            'CREDIT_AGENT_CURRENCY_MUST_BE_FIAT';
    end if;

    if v_approval_user_id is null then
        raise exception
            'APPROVAL_USER_ID_REQUIRED';
    end if;

    if v_approval_user_id <>
       auth.uid()::text
    then
        raise exception
            'APPROVAL_USER_MISMATCH';
    end if;

    if v_provider_id =
       auth.uid()::text
    then
        raise exception
            'INVALID_DEPOSIT_PROVIDER';
    end if;

    /*
     * Reuse the established cash-deposit context.
     *
     * It validates:
     *
     * - authenticated initiating user;
     * - provider;
     * - user status;
     * - provider status;
     * - country;
     * - transaction version.
     */
    v_stage := 'validate cash deposit context';

    perform 1
    from public.fetch_my_cash_deposit_context(
        p_v =>
            v_version,

        p_provider_id =>
            v_provider_id
    );

    if not found then
        raise exception
            'CASH_DEPOSIT_CONTEXT_NOT_FOUND';
    end if;

    /*
     * Fetch authenticated user.
     */
    v_stage := 'fetch user';

    v_user :=
        public.fetch_user_by_id(
            auth.uid()::text
        );

    if v_user.id is null then
        raise exception
            'USER_NOT_FOUND';
    end if;

    if v_user.status <>
       'active'::public."UserStatus"
    then
        raise exception
            'USER_NOT_ACTIVE';
    end if;

    if v_user.country_code is null then
        raise exception
            'USER_COUNTRY_NOT_CONFIGURED';
    end if;

    /*
     * The provider must specifically be an active merchant.
     *
     * Normal agents may use cash_deposit but cannot use
     * credit_agent_cash_deposit.
     */
    v_stage := 'fetch merchant provider';

    select user_record.*
    into v_provider
    from public.users user_record
    join public.user_role role_record
      on role_record.id =
         user_record.role_id
    where user_record.id =
              v_provider_id

      and user_record.country_code =
              v_user.country_code

      and user_record.status =
              'active'::public."UserStatus"

      and lower(
          role_record.name::text
      ) =
              'merchant'
    limit 1;

    if not found then
        raise exception
            'CREDIT_AGENT_MERCHANT_NOT_FOUND';
    end if;

    /*
     * The merchant must have an active credit-agent account for
     * the transaction currency.
     *
     * Approval creates accounts for every active fiat currency.
     */
    v_stage := 'validate credit agent account';

    perform 1
    from public.credit_agent_account
        account_record
    where account_record.merchant_id =
              v_provider.id

      and account_record.country_code =
              v_user.country_code

      and account_record.currency_code =
              v_currency_code

      and account_record.is_active =
              true
    limit 1;

    if not found then
        raise exception
            'MERCHANT_NOT_APPROVED_FOR_CREDIT_FACILITY';
    end if;

    /*
     * Prevent reference replay.
     */
    v_stage := 'check transaction replay';

    perform 1
    from public.transaction_state
        state_record
    where state_record.reference =
          v_reference
    limit 1;

    if found then
        raise exception
            'TRANSACTION_REPLAY';
    end if;

    /*
     * Create processing state.
     */
    v_stage := 'create transaction state';

    insert into public.transaction_state (
        reference,
        status,
        transaction_type,
        country_code,
        transaction_data,
        sender_approval,
        created_by,
        user_id
    )
    values (
        v_reference,
        'processing'::public."TransactionStatus",
        'credit_agent_cash_deposit'::public."TransactionType",
        v_user.country_code,
        p_transaction,
        p_sender_approval,
        v_user.id,
        v_provider.id
    )
    returning id
    into v_transaction_state_id;

    return v_transaction_state_id::text;

exception
    when unique_violation then
        raise exception
            'TRANSACTION_REPLAY';

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
                'CREATE_CREDIT_AGENT_CASH_DEPOSIT_STATE_FAILED at [%s]: %s',
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
                'Check the Credit Agent Cash Deposit State stage reported in the error'
            );
end;
$function$;


revoke all on function
    public.create_my_credit_agent_cash_deposit_state(
        jsonb,
        jsonb
    )
from public;

revoke all on function
    public.create_my_credit_agent_cash_deposit_state(
        jsonb,
        jsonb
    )
from anon;

grant execute on function
    public.create_my_credit_agent_cash_deposit_state(
        jsonb,
        jsonb
    )
to authenticated;