/*
 * ============================================================
 * GOLD TOKEN TRANSFER
 *
 * Transaction version: v6
 * Allowed roles:
 *   - customer
 *   - agent
 *   - vendor
 *
 * All allowed roles transfer through their customer Gold wallet.
 * ============================================================
 */


/*
 * ============================================================
 * 1. AUTHENTICATED GOLD TRANSFER CONTEXT
 * ============================================================
 */

create or replace function public.fetch_my_gold_transfer_context(
    p_v text
)
returns table (
    sender_id text,
    country_code text,
    wallet_address text,
    wallet_index bigint,
    version_time bigint
)
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
    v_sender public.users%rowtype;
    v_version_time bigint;
begin
    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHORIZED';
    end if;

    if p_v is distinct from 'v6' then
        raise exception using
            errcode = '42501',
            message = 'OPERATION_NOT_ALLOWED';
    end if;

    /*
     * Role validation applies to the authenticated user.
     *
     * Agent and vendor users are allowed because they also
     * own customer wallets.
     */
    if not public.has_role(
        array[
            'customer',
            'agent',
            'vendor'
        ]::text[]
    ) then
        raise exception using
            errcode = '42501',
            message = 'FORBIDDEN';
    end if;

    select sender_record.*
    into v_sender
    from public.users sender_record
    where sender_record.id =
          auth.uid()::text
    limit 1;

    if not found then
        raise exception
            'SENDER_NOT_FOUND';
    end if;

    if v_sender.status <>
       'active'::public."UserStatus"
    then
        raise exception
            'SENDER_NOT_ACTIVE';
    end if;

    if v_sender.country_code is null
       or btrim(v_sender.country_code) = ''
    then
        raise exception
            'USER_COUNTRY_NOT_CONFIGURED';
    end if;

    if v_sender.wallet_address is null
       or btrim(v_sender.wallet_address) = ''
    then
        raise exception
            'USER_WALLET_NOT_CONFIGURED';
    end if;

    /*
     * Wallet index zero is valid, so only check for null.
     */
    if v_sender.wallet_index is null then
        raise exception
            'USER_WALLET_INDEX_NOT_CONFIGURED';
    end if;

    /*
     * Reuse the centralized transaction-version function.
     */
    select public.fetch_transaction_v(
        p_v
    )
    into v_version_time;

    if v_version_time is null
       or v_version_time <= 0
    then
        raise exception
            'INVALID_TRANSACTION_VERSION';
    end if;

    return query
    select
        v_sender.id,
        lower(
            btrim(
                v_sender.country_code
            )
        ),
        v_sender.wallet_address,
        v_sender.wallet_index::bigint,
        v_version_time;
end;
$function$;


/*
 * ============================================================
 * 2. CREATE AUTHENTICATED PROCESSING STATE
 * ============================================================
 */

create or replace function public.create_my_gold_transfer_state(
    p_transaction jsonb
)
returns text
language plpgsql
security definer
set search_path to ''
as $function$
declare
    v_sender public.users%rowtype;
    v_receiver public.users%rowtype;

    v_reference text;
    v_receiver_identifier text;
    v_currency text;
    v_version text;
    v_transaction_id text;
