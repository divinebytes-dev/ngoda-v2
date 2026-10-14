/*
 * Ngoda cash transfer with optional loyalty-points fee redemption.
 *
 * Run this file before deploying the revised cash-transfer Edge Function.
 */

begin;


/* =========================================================
 * REDEMPTION CONFIGURATION
 * ========================================================= */

create table if not exists public.loyalty_redemption_config (
    id text primary key
        default (gen_random_uuid())::text,

    redemption_code text not null unique,
    transaction_type public."TransactionType" not null,
    country_code text,
    currency_code text,

    points_per_usd bigint not null,
    priority integer not null default 100,

    is_active boolean not null default true,
    valid_from timestamptz,
    valid_until timestamptz,

    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),

    constraint loyalty_redemption_code_check
        check (
            redemption_code = lower(btrim(redemption_code))
            and redemption_code ~ '^[a-z][a-z0-9_]*$'
        ),

    constraint loyalty_redemption_country_check
        check (
            country_code is null
            or country_code = lower(btrim(country_code))
        ),

    constraint loyalty_redemption_currency_check
        check (
            currency_code is null
            or currency_code = lower(btrim(currency_code))
        ),

    constraint loyalty_redemption_points_check
        check (points_per_usd >= 1),

    constraint loyalty_redemption_priority_check
        check (priority >= 1),

    constraint loyalty_redemption_dates_check
        check (
            valid_until is null
            or valid_from is null
            or valid_until > valid_from
        )
);


create index if not exists
    loyalty_redemption_scope_idx
on public.loyalty_redemption_config (
    transaction_type,
    coalesce(country_code, '*'),
    coalesce(currency_code, '*')
);


create index if not exists
    loyalty_redemption_resolution_idx
on public.loyalty_redemption_config (
    transaction_type,
    is_active,
    priority,
    country_code,
    currency_code
);


drop trigger if exists loyalty_redemption_config_updated_at_trigger
on public.loyalty_redemption_config;

create trigger loyalty_redemption_config_updated_at_trigger
before update on public.loyalty_redemption_config
for each row
execute function public.set_gamification_updated_at();


insert into public.loyalty_redemption_config (
    redemption_code,
    transaction_type,
    country_code,
    currency_code,
    points_per_usd,
    priority,
    is_active
)
values (
    'cash_transfer_fee_standard',
    'cash_transfer'::public."TransactionType",
    null,
    null,
    1000,
    100,
    true
)
on conflict (redemption_code) do update
set
    transaction_type = excluded.transaction_type,
    country_code = excluded.country_code,
    currency_code = excluded.currency_code,
    points_per_usd = excluded.points_per_usd,
    priority = excluded.priority,
    is_active = excluded.is_active;


alter table public.loyalty_redemption_config
    enable row level security;

revoke all on table public.loyalty_redemption_config
from anon, authenticated;

grant select on table public.loyalty_redemption_config
to service_role;


/* =========================================================
 * REDEMPTION LEDGER LINK AND IDEMPOTENCY
 * ========================================================= */

alter table public.loyalty_ledger
    add column if not exists source_transaction_id text;


create unique index if not exists
    loyalty_ledger_transfer_fee_redemption_unique
on public.loyalty_ledger (
    user_id,
    source_transaction_id
)
where ledger_type = 'redeem'::public."LoyaltyLedgerType"
  and source_transaction_id is not null;


create index if not exists
    loyalty_ledger_source_transaction_idx
on public.loyalty_ledger (source_transaction_id)
where source_transaction_id is not null;


/* =========================================================
 * ATOMIC TRANSFER-FEE REDEMPTION
 *
 * This function is called from cash_transfer. Because it is
 * called inside the posting RPC, the points movement and the
 * financial posting commit or roll back together.
 * ========================================================= */

