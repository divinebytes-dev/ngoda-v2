/* =========================================================
 * FETCH MY CASH-WITHDRAWAL CONTEXT
 * ========================================================= */

create or replace function public.fetch_my_cash_withdrawal_context(
    p_v text,
    p_user_id text
)
returns table (
    agent_id text,
    country_code text,
    agent_wallet_address text,
    user_id text,
    user_country_code text,
    user_wallet_address text,
    version_time integer
)
language plpgsql
stable
security definer
set search_path to ''
as $function$
begin
    /*
     * Validate authentication.
     */
    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHORIZED';
    end if;

    /*
     * Cash withdrawal remains on transaction version v3.
     */
    if p_v is distinct from 'v3' then
        raise exception
            'OPERATION_NOT_ALLOWED';
    end if;

    /*
     * Only agents, vendors and merchants may initiate a
     * cash withdrawal.
     */
    if not public.has_role(
        array[
            'agent'::public."Role",
            'merchant'::public."Role",
            'vendor'::public."Role"
        ]::public."Role"[]
    ) then
        raise exception using
            errcode = '42501',
            message = 'FORBIDDEN';
    end if;

    if p_user_id is null
       or btrim(p_user_id) = ''
    then
        raise exception
            'USER_ID_MISSING';
    end if;

    /*
     * The agent cannot withdraw from their own
     * customer wallet through this transaction.
     */
    if auth.uid()::text =
       btrim(p_user_id)
    then
        raise exception
            'OPERATION_NOT_ALLOWED';
    end if;

    /*
     * The withdrawing user must have a role that owns
     * a customer wallet.
     */
    if not public.user_has_role(
        btrim(p_user_id),
        array[
            'customer'::public."Role",
            'agent'::public."Role",
            'vendor'::public."Role"
        ]::public."Role"[]
    ) then
        raise exception using
            errcode = '42501',
            message = 'USER_NOT_AUTHORIZED';
    end if;

    /*
     * Return trusted information for both participants.
     *
     * The agent is derived from auth.uid().
     * The withdrawing user comes from transaction.s.
     */
    return query
    select
        agent_record.id,
        agent_record.country_code,
        agent_record.wallet_address,

        user_record.id,
        user_record.country_code,
        user_record.wallet_address,

        public.get_transaction_v(p_v)
    from public.users agent_record
    join public.users user_record
      on user_record.id =
         btrim(p_user_id)
    where agent_record.id =
          auth.uid()::text
      and agent_record.status =
          'active'::public."UserStatus"
      and user_record.status =
          'active'::public."UserStatus"
      and agent_record.country_code =
          user_record.country_code
    limit 1;

    if not found then
        raise exception
            'CASH_WITHDRAWAL_CONTEXT_NOT_FOUND';
    end if;
end;
$function$;


/* =========================================================
 * CREATE MY CASH-WITHDRAWAL TRANSACTION STATE
 * ========================================================= */

create or replace function public.create_my_cash_withdrawal_state(
    p_transaction jsonb,
    p_sender_approval jsonb
)
returns text
language plpgsql
security definer
set search_path to ''
as $function$
declare
    v_agent_id text;
    v_user_id text;
    v_country_code text;
    v_reference text;
    v_version text;

    v_transaction_state_id text;
begin
    /*
     * Validate authentication.
     */
    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHORIZED';
    end if;

    /*
     * Only agents, vendors and merchants may initiate
     * cash withdrawals.
     */
    if not public.has_role(
        array[
            'agent'::public."Role",
            'merchant'::public."Role",
            'vendor'::public."Role"
        ]::public."Role"[]
    ) then
        raise exception using
            errcode = '42501',
            message = 'FORBIDDEN';
    end if;

    /*
     * Validate the supplied signed objects.
     */
    if p_transaction is null
       or jsonb_typeof(p_transaction) <>
          'object'
    then
        raise exception
            'TRANSACTION_DATA_IS_MISSING';
    end if;

    if p_sender_approval is null
       or jsonb_typeof(p_sender_approval) <>
          'object'
    then
        raise exception
            'SENDER_APPROVAL_IS_MISSING';
    end if;

    /*
     * Validate the transaction version.
     */
    v_version :=
        nullif(
            btrim(p_transaction ->> 'v'),
            ''
        );

    if v_version is distinct from 'v3' then
        raise exception
            'OPERATION_NOT_ALLOWED';
    end if;

    /*
     * Parse the unique transaction reference.
     */
    v_reference :=
        nullif(
            btrim(p_transaction ->> 'r'),
            ''
        );

    if v_reference is null then
        raise exception
            'REFERENCE_MISSING';
    end if;

    /*
     * transaction.s is the withdrawing user.
     */
    v_user_id :=
        nullif(
            btrim(p_transaction ->> 's'),
            ''
        );

    if v_user_id is null then
        raise exception
            'USER_ID_MISSING';
    end if;

    v_agent_id :=
        auth.uid()::text;

    if v_agent_id = v_user_id then
        raise exception
            'OPERATION_NOT_ALLOWED';
    end if;

    /*
     * Validate the withdrawing user's role.
     */
    if not public.user_has_role(
        v_user_id,
        array[
            'customer'::public."Role",
            'agent'::public."Role",
            'vendor'::public."Role"
        ]::public."Role"[]
    ) then
        raise exception using
            errcode = '42501',
            message = 'USER_NOT_AUTHORIZED';
    end if;

    /*
     * Fetch the agent country and ensure both users
     * belong to the same country.
     */
    select agent_record.country_code
    into v_country_code
    from public.users agent_record
    join public.users user_record
      on user_record.id =
         v_user_id
    where agent_record.id =
          v_agent_id
      and agent_record.status =
          'active'::public."UserStatus"
      and user_record.status =
          'active'::public."UserStatus"
      and agent_record.country_code =
          user_record.country_code
    limit 1;

    if not found then
        raise exception
            'CASH_WITHDRAWAL_PARTICIPANTS_NOT_VALID';
    end if;

    /*
     * Reference is unique and provides replay protection.
     */
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
        'cash_withdrawal'::public."TransactionType",
        v_country_code,
        p_transaction,
        p_sender_approval,
        v_agent_id,
        v_user_id
    )
    returning id::text
    into v_transaction_state_id;

    return v_transaction_state_id;

exception
    when unique_violation then
        raise exception using
            errcode = '23505',
            message = 'TRANSACTION_REPLAY';
end;
$function$;


/* =========================================================
 * FUNCTION OWNERS
 * ========================================================= */

alter function public.fetch_my_cash_withdrawal_context(
    text,
    text
)
owner to postgres;

alter function public.create_my_cash_withdrawal_state(
    jsonb,
    jsonb
)
owner to postgres;


/* =========================================================
 * EXECUTION PERMISSIONS
 * ========================================================= */

revoke execute on function
    public.fetch_my_cash_withdrawal_context(
        text,
        text
    )
from public, anon;

grant execute on function
    public.fetch_my_cash_withdrawal_context(
        text,
        text
    )
to authenticated;


revoke execute on function
    public.create_my_cash_withdrawal_state(
        jsonb,
        jsonb
    )
from public, anon;

grant execute on function
    public.create_my_cash_withdrawal_state(
        jsonb,
        jsonb
    )
to authenticated;


/* =========================================================
 * RELOAD POSTGREST
 * ========================================================= */

notify pgrst, 'reload schema';