begin
    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHORIZED';
    end if;

    if p_transaction is null then
        raise exception
            'TRANSACTION_DATA_IS_MISSING';
    end if;

    if not public.has_role(
        array[
            'customer',
            'agent',
            'vendor'
        ]::text[]
    ) then
        raise exception using
            errcode = '42501',
            message = 'FORBIDDEN';
    end if;

    v_version :=
        nullif(
            btrim(
                p_transaction ->> 'v'
            ),
            ''
        );

    if v_version is distinct from 'v6' then
        raise exception
            'OPERATION_NOT_ALLOWED';
    end if;

    v_reference :=
        nullif(
            btrim(
                p_transaction ->> 'r'
            ),
            ''
        );

    if v_reference is null then
        raise exception
            'REFERENCE_IS_REQUIRED';
    end if;

    v_receiver_identifier :=
        nullif(
            btrim(
                p_transaction ->> 's'
            ),
            ''
        );

    if v_receiver_identifier is null then
        raise exception
            'RECEIVER_IDENTIFIER_IS_REQUIRED';
    end if;

    v_currency :=
        lower(
            nullif(
                btrim(
                    p_transaction ->> 'c'
                ),
                ''
            )
        );

    if v_currency is distinct from 'gold' then
        raise exception
            'INVALID_GOLD_TRANSFER_CURRENCY';
    end if;

    select sender_record.*
    into v_sender
    from public.users sender_record
    where sender_record.id =
          auth.uid()::text
    limit 1;

    if not found then
        raise exception
            'SENDER_NOT_FOUND';
    end if;

    if v_sender.status <>
       'active'::public."UserStatus"
    then
        raise exception
            'SENDER_NOT_ACTIVE';
    end if;

    v_receiver :=
        public.fetch_user_by_email_or_phone(
            v_receiver_identifier
        );

    if v_receiver.id is null then
        raise exception
            'RECEIVER_NOT_FOUND';
    end if;

    if v_receiver.status <>
       'active'::public."UserStatus"
    then
        raise exception
            'RECEIVER_NOT_ACTIVE';
    end if;

    if v_sender.id =
       v_receiver.id
    then
        raise exception
            'OPERATION_NOT_ALLOWED';
    end if;

    if v_sender.country_code is distinct from
       v_receiver.country_code
    then
        raise exception
            'OPERATION_NOT_ALLOWED';
    end if;

    if v_sender.wallet_address is null
       or btrim(v_sender.wallet_address) = ''
    then
        raise exception
            'SENDER_WALLET_NOT_CONFIGURED';
    end if;

    if v_receiver.wallet_address is null
       or btrim(v_receiver.wallet_address) = ''
    then
        raise exception
            'RECEIVER_WALLET_NOT_CONFIGURED';
    end if;

    begin
        insert into public.transaction_state (
            reference,
            status,
            transaction_type,
            country_code,
            transaction_data,
            created_by,
            user_id
        )
        values (
            v_reference,
            'processing'::public."TransactionStatus",
            'gold_token_transfer'::public."TransactionType",
            lower(
                btrim(
                    v_sender.country_code
                )
            ),
            p_transaction,
            v_sender.id,
            v_receiver.id
        )
        returning id::text
        into v_transaction_id;

    exception
        when unique_violation then
            raise exception using
                errcode = '23505',
                message = 'TRANSACTION_REPLAY';
    end;

    if v_transaction_id is null then
        raise exception
            'TRANSACTION_STATE_CREATE_FAILED';
    end if;

    return v_transaction_id;
end;
$function$;


/*
 * ============================================================
 * 3. TRUSTED GOLD TRANSFER PREPARATION
 * ============================================================
 */

create or replace function public.prepare_gold_transfer(
    p_sender_id text,
    p_transaction jsonb,
    p_country_code text,
    p_transaction_state_id text
)
returns table (
    sender_id text,
    sender_wallet_address text,
    sender_wallet_index bigint,

    receiver_id text,
    receiver_wallet_address text,

    treasury_id text,
    treasury_wallet_address text,

    country_code text,
    fiscal_year integer,
    period integer,
    document_prefix text,

    amount text,
    fee text,
    total_amount text,

    mappings public.transaction_gl_mapping[],
    components public.posting_component[]
)
language plpgsql
security definer
set search_path to ''
as $function$
declare
    v_state public.transaction_state%rowtype;

    v_sender public.users%rowtype;
    v_receiver public.users%rowtype;
    v_treasury public.users%rowtype;

    v_receiver_identifier text;
    v_reference text;
    v_currency text;

    v_raw_amount numeric;
    v_amount numeric;
    v_fee numeric := 0;
    v_total_amount numeric;

    v_fiscal_year integer;
    v_period integer;
    v_document_prefix text;

    v_mappings
        public.transaction_gl_mapping[];

    v_components
        public.posting_component[];

    v_adjusted_components
        public.posting_component[] :=
            array[]::public.posting_component[];

    v_component
        public.posting_component;

    v_adjusted_component
        public.posting_component;
