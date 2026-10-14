create or replace function public.create_my_credit_agent_cash_withdrawal_state(
    p_transaction jsonb,
    p_sender_approval jsonb
)
returns text
language plpgsql
security definer
set search_path to ''
as $function$
declare
    v_stage text :=
        'initialization';

    v_authenticated_user_id text;

    v_transaction_version text;
    v_reference text;
    v_user_id text;
    v_currency_code text;

    v_approval_user_id text;

    v_context record;

    v_merchant public.users%rowtype;
    v_user public.users%rowtype;

    v_credit_agent_account
        public.credit_agent_account%rowtype;

    v_transaction_state_id
        public.transaction_state.id%type;

    v_error_state text;
    v_error_message text;
    v_error_detail text;
    v_error_hint text;
    v_error_context text;
begin
    /*
     * Authentication.
     */
    if auth.uid() is null then
        raise exception using
            errcode =
                '42501',

            message =
                'UNAUTHORIZED';
    end if;

    v_authenticated_user_id :=
        auth.uid()::text;

    if p_transaction is null then
        raise exception
            'TRANSACTION_DATA_IS_MISSING';
    end if;

    if p_sender_approval is null then
        raise exception
            'SENDER_APPROVAL_IS_MISSING';
    end if;

    /*
     * Read the signed transaction fields.
     *
     * v = transaction version
     * r = transaction reference
     * s = withdrawing customer
     * c = currency
     */
    v_stage :=
        'read transaction fields';

    v_transaction_version :=
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

    v_user_id :=
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

    /*
     * The approval belongs to the authenticated merchant.
     */
    v_approval_user_id :=
        nullif(
            btrim(
                p_sender_approval ->> 'b'
            ),
            ''
        );

    if v_transaction_version is null then
        raise exception
            'TRANSACTION_VERSION_REQUIRED';
    end if;

    if v_transaction_version <> 'v3' then
        raise exception
            'OPERATION_NOT_ALLOWED';
    end if;

    if v_reference is null then
        raise exception
            'REFERENCE_REQUIRED';
    end if;

    if v_user_id is null then
        raise exception
            'USER_NOT_FOUND';
    end if;

    if v_currency_code is null then
        raise exception
            'CURRENCY_REQUIRED';
    end if;

    if v_approval_user_id is null then
        raise exception
            'APPROVAL_USER_ID_REQUIRED';
    end if;

    if v_approval_user_id <>
       v_authenticated_user_id
    then
        raise exception
            'APPROVAL_USER_MISMATCH';
    end if;

    if v_user_id =
       v_authenticated_user_id
    then
        raise exception
            'SELF_TRANSACTION_NOT_ALLOWED';
    end if;

    /*
     * Reuse the existing cash-withdrawal context.
     *
     * It validates the authenticated provider, the
     * customer, countries, wallet addresses and v3
     * transaction configuration.
     */
    v_stage :=
        'fetch cash withdrawal context';

    select context_record.*
    into v_context
    from public.fetch_my_cash_withdrawal_context(
        p_v =>
            v_transaction_version,

        p_user_id =>
            v_user_id
    ) as context_record;

    if not found then
        raise exception
            'CASH_WITHDRAWAL_CONTEXT_NOT_FOUND';
    end if;

    if v_context.agent_id is null then
        raise exception
            'MERCHANT_NOT_FOUND';
    end if;

    if v_context.agent_id <>
       v_authenticated_user_id
    then
        raise exception
            'MERCHANT_MISMATCH';
    end if;

    if v_context.user_id is null then
        raise exception
            'USER_NOT_FOUND';
    end if;

    if v_context.user_id <>
       v_user_id
    then
        raise exception
            'USER_MISMATCH';
    end if;

    if v_context.country_code is null then
        raise exception
            'MERCHANT_COUNTRY_NOT_CONFIGURED';
    end if;

    if v_context.user_country_code is null then
        raise exception
            'USER_COUNTRY_NOT_CONFIGURED';
    end if;

    if lower(v_context.country_code) <>
       lower(v_context.user_country_code)
    then
        raise exception
            'COUNTRY_MISMATCH';
    end if;

    /*
     * Explicitly require the authenticated provider to
     * be an active merchant.
     */
    v_stage :=
        'validate merchant';

    select merchant_record.*
    into v_merchant
    from public.users merchant_record
    join public.user_role role_record
      on role_record.id =
         merchant_record.role_id
    where merchant_record.id =
          v_authenticated_user_id

      and merchant_record.status =
          'active'::public."UserStatus"

      and lower(
          role_record.name::text
      ) =
          'merchant'

      and lower(
          merchant_record.country_code
      ) =
          lower(v_context.country_code)
    limit 1;

    if not found then
        raise exception using
            errcode =
                '42501',

            message =
                'MERCHANT_NOT_AUTHORIZED';
    end if;

    /*
     * Confirm that the withdrawing user is still active.
     */
    v_stage :=
        'validate withdrawing user';

    select user_record.*
    into v_user
    from public.users user_record
    where user_record.id =
          v_user_id

      and user_record.status =
          'active'::public."UserStatus"

      and lower(
          user_record.country_code
      ) =
          lower(v_merchant.country_code)
    limit 1;

    if not found then
        raise exception
            'USER_NOT_ACTIVE';
    end if;

    /*
     * The merchant-wide approval creates one operational
     * balance row for each supported fiat currency.
     *
     * This check confirms that the merchant is approved
     * and active for the signed transaction currency.
     */
    v_stage :=
        'validate credit agent account';

    select account_record.*
    into v_credit_agent_account
    from public.credit_agent_account
        account_record
    where account_record.merchant_id =
          v_merchant.id

      and lower(
          account_record.country_code
      ) =
          lower(v_merchant.country_code)

      and lower(
          account_record.currency_code
      ) =
          v_currency_code

      and account_record.is_active =
          true
    limit 1;

    if not found then
        raise exception
            'CREDIT_AGENT_ACCOUNT_NOT_ACTIVE';
    end if;

    /*
     * A credit-agent withdrawal may use:
     *
     * 1. cash already held by the merchant;
     * 2. the remaining receivable balance;
     * 3. or a combination of both.
     *
     * The exact balance split is calculated later inside
     * the service-only posting transaction while the
     * credit-agent account is locked.
     */
    if
        coalesce(
            v_credit_agent_account.cash_holding_balance,
            0
        ) +
        coalesce(
            v_credit_agent_account.receivable_balance,
            0
        )
        <= 0
    then
        raise exception
            'CREDIT_AGENT_WITHDRAWAL_BALANCE_NOT_AVAILABLE';
    end if;

    /*
     * Prevent reference replay before creating another
     * processing state.
     */
    v_stage :=
        'check transaction replay';

    perform 1
    from public.transaction_state
        transaction_state_record
    where transaction_state_record.reference =
          v_reference
    limit 1;

    if found then
        raise exception using
            errcode =
                '23505',

            message =
                'TRANSACTION_REPLAY';
    end if;

    /*
     * Store the signed payloads exactly as received.
     *
     * created_by = authenticated merchant
     * user_id    = withdrawing customer
     */
    v_stage :=
        'create transaction state';

    insert into public.transaction_state (
        reference,
        transaction_type,
        transaction_data,
        sender_approval,
        status,
        created_by,
        user_id,
        country_code,
        created_at,
        updated_at
    )
    values (
        v_reference,
        'credit_agent_cash_withdrawal'::public."TransactionType",
        p_transaction,
        p_sender_approval,
        'processing'::public."TransactionStatus",
        v_merchant.id,
        v_user.id,
        v_merchant.country_code,
        now(),
        now()
    )
    returning id
    into v_transaction_state_id;

    return
        v_transaction_state_id::text;