create or replace function public.redeem_loyalty_points_for_transfer_fee(
    p_user_id text,
    p_source_reference text,
    p_source_transaction_id text,
    p_transaction_type public."TransactionType",
    p_country_code text,
    p_currency_code text,
    p_fee_amount numeric,
    p_fee_amount_usd numeric,
    p_points_to_redeem bigint,
    p_points_per_usd bigint
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
    v_user_id text;
    v_source_reference text;
    v_source_transaction_id text;
    v_country_code text;
    v_currency_code text;

    v_account public.loyalty_account%rowtype;
    v_ledger public.loyalty_ledger%rowtype;
begin
    if coalesce(auth.role(), '') <> 'service_role' then
        raise exception using
            errcode = '42501',
            message = 'SERVICE_ROLE_REQUIRED';
    end if;

    v_user_id :=
        nullif(btrim(p_user_id), '');

    v_source_reference :=
        nullif(btrim(p_source_reference), '');

    v_source_transaction_id :=
        nullif(btrim(p_source_transaction_id), '');

    v_country_code :=
        lower(nullif(btrim(p_country_code), ''));

    v_currency_code :=
        lower(nullif(btrim(p_currency_code), ''));

    if v_user_id is null then
        raise exception
            'LOYALTY_REDEMPTION_USER_REQUIRED';
    end if;

    if v_source_reference is null then
        raise exception
            'LOYALTY_REDEMPTION_REFERENCE_REQUIRED';
    end if;

    if v_source_transaction_id is null then
        raise exception
            'LOYALTY_REDEMPTION_TRANSACTION_REQUIRED';
    end if;

    if p_transaction_type <>
       'cash_transfer'::public."TransactionType"
    then
        raise exception
            'LOYALTY_REDEMPTION_TRANSACTION_NOT_ELIGIBLE';
    end if;

    if p_fee_amount is null
       or p_fee_amount <= 0
       or p_fee_amount_usd is null
       or p_fee_amount_usd <= 0
    then
        raise exception
            'INVALID_LOYALTY_REDEMPTION_FEE';
    end if;

    if p_points_to_redeem is null
       or p_points_to_redeem <= 0
       or p_points_per_usd is null
       or p_points_per_usd <= 0
    then
        raise exception
            'INVALID_LOYALTY_REDEMPTION_POINTS';
    end if;

    /* Idempotent replay of the same completed redemption. */
    select ledger_record.*
    into v_ledger
    from public.loyalty_ledger ledger_record
    where ledger_record.user_id = v_user_id
      and ledger_record.source_transaction_id =
          v_source_transaction_id
      and ledger_record.ledger_type =
          'redeem'::public."LoyaltyLedgerType"
    limit 1;

    if found then
        if abs(v_ledger.points_delta) <>
           p_points_to_redeem
           or v_ledger.source_reference is distinct from
              v_source_reference
        then
            raise exception
                'LOYALTY_REDEMPTION_REPLAY_MISMATCH';
        end if;

        return jsonb_build_object(
            'success', true,
            'idempotent_replay', true,
            'ledger_id', v_ledger.id,
            'points_redeemed', abs(v_ledger.points_delta),
            'available_points',
                v_ledger.available_balance_after,
            'tier_points',
                v_ledger.tier_balance_after
        );
    end if;

    /* Serialize all spend operations for this account. */
    select account_record.*
    into v_account
    from public.loyalty_account account_record
    where account_record.user_id = v_user_id
    for update;

    if not found then
        raise exception
            'LOYALTY_ACCOUNT_NOT_FOUND';
    end if;

    if not v_account.is_active then
        raise exception
            'LOYALTY_ACCOUNT_NOT_ACTIVE';
    end if;

    if v_account.available_points < p_points_to_redeem then
        raise exception
            'INSUFFICIENT_LOYALTY_POINTS_REQUIRED_%_AVAILABLE_%',
            p_points_to_redeem,
            v_account.available_points;
    end if;

    update public.loyalty_account
    set
        available_points =
            available_points - p_points_to_redeem,
        last_event_at =
            now()
    where id = v_account.id
    returning * into v_account;

    insert into public.loyalty_ledger (
        loyalty_account_id,
        user_id,
        event_id,
        rule_id,
        ledger_type,
        event_type,
        points_delta,
        available_balance_after,
        tier_points_delta,
        tier_balance_after,
        source_reference,
        source_transaction_id,
        description,
        rule_snapshot,
        metadata
    )
    values (
        v_account.id,
        v_user_id,
        null,
        null,
        'redeem'::public."LoyaltyLedgerType",
        'user_transfer'::public."LoyaltyEventType",
        -p_points_to_redeem,
        v_account.available_points,
        0,
        v_account.tier_points,
        v_source_reference,
        v_source_transaction_id,
        'Transfer fee paid with loyalty points',
        jsonb_build_object(
            'points_per_usd', p_points_per_usd,
            'fee_amount', p_fee_amount,
            'fee_amount_usd', p_fee_amount_usd
        ),
        jsonb_build_object(
            'redemption_type', 'transfer_fee',
            'transaction_type', p_transaction_type,
            'country_code', v_country_code,
            'currency_code', v_currency_code,
            'fee_payment_method', 'points'
        )
    )
    returning * into v_ledger;

    return jsonb_build_object(
        'success', true,
        'idempotent_replay', false,
        'ledger_id', v_ledger.id,
        'points_redeemed', abs(v_ledger.points_delta),
        'available_points', v_account.available_points,
        'tier_points', v_account.tier_points
    );
end;
$function$;


revoke all on function
    public.redeem_loyalty_points_for_transfer_fee(
        text,
        text,
        text,
        public."TransactionType",
        text,
        text,
        numeric,
        numeric,
        bigint,
        bigint
    )
from public, anon, authenticated;

grant execute on function
    public.redeem_loyalty_points_for_transfer_fee(
        text,
        text,
        text,
        public."TransactionType",
        text,
        text,
        numeric,
        numeric,
        bigint,
        bigint
    )
to service_role;


/* =========================================================
 * NON-EARNING TRANSFER ACTIVITY
 *
 * A points-paid transfer earns no new points, but it remains
 * a completed user-transfer activity for badge progression.
 * ========================================================= */

create or replace function public.record_non_earning_transfer_activity(
    p_idempotency_key text,
    p_user_id text,
    p_source_reference text,
    p_source_transaction_id text,
    p_amount numeric,
    p_amount_usd numeric,
    p_country_code text,
    p_currency_code text,
    p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
    v_idempotency_key text;
    v_user_id text;
    v_source_reference text;
    v_source_transaction_id text;
    v_country_code text;
    v_currency_code text;
    v_metadata jsonb;
    v_event public.gamification_event%rowtype;
begin
    if coalesce(auth.role(), '') <> 'service_role' then
        raise exception using
            errcode = '42501',
            message = 'SERVICE_ROLE_REQUIRED';
    end if;

    v_idempotency_key :=
        nullif(btrim(p_idempotency_key), '');

    v_user_id :=
        nullif(btrim(p_user_id), '');

    v_source_reference :=
        nullif(btrim(p_source_reference), '');

    v_source_transaction_id :=
        nullif(btrim(p_source_transaction_id), '');

    v_country_code :=
        lower(nullif(btrim(p_country_code), ''));

    v_currency_code :=
        lower(nullif(btrim(p_currency_code), ''));

    v_metadata :=
        coalesce(p_metadata, '{}'::jsonb);

    if v_idempotency_key is null
       or v_user_id is null
       or v_source_reference is null
       or v_source_transaction_id is null
    then
        raise exception
            'NON_EARNING_TRANSFER_ACTIVITY_DATA_REQUIRED';
    end if;

    if p_amount is null
       or p_amount <= 0
       or p_amount_usd is null
       or p_amount_usd <= 0
    then
        raise exception
            'INVALID_NON_EARNING_TRANSFER_AMOUNT';
    end if;

    if jsonb_typeof(v_metadata) <> 'object' then
        raise exception
            'INVALID_GAMIFICATION_METADATA';
    end if;

    insert into public.gamification_event (
        idempotency_key,
        event_type,
        status,
        user_id,
        source_reference,
        source_transaction_id,
        transaction_type,
        amount,
        amount_usd,
        country_code,
        currency_code,
        metadata,
        attempt_count,
        claimed_at
    )
    values (
        v_idempotency_key,
        'user_transfer'::public."LoyaltyEventType",
        'pending'::public."GamificationEventStatus",
        v_user_id,
        v_source_reference,
        v_source_transaction_id,
        'cash_transfer'::public."TransactionType",
        p_amount,
        p_amount_usd,
        v_country_code,
        v_currency_code,
        v_metadata || jsonb_build_object(
            'non_earning_activity', true,
            'points_awarded', 0,
            'reason', 'fee_paid_with_points'
        ),
        1,
        now()
    )
    on conflict (idempotency_key)
    do nothing
    returning * into v_event;

    if not found then
        select event_record.*
        into v_event
        from public.gamification_event event_record
        where event_record.idempotency_key =
              v_idempotency_key;

        if not found
           or v_event.user_id <> v_user_id
           or v_event.event_type <>
              'user_transfer'::public."LoyaltyEventType"
           or v_event.source_reference <>
              v_source_reference
           or v_event.source_transaction_id is distinct from
              v_source_transaction_id
        then
            raise exception
                'GAMIFICATION_IDEMPOTENCY_KEY_PAYLOAD_MISMATCH';
        end if;

        return jsonb_build_object(
            'success', true,
            'idempotent_replay', true,
            'event_id', v_event.id,
            'event_status', v_event.status,
            'points_awarded', 0
        );
    end if;

    /*
     * The existing badge trigger runs on this status update.
     */
    update public.gamification_event
    set
        status =
            'completed'::public."GamificationEventStatus",
        processed_at =
            now(),
        lease_expires_at =
            null,
        error_message =
            null
    where id = v_event.id
    returning * into v_event;

    return jsonb_build_object(
        'success', true,
        'idempotent_replay', false,
        'event_id', v_event.id,
        'event_status', v_event.status,
        'points_awarded', 0
    );
end;
$function$;


revoke all on function
    public.record_non_earning_transfer_activity(
        text,
        text,
        text,
        text,
        numeric,
        numeric,
        text,
        text,
        jsonb
    )
from public, anon, authenticated;

grant execute on function
    public.record_non_earning_transfer_activity(
        text,
        text,
        text,
        text,
        numeric,
        numeric,
        text,
        text,
        jsonb
    )
to service_role;


/* =========================================================
 * COMPLETE CASH TRANSFER FUNCTION
 *
 * Drop both the original six-argument signature and this
 * migration's seven-argument signature so the script can be
 * safely rerun without PostgREST overload ambiguity.
 * ========================================================= */

drop function if exists public.cash_transfer(
    text,
    jsonb,
    public."TransactionType",
    text,
    text,
    text
);

drop function if exists public.cash_transfer(
    text,
    jsonb,
    public."TransactionType",
    text,
    text,
    text,
    text
);


create function public.cash_transfer(
    p_sender_id text,
    p_transaction jsonb,
    p_transaction_type public."TransactionType",
    p_country_code text,
    p_transaction_state_id text,
    p_ip_address text default null,
    p_fee_payment_method text default 'cash'
)
returns table (
    success boolean,
    reference text,
    financial_transaction_id text,
    amount text,
    amount_usd text,
    original_fee text,
    cash_fee text,
    cash_charges text,
    fee_payment_method text,
    points_redeemed bigint,
    redemption_ledger_id text,
    currency text,
    receiver_notification_id text,
    device_tokens text[],
    push_title text,
    push_body text,
    push_reference text
)
language plpgsql
security definer
set search_path to ''
as $function$
declare
    v_decimals numeric := 100;

    v_amount numeric;
    v_amount_usd numeric(20, 6);
    v_principal numeric;
    v_currency text;
    v_reference text;
    v_receiver_identifier text;
    v_fee_payment_method text;
    v_rate_to_usd numeric;

    v_fiscal_year integer;
    v_period integer;

    v_receiver public.users%rowtype;
    v_sender public.users%rowtype;
    v_treasury public.users%rowtype;
    v_transaction_state public.transaction_state%rowtype;

    v_mappings
        public.transaction_gl_mapping[];

    v_components
        public.posting_component[];

    v_component_totals
        public.component_totals;

    v_principal_amount numeric;
    v_others_amount numeric;
    v_original_fee numeric := 0;
    v_cash_fee numeric := 0;
    v_fee_amount_usd numeric(20, 6) := 0;

    v_redemption_config
        public.loyalty_redemption_config%rowtype;

    v_points_redeemed bigint := 0;
    v_redemption_result jsonb;
    v_redemption_ledger_id text;

    v_sender_notification
        public.notification_message;

    v_receiver_notification
        public.notification_message;

    v_device_tokens text[] :=
        array[]::text[];

    v_document_prefix text;
    v_document_number text;

    v_financial_transaction_id bigint;
    v_receiver_notification_id text;

    v_stage text := 'initialization';
    v_error_state text;
    v_error_message text;
    v_error_detail text;
    v_error_hint text;
    v_error_context text;
begin
    v_stage := 'validate service role';

    if coalesce(auth.role(), '') <> 'service_role' then
        raise exception using
            errcode = '42501',
            message = 'SERVICE_ROLE_REQUIRED';
    end if;

    v_stage := 'validate transaction type';

    if p_transaction_type <>
       'cash_transfer'::public."TransactionType"
    then
        raise exception
            'INVALID_CASH_TRANSFER_TRANSACTION_TYPE_%',
            p_transaction_type;
    end if;

    v_fee_payment_method :=
        lower(
            coalesce(
                nullif(btrim(p_fee_payment_method), ''),
                'cash'
            )
        );

    if v_fee_payment_method not in ('cash', 'points') then
        raise exception
            'INVALID_FEE_PAYMENT_METHOD';
    end if;

    /* Validate, lock, and bind the processing state. */
    v_stage :=
        'validate and lock transaction state';

    select transaction_state_record.*
    into v_transaction_state
    from public.transaction_state transaction_state_record
    where transaction_state_record.id =
          p_transaction_state_id
      and transaction_state_record.created_by =
          p_sender_id
      and transaction_state_record.transaction_type =
          p_transaction_type
      and transaction_state_record.country_code =
          p_country_code
      and transaction_state_record.status =
          'processing'::public."TransactionStatus"
    limit 1
    for update;

    if not found then
        raise exception
            'INVALID_TRANSACTION_STATE';
    end if;

    if v_transaction_state.transaction_data
       is distinct from p_transaction
    then
        raise exception
            'TRANSACTION_STATE_DATA_MISMATCH';
    end if;

    /* Parse transaction data. */
    v_stage := 'parse transaction amount';

    v_amount :=
        (p_transaction ->> 'a')::numeric /
        v_decimals;

    if v_amount <= 0 then
        raise exception
            'INVALID_AMOUNT';
    end if;

    v_principal := v_amount;

    v_stage := 'parse transaction currency';

    v_currency :=
        lower(
            nullif(
                btrim(p_transaction ->> 'c'),
                ''
            )
        );

    if v_currency is null then
        raise exception
            'CURRENCY_MISSING';
    end if;

    v_stage := 'parse transaction reference';

    v_reference :=
        nullif(
            btrim(p_transaction ->> 'r'),
            ''
        );

    if v_reference is null then
        raise exception
            'REFERENCE_MISSING';
    end if;

    v_stage := 'parse receiver identifier';

    v_receiver_identifier :=
        nullif(
            btrim(p_transaction ->> 's'),
            ''
        );

    if v_receiver_identifier is null then
        raise exception
            'RECEIVER_IDENTIFIER_MISSING';
    end if;

    /* Capture the principal USD value and transaction-time rate. */
    v_stage := 'calculate transfer USD amount';

    if v_currency = 'usd' then
        v_rate_to_usd := 1;
        v_amount_usd := round(v_amount, 6);
    else
        select rate_record.rate_to_usd
        into v_rate_to_usd
        from public.current_rates rate_record
        where lower(btrim(rate_record.code)) =
              v_currency
        limit 1;

        if not found
           or v_rate_to_usd is null
           or v_rate_to_usd <= 0
        then
            raise exception
                'CURRENT_RATE_NOT_FOUND_%',
                upper(v_currency);
        end if;

        if v_currency = 'gold' then
            v_amount_usd :=
                round(v_amount * v_rate_to_usd, 6);
        else
            v_amount_usd :=
                round(v_amount / v_rate_to_usd, 6);
        end if;
    end if;

    if v_amount_usd <= 0 then
        raise exception
            'INVALID_TRANSFER_USD_AMOUNT';
    end if;

    /* Fetch GL mappings and build original cash components. */
    v_stage := 'fetch GL mappings';

    select array_agg(mapping_row)
    into v_mappings
    from public.fetch_gl_mappings(
        p_transaction_type
    ) as mapping_row;

    if v_mappings is null
       or cardinality(v_mappings) = 0
    then
        raise exception
            'GL_MAPPINGS_NOT_FOUND';
    end if;

    v_stage := 'build posting components';

    v_components :=
        public.build_posting_components(
            p_transaction_type,
            v_principal,
            v_mappings,
            p_country_code,
            v_currency,
            false
        );

    if v_components is null
       or cardinality(v_components) = 0
    then
        raise exception
            'POSTING_COMPONENTS_NOT_FOUND';
    end if;

    /* Extract the original transfer fee before any redemption. */
    v_stage := 'extract transfer fee';

    select coalesce(
        component.credit_amount,
        0
    )
    into v_original_fee
    from unnest(v_components) as component(
        component_type,
        debit_amount,
        credit_amount
    )
    where component.component_type =
          'transfer_fee'::public."ComponentType"
    limit 1;

    v_original_fee :=
        coalesce(v_original_fee, 0);

    if v_original_fee <= 0 then
        raise exception
            'INVALID_FEE_AMOUNT';
    end if;

    if v_currency = 'usd' then
        v_fee_amount_usd :=
            round(v_original_fee, 6);
    elsif v_currency = 'gold' then
        v_fee_amount_usd :=
            round(v_original_fee * v_rate_to_usd, 6);
    else
        v_fee_amount_usd :=
            round(v_original_fee / v_rate_to_usd, 6);
    end if;

    if v_fee_amount_usd <= 0 then
        raise exception
            'INVALID_TRANSFER_FEE_USD_AMOUNT';
    end if;

    /*
     * Resolve and apply all-or-nothing transfer-fee redemption.
     * Other components, including government tax, remain in cash.
     */
    if v_fee_payment_method = 'points' then
        v_stage := 'resolve loyalty redemption config';

        select config_record.*
        into v_redemption_config
        from public.loyalty_redemption_config config_record
        where config_record.transaction_type =
              p_transaction_type
          and config_record.is_active = true
          and (
              config_record.country_code is null
              or config_record.country_code =
                 lower(p_country_code)
          )
          and (
              config_record.currency_code is null
              or config_record.currency_code =
                 v_currency
          )
          and (
              config_record.valid_from is null
              or config_record.valid_from <= now()
          )
          and (
              config_record.valid_until is null
              or config_record.valid_until > now()
          )
        order by
            case
                when config_record.country_code is not null
                    then 0
                else 1
            end,
            case
                when config_record.currency_code is not null
                    then 0
                else 1
            end,
            config_record.priority,
            config_record.id
        limit 1;

        if not found then
            raise exception
                'TRANSFER_FEE_POINT_REDEMPTION_NOT_AVAILABLE';
        end if;

        v_points_redeemed :=
            ceil(
                v_fee_amount_usd *
                v_redemption_config.points_per_usd
            )::bigint;

        if v_points_redeemed <= 0 then
            raise exception
                'INVALID_TRANSFER_FEE_POINTS';
        end if;

        /*
         * Remove the transfer-fee credit and reduce the gross
         * principal debit by the same amount. The remaining
         * components stay unchanged and payable in cash.
         */
        v_stage := 'apply loyalty fee discount to components';

        select array_agg(
            row(
                component.component_type,
                case
                    when component.component_type =
                         'principal'::public."ComponentType"
                    then component.debit_amount -
                         v_original_fee
                    else component.debit_amount
                end,
                component.credit_amount
            )::public.posting_component
            order by component.position
        )
        into v_components
        from unnest(v_components)
            with ordinality as component(
                component_type,
                debit_amount,
                credit_amount,
                position
            )
        where component.component_type <>
              'transfer_fee'::public."ComponentType";

        v_components :=
            public.validate_components(v_components);

        v_cash_fee := 0;
    else
        v_cash_fee := v_original_fee;
    end if;

    /* Extract final cash totals after the fee choice. */
    v_stage := 'extract final component totals';

    v_component_totals :=
        public.extract_component_totals(
            v_components,
            false
        );

    v_principal_amount :=
        v_component_totals.principal_amount;

    v_others_amount :=
        v_component_totals.others_amount;

    if v_principal_amount < v_amount then
        raise exception
            'INVALID_FINAL_TRANSFER_DEBIT';
    end if;

    /* Fetch fiscal period and participants. */
    v_stage := 'fetch fiscal period';

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

    v_stage := 'fetch receiver';

    v_receiver :=
        public.fetch_user_by_email_or_phone(
            v_receiver_identifier
        );

    v_stage := 'fetch sender';

    v_sender :=
        public.fetch_user_by_id(
            p_sender_id
        );

    v_stage := 'fetch country treasury';

    v_treasury :=
        public.fetch_country_treasury(
            p_country_code
        );

    v_stage := 'validate receiver status';

    if v_receiver.status <>
       'active'::public."UserStatus"
    then
        raise exception
            'RECEIVER_NOT_ACTIVE';
    end if;

    v_stage := 'validate sender status';

    if v_sender.status <>
       'active'::public."UserStatus"
    then
        raise exception
            'SENDER_NOT_ACTIVE';
    end if;

    if v_sender.id = v_receiver.id
       or v_sender.country_code is distinct from
          v_receiver.country_code
       or v_sender.country_code is distinct from
          p_country_code
    then
        raise exception
            'OPERATION_NOT_ALLOWED';
    end if;

    /* Build notifications. */
    v_stage := 'create sender notification';

    v_sender_notification :=
        public.create_notification_message(
            p_country_code,
            p_transaction_type,
            'sender'::public."NotificationAudience",
            v_principal_amount,
            upper(v_currency),
            v_reference || '-01',
            0,
            coalesce(
                v_sender.email,
                v_sender.phone,
                v_sender.id
            ),
            coalesce(
                v_receiver.email,
                v_receiver.phone,
                v_receiver.id
            )
        );

    v_stage := 'create receiver notification';

    v_receiver_notification :=
        public.create_notification_message(
            p_country_code,
            p_transaction_type,
            'receiver'::public."NotificationAudience",
            v_amount,
            upper(v_currency),
            v_reference || '-02',
            0,
            coalesce(
                v_sender.email,
                v_sender.phone,
                v_sender.id
            ),
            coalesce(
                v_receiver.email,
                v_receiver.phone,
                v_receiver.id
            )
        );

    v_stage := 'fetch receiver device tokens';

    v_device_tokens :=
        coalesce(
            public.fetch_device_tokens(
                p_country_code,
                v_receiver.id
            ),
            array[]::text[]
        );

    /* Generate document number and create the financial header. */
    v_stage := 'fetch document number prefix';

    v_document_prefix :=
        public.fetch_transaction_doc_num_prefix(
            p_transaction_type
        );

    v_stage := 'generate document number';

    v_document_number :=
        public.generate_document_number(
            v_document_prefix,
            v_fiscal_year,
            v_period,
            p_country_code
        );

    v_stage := 'insert financial transaction';

    insert into public.financial_transaction (
        document_number,
        fiscal_year,
        period,
        transaction_type,
        description,
        created_by,
        gross_amount,
        currency_code,
        reference,
        country_code
    )
    values (
        v_document_number,
        v_fiscal_year,
        v_period,
        p_transaction_type,
        'User transfer from ' ||
        coalesce(
            v_sender.email,
            v_sender.phone,
            v_sender.id
        ) ||
        ' to ' ||
        coalesce(
            v_receiver.email,
            v_receiver.phone,
            v_receiver.id
        ),
        p_sender_id,
        v_principal_amount,
        v_currency,
        v_reference,
        p_country_code
    )
    returning id
    into v_financial_transaction_id;

    /*
     * Redeem after obtaining the financial transaction ID,
     * but before any posting completes. A later failure rolls
     * back this ledger row and restores the account balance.
     */
    if v_fee_payment_method = 'points' then
        v_stage := 'redeem loyalty points';

        v_redemption_result :=
            public.redeem_loyalty_points_for_transfer_fee(
                p_sender_id,
                v_reference,
                v_financial_transaction_id::text,
                p_transaction_type,
                p_country_code,
                v_currency,
                v_original_fee,
                v_fee_amount_usd,
                v_points_redeemed,
                v_redemption_config.points_per_usd
            );

        v_redemption_ledger_id :=
            v_redemption_result ->> 'ledger_id';

        if v_redemption_ledger_id is null then
            raise exception
                'LOYALTY_REDEMPTION_LEDGER_NOT_CREATED';
        end if;
    end if;

    /* Post financial entries. */
    v_stage := 'post financial entries';

    perform *
    from public.post_financial_entries(
        p_document_number =>
            v_document_number,
        p_country_code =>
            p_country_code,
        p_transaction_id =>
            v_financial_transaction_id,
        p_transaction_type =>
            p_transaction_type,
        p_created_by =>
            p_sender_id,
        p_components =>
            v_components,
        p_mappings =>
            v_mappings,
        p_currency_code =>
            v_currency,
        p_fiscal_year =>
            v_fiscal_year,
        p_period =>
            v_period,
        p_reference =>
            v_reference,
        p_deposit_type =>
            null
    );

    /* Post wallet entries and notification rows. */
    v_stage := 'post wallet entries';

    select result.receiver_notification_id
    into v_receiver_notification_id
    from public.post_wallet_entries(
        p_fiscal_year =>
            v_fiscal_year,
        p_period =>
            v_period,
        p_document_number =>
            v_document_number,
        p_reference =>
            v_reference,
        p_receiver_id =>
            v_receiver.id,
        p_sender_id =>
            p_sender_id,
        p_transaction_type =>
            p_transaction_type,
        p_credit_amount =>
            v_amount,
        p_debit_amount =>
            v_principal_amount,
        p_sender_wallet_owner =>
            'customer'::public."WalletOwnerType",
        p_receiver_wallet_owner =>
            'customer'::public."WalletOwnerType",
        p_currency_code =>
            v_currency,
        p_country_code =>
            p_country_code,
        p_audit_action_type =>
            'cash_transferred'::public."AuditActionType",
        p_treasury_id =>
            v_treasury.id,
        p_fee_amount =>
            v_cash_fee,
        p_ip_address =>
            p_ip_address,
        p_receiver_notification =>
            v_receiver_notification,
        p_sender_notification =>
            v_sender_notification
    ) as result;

    /* Mark transaction as successful. */
    v_stage := 'update transaction state';

    update public.transaction_state
    set
        user_id =
            v_receiver.id,
        status =
            'success'::public."TransactionStatus",
        message =
            null,
        updated_at =
            now()
    where id =
          p_transaction_state_id
      and created_by =
          p_sender_id
      and transaction_type =
          p_transaction_type
      and status =
          'processing'::public."TransactionStatus";

    if not found then
        raise exception
            'TRANSACTION_STATE_UPDATE_FAILED';
    end if;

    /* Return posting, redemption, and notification data. */
    v_stage := 'return cash transfer result';

    return query
    select
        true,
        v_reference,
        v_financial_transaction_id::text,
        v_amount::text,
        v_amount_usd::text,
        v_original_fee::text,
        v_cash_fee::text,
        v_others_amount::text,
        v_fee_payment_method,
        v_points_redeemed,
        v_redemption_ledger_id,
        v_currency,
        v_receiver_notification_id,
        v_device_tokens,
        v_receiver_notification.title,
        v_receiver_notification.body,
        v_receiver_notification.payload
            ->> 'reference';
exception
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
                    'CASH_TRANSFER_FAILED at [%s]: %s',
                    v_stage,
                    v_error_message
                ),
            detail =
                coalesce(
                    nullif(
                        concat_ws(
                            E'\n',
                            nullif(v_error_detail, ''),
                            nullif(v_error_context, '')
                        ),
                        ''
                    ),
                    'No additional PostgreSQL context'
                ),
            hint =
                coalesce(
                    nullif(v_error_hint, ''),
                    'Check the cash-transfer stage reported in the error'
                );
end;
$function$;


revoke all on function public.cash_transfer(
    text,
    jsonb,
    public."TransactionType",
    text,
    text,
    text,
    text
)
from public, anon, authenticated;

grant execute on function public.cash_transfer(
    text,
    jsonb,
    public."TransactionType",
    text,
    text,
    text,
    text
)
to service_role;


notify pgrst, 'reload schema';

commit;
