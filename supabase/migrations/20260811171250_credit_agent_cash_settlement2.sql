create or replace function public.create_my_credit_agent_cash_settlement_state(
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

    v_authenticated_merchant_id text;

    v_transaction_version text;
    v_reference text;
    v_accounts_id text;
    v_currency_code text;

    v_amount_minor numeric;

    v_approval_merchant_id text;

    v_context record;

    v_transaction_state_id
        public.transaction_state.id%type;

    v_error_state text;
    v_error_message text;
    v_error_detail text;
    v_error_hint text;
    v_error_context text;
begin
    /*
     * The merchant scans the accounts-generated
     * transaction and submits the signed approval.
     */
    if auth.uid() is null then
        raise exception using
            errcode =
                '42501',

            message =
                'UNAUTHORIZED';
    end if;

    v_authenticated_merchant_id :=
        auth.uid()::text;

    if not public.has_role(
        array[
            'merchant'::public."Role"
        ]::public."Role"[]
    ) then
        raise exception using
            errcode =
                '42501',

            message =
                'FORBIDDEN';
    end if;

    if p_transaction is null then
        raise exception
            'TRANSACTION_DATA_IS_MISSING';
    end if;

    if p_sender_approval is null then
        raise exception
            'SENDER_APPROVAL_IS_MISSING';
    end if;

    /*
     * Read signed transaction fields.
     *
     * v = transaction version
     * r = reference
     * s = accounts user ID
     * c = currency
     * a = amount in minor units
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

    v_accounts_id :=
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
     * The approval must belong to the authenticated
     * merchant submitting the request.
     */
    v_approval_merchant_id :=
        nullif(
            btrim(
                p_sender_approval ->> 'b'
            ),
            ''
        );

    if v_transaction_version <> 'v8' then
        raise exception
            'OPERATION_NOT_ALLOWED';
    end if;

    if v_reference is null then
        raise exception
            'REFERENCE_REQUIRED';
    end if;

    if v_accounts_id is null then
        raise exception
            'ACCOUNTS_ID_MISSING';
    end if;

    if v_currency_code is null then
        raise exception
            'CURRENCY_REQUIRED';
    end if;

    if v_currency_code = 'gold' then
        raise exception
            'INVALID_SETTLEMENT_CURRENCY';
    end if;

    if coalesce(
        p_transaction ->> 'a',
        ''
    ) !~ '^[0-9]+$'
    then
        raise exception
            'INVALID_AMOUNT';
    end if;

    v_amount_minor :=
        (p_transaction ->> 'a')::numeric;

    if v_amount_minor <= 0 then
        raise exception
            'INVALID_AMOUNT';
    end if;

    if v_approval_merchant_id is null then
        raise exception
            'APPROVAL_USER_ID_REQUIRED';
    end if;

    if v_approval_merchant_id <>
       v_authenticated_merchant_id
    then
        raise exception
            'APPROVAL_USER_MISMATCH';
    end if;

    if v_accounts_id =
       v_authenticated_merchant_id
    then
        raise exception
            'OPERATION_NOT_ALLOWED';
    end if;

    /*
     * Reuse the trusted settlement context.
     *
     * This confirms:
     *
     * - authenticated user is an active merchant;
     * - transaction.s is an active accounts user;
     * - both users belong to the same country;
     * - the merchant has an active credit-agent account;
     * - treasury exists for the merchant country;
     * - v1 is configured.
     */
    v_stage :=
        'fetch settlement context';

    select context_record.*
    into v_context
    from public.fetch_my_credit_agent_cash_settlement_context(
        p_v =>
            v_transaction_version,

        p_accounts_id =>
            v_accounts_id,

        p_currency_code =>
            v_currency_code
    ) as context_record;

    if not found then
        raise exception
            'CREDIT_AGENT_CASH_SETTLEMENT_CONTEXT_NOT_FOUND';
    end if;

    if v_context.merchant_id is null
       or v_context.merchant_id <>
          v_authenticated_merchant_id
    then
        raise exception
            'MERCHANT_MISMATCH';
    end if;

    if v_context.accounts_id is null
       or v_context.accounts_id <>
          v_accounts_id
    then
        raise exception
            'ACCOUNTS_USER_MISMATCH';
    end if;

    if v_context.merchant_country_code is null then
        raise exception
            'MERCHANT_COUNTRY_NOT_CONFIGURED';
    end if;

    if v_context.accounts_country_code is null then
        raise exception
            'ACCOUNTS_COUNTRY_NOT_CONFIGURED';
    end if;

    if v_context.merchant_country_code <>
       v_context.accounts_country_code
    then
        raise exception
            'COUNTRY_MISMATCH';
    end if;

    if v_context.treasury_id is null then
        raise exception
            'TREASURY_NOT_FOUND';
    end if;

    /*
     * Reject a previously used signed reference.
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
     * The authenticated merchant creates the state.
     *
     * The accounts user is stored as the other signed
     * participant and will later be recorded as the
     * financial transaction creator.
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
        'credit_agent_cash_settlement'::public."TransactionType",
        p_transaction,
        p_sender_approval,
        'processing'::public."TransactionStatus",
        v_authenticated_merchant_id,
        v_accounts_id,
        v_context.merchant_country_code,
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
                    'CREATE_CREDIT_AGENT_CASH_SETTLEMENT_STATE_FAILED at [%s]: %s',
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
                        'Check the Credit Agent Cash Settlement State stage: %s',
                        v_stage
                    )
                );
end;
$function$;


revoke all on function
    public.create_my_credit_agent_cash_settlement_state(
        jsonb,
        jsonb
    )
from public;

revoke all on function
    public.create_my_credit_agent_cash_settlement_state(
        jsonb,
        jsonb
    )
from anon;

grant execute on function
    public.create_my_credit_agent_cash_settlement_state(
        jsonb,
        jsonb
    )
to authenticated;