exception
    when unique_violation then
        raise exception using
            errcode =
                '23505',

            message =
                'TRANSACTION_REPLAY';

    when others then
        get stacked diagnostics
            v_error_state =
                returned_sqlstate,

            v_error_message =
                message_text,

            v_error_detail =
                pg_exception_detail,

            v_error_hint =
                pg_exception_hint,

            v_error_context =
                pg_exception_context;

        raise exception using
            errcode =
                v_error_state,

            message =
                format(
                    'CREATE_CREDIT_AGENT_CASH_WITHDRAWAL_STATE_FAILED at [%s]: %s',
                    v_stage,
                    v_error_message
                ),

            detail =
                concat_ws(
                    E'\n',
                    nullif(
                        v_error_detail,
                        ''
                    ),
                    nullif(
                        v_error_context,
                        ''
                    )
                ),

            hint =
                coalesce(
                    nullif(
                        v_error_hint,
                        ''
                    ),
                    format(
                        'Check the Credit Agent Cash Withdrawal State stage: %s',
                        v_stage
                    )
                );
end;
$function$;


revoke all on function
    public.create_my_credit_agent_cash_withdrawal_state(
        jsonb,
        jsonb
    )
from public;

revoke all on function
    public.create_my_credit_agent_cash_withdrawal_state(
        jsonb,
        jsonb
    )
from anon;

grant execute on function
    public.create_my_credit_agent_cash_withdrawal_state(
        jsonb,
        jsonb
    )
to authenticated;