begin
    /*
     * This function is only called by the Edge Function's
     * service-role client.
     */
    if coalesce(
        auth.role(),
        ''
    ) <> 'service_role'
    then
        raise exception using
            errcode = '42501',
            message = 'SERVICE_ROLE_REQUIRED';
    end if;

    if p_transaction is null then
        raise exception
            'TRANSACTION_DATA_IS_MISSING';
    end if;

    /*
     * Lock and validate the processing state created with
     * the authenticated client.
     */
    select state_record.*
    into v_state
    from public.transaction_state state_record
    where state_record.id =
          p_transaction_state_id
      and state_record.created_by =
          p_sender_id
      and state_record.transaction_type =
          'gold_token_transfer'::public."TransactionType"
      and state_record.status =
          'processing'::public."TransactionStatus"
    for update;

    if not found then
        raise exception
            'INVALID_TRANSACTION_STATE';
    end if;

    if v_state.transaction_data
       is distinct from p_transaction
    then
        raise exception
            'TRANSACTION_DATA_MISMATCH';
    end if;

    if p_transaction ->> 'v'
       is distinct from 'v6'
    then
        raise exception
            'OPERATION_NOT_ALLOWED';
    end if;

    v_reference :=
        nullif(
            btrim(
                p_transaction ->> 'r'
            ),
            ''
        );

    if v_reference is null then
        raise exception
            'REFERENCE_IS_REQUIRED';
    end if;

    if v_state.reference is distinct from
       v_reference
    then
        raise exception
            'TRANSACTION_REFERENCE_MISMATCH';
    end if;

    v_receiver_identifier :=
        nullif(
            btrim(
                p_transaction ->> 's'
            ),
            ''
        );

    if v_receiver_identifier is null then
        raise exception
            'RECEIVER_IDENTIFIER_IS_REQUIRED';
    end if;

    v_currency :=
        lower(
            nullif(
                btrim(
                    p_transaction ->> 'c'
                ),
                ''
            )
        );

    if v_currency is distinct from 'gold' then
        raise exception
            'INVALID_GOLD_TRANSFER_CURRENCY';
    end if;

    /*
     * Parse the signed quantity.
     *
     * Preserve the existing transaction serialization rule:
     * transaction.a is divided by 100.
     */
    begin
        v_raw_amount :=
            (
                p_transaction ->> 'a'
            )::numeric / 100;
    exception
        when invalid_text_representation then
            raise exception
                'INVALID_QUANTITY';
    end;

    /*
     * Gold quantities are always rounded down to six
     * decimal places.
     */
    v_amount :=
        trunc(
            v_raw_amount,
            6
        );

    if v_amount <= 0 then
        raise exception
            'INVALID_QUANTITY';
    end if;

    /*
     * Fetch trusted users.
     */
    v_sender :=
        public.fetch_user_by_id(
            p_sender_id
        );

    v_receiver :=
        public.fetch_user_by_email_or_phone(
            v_receiver_identifier
        );

    v_treasury :=
        public.fetch_country_treasury(
            p_country_code
        );

    if v_sender.id is null then
        raise exception
            'SENDER_NOT_FOUND';
    end if;

    if v_receiver.id is null then
        raise exception
            'RECEIVER_NOT_FOUND';
    end if;

    if v_treasury.id is null then
        raise exception
            'TREASURY_NOT_FOUND';
    end if;

    if v_sender.status <>
       'active'::public."UserStatus"
    then
        raise exception
            'SENDER_NOT_ACTIVE';
    end if;

    if v_receiver.status <>
       'active'::public."UserStatus"
    then
        raise exception
            'RECEIVER_NOT_ACTIVE';
    end if;

    if v_sender.id =
       v_receiver.id
    then
        raise exception
            'OPERATION_NOT_ALLOWED';
    end if;

    if lower(
        btrim(
            v_sender.country_code
        )
    ) is distinct from lower(
        btrim(
            p_country_code
        )
    ) then
        raise exception
            'SENDER_COUNTRY_MISMATCH';
    end if;

    if v_sender.country_code is distinct from
       v_receiver.country_code
    then
        raise exception
            'OPERATION_NOT_ALLOWED';
    end if;

    if v_sender.wallet_address is null
       or btrim(v_sender.wallet_address) = ''
    then
        raise exception
            'SENDER_WALLET_NOT_CONFIGURED';
    end if;

    if v_sender.wallet_index is null then
        raise exception
            'SENDER_WALLET_INDEX_NOT_CONFIGURED';
    end if;

    if v_receiver.wallet_address is null
       or btrim(v_receiver.wallet_address) = ''
    then
        raise exception
            'RECEIVER_WALLET_NOT_CONFIGURED';
    end if;

    if v_treasury.wallet_address is null
       or btrim(v_treasury.wallet_address) = ''
    then
        raise exception
            'TREASURY_WALLET_NOT_CONFIGURED';
    end if;

    /*
     * Fetch fiscal period.
     */
    select
        fiscal_period.fiscal_year,
        fiscal_period.period
    into
        v_fiscal_year,
        v_period
    from public.fetch_fiscal_period(
        p_country_code
    ) as fiscal_period;

    if not found then
        raise exception
            'FISCAL_PERIOD_NOT_FOUND';
    end if;

    /*
     * Fetch GL mappings.
     */
    select array_agg(
        mapping_record
        order by
            mapping_record.component_type
    )
    into v_mappings
    from public.fetch_gl_mappings(
        'gold_token_transfer'::public."TransactionType"
    ) as mapping_record;

    if v_mappings is null
       or cardinality(
           v_mappings
       ) = 0
    then
        raise exception
            'GL_MAPPINGS_NOT_FOUND';
    end if;

    /*
     * Build the configured transfer components.
     *
     * Gold is an asset, therefore reverse remains true,
     * matching the original implementation.
     */
    v_components :=
        public.build_posting_components(
            'gold_token_transfer'::public."TransactionType",
            v_amount,
            v_mappings,
            p_country_code,
            'gold',
            true
        );

    if v_components is null
       or cardinality(
           v_components
       ) = 0
    then
        raise exception
            'POSTING_COMPONENTS_NOT_FOUND';
    end if;

    /*
     * Extract the configured transaction fee.
     */
    select greatest(
        coalesce(
            component_record.debit_amount,
            0
        ),
        coalesce(
            component_record.credit_amount,
            0
        )
    )
    into v_fee
    from unnest(
        v_components
    ) as component_record(
        component_type,
        debit_amount,
        credit_amount
    )
    where component_record.component_type =
          'transaction_fee'::public."ComponentType"
    limit 1;

    v_fee :=
        trunc(
            coalesce(
                v_fee,
                0
            ),
            6
        );

    if v_fee < 0 then
        raise exception
            'INVALID_FEE_AMOUNT';
    end if;

    v_total_amount :=
        v_amount +
        v_fee;

    /*
     * Preserve the original Gold Transfer component rules:
     *
     * Principal:
     *   debit  = transferred amount
     *   credit = transferred amount + fee
     *
     * Transaction fee:
     *   debit  = fee
     *   credit = zero
     */
    foreach v_component
    in array v_components
    loop
        v_adjusted_component :=
            v_component;

        if v_component.component_type =
           'principal'::public."ComponentType"
        then
            v_adjusted_component.debit_amount :=
                v_amount;

            v_adjusted_component.credit_amount :=
                v_total_amount;

        elsif v_component.component_type =
              'transaction_fee'::public."ComponentType"
        then
            v_adjusted_component.debit_amount :=
                v_fee;

            v_adjusted_component.credit_amount :=
                0;
        end if;

        v_adjusted_components :=
            array_append(
                v_adjusted_components,
                v_adjusted_component
            );
    end loop;

    v_components :=
        public.validate_components(
            v_adjusted_components
        );

    if v_components is null
       or cardinality(
           v_components
       ) = 0
    then
        raise exception
            'INVALID_POSTING_COMPONENTS';
    end if;

    v_document_prefix :=
        public.fetch_transaction_doc_num_prefix(
            'gold_token_transfer'::public."TransactionType"
        );

    if v_document_prefix is null
       or btrim(v_document_prefix) = ''
    then
        raise exception
            'DOCUMENT_PREFIX_NOT_FOUND';
    end if;

    return query
    select
        v_sender.id,
        v_sender.wallet_address,
        v_sender.wallet_index::bigint,

        v_receiver.id,
        v_receiver.wallet_address,

        v_treasury.id,
        v_treasury.wallet_address,

        lower(
            btrim(
                p_country_code
            )
        ),

        v_fiscal_year,
        v_period,
        v_document_prefix,

        v_amount::text,
        v_fee::text,
        v_total_amount::text,

        v_mappings,
        v_components;
end;
$function$;


/*
 * ============================================================
 * OWNERSHIP AND PERMISSIONS
 * ============================================================
 */

alter function public.fetch_my_gold_transfer_context(
    text
)
owner to postgres;

alter function public.create_my_gold_transfer_state(
    jsonb
)
owner to postgres;

alter function public.prepare_gold_transfer(
    text,
    jsonb,
    text,
    text
)
owner to postgres;


revoke all
on function public.fetch_my_gold_transfer_context(
    text
)
from public, anon, authenticated, service_role;

revoke all
on function public.create_my_gold_transfer_state(
    jsonb
)
from public, anon, authenticated, service_role;

revoke all
on function public.prepare_gold_transfer(
    text,
    jsonb,
    text,
    text
)
from public, anon, authenticated, service_role;


grant execute
on function public.fetch_my_gold_transfer_context(
    text
)
to authenticated;

grant execute
on function public.create_my_gold_transfer_state(
    jsonb
)
to authenticated;

grant execute
on function public.prepare_gold_transfer(
    text,
    jsonb,
    text,
    text
)
to service_role;