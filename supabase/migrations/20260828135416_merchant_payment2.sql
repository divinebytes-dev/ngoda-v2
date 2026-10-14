/*
 * Ngoda Merchant Payment - Optional Support Contribution
 *
 * Run after 01_add_fee_contribution_loyalty_event.sql has committed.
 *
 * The existing five-argument prepare function and two-argument state
 * function remain intact. The Edge Function uses the contribution-aware
 * overloads created here.
 */


/* =========================================================
 * DURABLE CUSTOMER CHOICE
 * ========================================================= */

alter table public.transaction_state
    add column if not exists payment_fee_contribution boolean;

update public.transaction_state
set payment_fee_contribution = false
where payment_fee_contribution is null;

alter table public.transaction_state
    alter column payment_fee_contribution set default false,
    alter column payment_fee_contribution set not null;


/* =========================================================
 * CONFIGURABLE CONTRIBUTION BONUS
 * ========================================================= */

insert into public.loyalty_rule (
    event_type,
    rule_code,
    rule_name,
    calculation_type,
    fixed_points,
    points_per_usd,
    min_amount_usd,
    max_amount_usd,
    min_points_per_event,
    max_points_per_event,
    daily_cap_points,
    monthly_cap_points,
    country_code,
    currency_code,
    multiplier,
    priority,
    condition_config,
    is_active
)
values (
    'merchant_payment_fee_contribution'::public."LoyaltyEventType",
    'merchant_payment_fee_contribution_standard',
    'Optional merchant-payment support contribution',
    'fixed'::public."LoyaltyRuleCalculationType",
    5,
    null,
    null,
    null,
    5,
    5,
    100,
    500,
    null,
    null,
    1,
    100,
    jsonb_build_object(
        'requires_payment_fee_contribution', true,
        'beneficiary', 'payer'
    ),
    true
)
on conflict (rule_code) do update
set
    rule_name = excluded.rule_name,
    calculation_type = excluded.calculation_type,
    condition_config = excluded.condition_config,
    updated_at = now();

/*
 * To change the bonus later, update fixed_points, min_points_per_event and
 * max_points_per_event together. Example for a two-point bonus:
 *
 * update public.loyalty_rule
 * set fixed_points = 2,
 *     min_points_per_event = 2,
 *     max_points_per_event = 2,
 *     updated_at = now()
 * where rule_code = 'merchant_payment_fee_contribution_standard';
 */


/* =========================================================
 * CREATE PROCESSING STATE WITH THE CUSTOMER'S CHOICE
 * ========================================================= */

create or replace function public.create_my_merchant_payment_state(
    p_transaction jsonb,
    p_approval jsonb,
    p_payment_fee_contribution boolean
)
returns text
language plpgsql
security definer
set search_path to ''
as $$
declare
    v_transaction_id text;
begin
    if p_payment_fee_contribution is null then
        raise exception 'PAYMENT_FEE_CONTRIBUTION_REQUIRED';
    end if;

    /*
     * The existing function performs authentication, role, participant,
     * signature-payload and replay validation before inserting the state.
     */
    v_transaction_id :=
        public.create_my_merchant_payment_state(
            p_transaction,
            p_approval
        );

    update public.transaction_state state_record
    set
        payment_fee_contribution = p_payment_fee_contribution,
        updated_at = now()
    where state_record.id::text = v_transaction_id
      and state_record.created_by = auth.uid()::text
      and state_record.transaction_type =
          'merchant_payment'::public."TransactionType"
      and state_record.status =
          'processing'::public."TransactionStatus";

    if not found then
        raise exception 'TRANSACTION_STATE_CONTRIBUTION_UPDATE_FAILED';
    end if;

    return v_transaction_id;
end;
$$;


/* =========================================================
 * PREPARE TRUSTED POSTING VALUES
 * ========================================================= */

create or replace function public.prepare_merchant_payment(
    p_payer_id text,
    p_transaction jsonb,
    p_approval jsonb,
    p_country_code text,
    p_transaction_state_id text,
    p_payment_fee_contribution boolean
)
returns table(
    payer_id text,
    payer_wallet_address text,
    merchant_id text,
    merchant_wallet_address text,
    treasury_id text,
    country_code text,
    fiscal_year integer,
    period integer,
    document_prefix text,
    currency_code text,
    amount text,
    payer_debit_amount text,
    merchant_credit_amount text,
    other_amount text,
    payment_fee text,
    commission_rate text,
    commission_amount text,
    mappings public.transaction_gl_mapping[],
    components public.posting_component[]
)
language plpgsql
security definer
set search_path to ''
as $$
declare
    v_base record;
    v_state_contribution boolean;
    v_mappings public.transaction_gl_mapping[];
    v_components public.posting_component[];
    v_component_totals public.component_totals;
    v_payer_debit_amount numeric;
    v_other_amount numeric;
    v_payment_fee numeric;
begin
    if coalesce(auth.role(), '') <> 'service_role' then
        raise exception using
            errcode = '42501',
            message = 'SERVICE_ROLE_REQUIRED';
    end if;

    if p_payment_fee_contribution is null then
        raise exception 'PAYMENT_FEE_CONTRIBUTION_REQUIRED';
    end if;

    select state_record.payment_fee_contribution
    into v_state_contribution
    from public.transaction_state state_record
    where state_record.id::text = p_transaction_state_id
      and state_record.created_by = p_payer_id
      and state_record.transaction_type =
          'merchant_payment'::public."TransactionType"
      and state_record.status =
          'processing'::public."TransactionStatus"
    for update;

    if not found then
        raise exception 'INVALID_TRANSACTION_STATE';
    end if;

    if v_state_contribution is distinct from p_payment_fee_contribution then
        raise exception 'PAYMENT_FEE_CONTRIBUTION_MISMATCH';
    end if;

    /*
     * Reuse the established five-argument implementation for all trusted
     * participant, state, amount, fiscal-period and configuration checks.
     */
    select preparation_record.*
    into v_base
    from public.prepare_merchant_payment(
        p_payer_id,
        p_transaction,
        p_approval,
        p_country_code,
        p_transaction_state_id
    ) as preparation_record;

    if not found then
        raise exception 'MERCHANT_PAYMENT_PREPARATION_NOT_FOUND';
    end if;

    v_mappings := v_base.mappings;
    v_components := v_base.components;
    v_payment_fee := coalesce(v_base.payment_fee::numeric, 0);

    if not p_payment_fee_contribution then
        /*
         * Merchant payment uses gross principal mode. The principal debit
         * therefore already includes all configured charges. Removing the
         * payment-fee credit also requires reducing the principal debit by
         * exactly that fee. Mandatory taxes and future non-fee components
         * remain untouched.
         */
        select array_agg(
            mapping_record
            order by mapping_record.component_type
        )
        into v_mappings
        from unnest(v_base.mappings) as mapping_record
        where mapping_record.component_type <>
              'payment_fee'::public."ComponentType";

        select array_agg(
            row(
                component_record.component_type,
                case
                    when component_record.component_type =
                         'principal'::public."ComponentType"
                    then component_record.debit_amount - v_payment_fee
                    else component_record.debit_amount
                end,
                component_record.credit_amount
            )::public.posting_component
        )
        into v_components
        from unnest(v_base.components) as component_record
        where component_record.component_type <>
              'payment_fee'::public."ComponentType";

        if v_components is null
           or cardinality(v_components) = 0
        then
            raise exception 'MERCHANT_PAYMENT_COMPONENTS_NOT_FOUND';
        end if;

        if exists (
            select 1
            from unnest(v_components) as component_record
            where component_record.debit_amount < 0
               or component_record.credit_amount < 0
        ) then
            raise exception 'INVALID_MERCHANT_PAYMENT_COMPONENT_AMOUNT';
        end if;

        v_components := public.validate_components(v_components);

        v_component_totals :=
            public.extract_component_totals(
                v_components,
                false
            );

        v_payer_debit_amount :=
            coalesce(v_component_totals.principal_amount, 0);

        v_other_amount :=
            coalesce(v_component_totals.others_amount, 0);

        if v_payer_debit_amount <= 0 then
            raise exception 'INVALID_PAYER_DEBIT_AMOUNT';
        end if;

        return query
        select
            v_base.payer_id::text,
            v_base.payer_wallet_address::text,
            v_base.merchant_id::text,
            v_base.merchant_wallet_address::text,
            v_base.treasury_id::text,
            v_base.country_code::text,
            v_base.fiscal_year::integer,
            v_base.period::integer,
            v_base.document_prefix::text,
            v_base.currency_code::text,
            v_base.amount::text,
            v_payer_debit_amount::text,
            v_base.merchant_credit_amount::text,
            v_other_amount::text,
            '0'::text,
            v_base.commission_rate::text,
            '0'::text,
            v_mappings,
            v_components;

        return;
    end if;

    return query
    select
        v_base.payer_id::text,
        v_base.payer_wallet_address::text,
        v_base.merchant_id::text,
        v_base.merchant_wallet_address::text,
        v_base.treasury_id::text,
        v_base.country_code::text,
        v_base.fiscal_year::integer,
        v_base.period::integer,
        v_base.document_prefix::text,
        v_base.currency_code::text,
        v_base.amount::text,
        v_base.payer_debit_amount::text,
        v_base.merchant_credit_amount::text,
        v_base.other_amount::text,
        v_base.payment_fee::text,
        v_base.commission_rate::text,
        v_base.commission_amount::text,
        v_mappings,
        v_components;
end;
$$;


/* =========================================================
 * COMPLETE PAYMENT ATOMICALLY
 * ========================================================= */

create or replace function public.complete_merchant_payment(
    p_payer_id text,
    p_transaction jsonb,
    p_approval jsonb,
    p_country_code text,
    p_transaction_state_id text,
    p_payment_fee_contribution boolean,
    p_ip_address text default null
)
returns table(
    success boolean,
    document_number text,
    financial_transaction_id text,
    amount text,
    amount_usd text,
    payment_fee text,
    payment_fee_usd text,
    payment_fee_contribution boolean,
    payer_debit_amount text,
    currency_code text,
    receiver_notification_id text,
    device_tokens text[],
    push_title text,
    push_body text,
    push_reference text
)
language plpgsql
security definer
set search_path to ''
as $$
declare
    v_preparation record;
    v_payer public.users%rowtype;
    v_merchant public.users%rowtype;
    v_sender_notification public.notification_message;
    v_receiver_notification public.notification_message;
    v_device_tokens text[] := array[]::text[];
    v_document_number text;
    v_financial_transaction_id bigint;
    v_receiver_notification_id text;
    v_reference text;
    v_rate_to_usd numeric;
    v_amount_usd numeric(20, 6);
    v_payment_fee_usd numeric(20, 6) := 0;
    v_contributed boolean := false;
    v_stage text := 'initialization';
    v_error_state text;
    v_error_message text;
    v_error_detail text;
    v_error_hint text;
    v_error_context text;
begin
    if coalesce(auth.role(), '') <> 'service_role' then
        raise exception using
            errcode = '42501',
            message = 'SERVICE_ROLE_REQUIRED';
    end if;

    if p_payment_fee_contribution is null then
        raise exception 'PAYMENT_FEE_CONTRIBUTION_REQUIRED';
    end if;

    v_stage := 'prepare merchant payment';

    select preparation_record.*
    into v_preparation
    from public.prepare_merchant_payment(
        p_payer_id,
        p_transaction,
        p_approval,
        p_country_code,
        p_transaction_state_id,
        p_payment_fee_contribution
    ) as preparation_record;

    if not found then
        raise exception 'MERCHANT_PAYMENT_PREPARATION_NOT_FOUND';
    end if;

    v_reference := nullif(btrim(p_transaction ->> 'r'), '');

    if v_reference is null then
        raise exception 'REFERENCE_IS_REQUIRED';
    end if;

    v_contributed :=
        p_payment_fee_contribution
        and v_preparation.payment_fee::numeric > 0;

    /* Capture the qualifying USD values in the posting transaction. */
    v_stage := 'calculate loyalty USD values';

    if lower(v_preparation.currency_code) = 'usd' then
        v_amount_usd := round(v_preparation.amount::numeric, 6);
        v_payment_fee_usd :=
            round(v_preparation.payment_fee::numeric, 6);
    else
        select rate_record.rate_to_usd
        into v_rate_to_usd
        from public.current_rates rate_record
        where lower(btrim(rate_record.code)) =
              lower(v_preparation.currency_code)
        limit 1;

        if not found
           or v_rate_to_usd is null
           or v_rate_to_usd <= 0
        then
            raise exception
                'CURRENT_RATE_NOT_FOUND_%',
                upper(v_preparation.currency_code);
        end if;

        /* Merchant payments support fiat currencies only. */
        v_amount_usd := round(
            v_preparation.amount::numeric / v_rate_to_usd,
            6
        );

        v_payment_fee_usd := round(
            v_preparation.payment_fee::numeric / v_rate_to_usd,
            6
        );
    end if;

    if v_amount_usd <= 0 then
        raise exception 'INVALID_MERCHANT_PAYMENT_USD_AMOUNT';
    end if;

    v_stage := 'fetch payment users';
    v_payer := public.fetch_user_by_id(v_preparation.payer_id);
    v_merchant := public.fetch_user_by_id(v_preparation.merchant_id);

    if v_payer.id is null then
        raise exception 'PAYER_NOT_FOUND';
    end if;

    if v_merchant.id is null then
        raise exception 'MERCHANT_NOT_FOUND';
    end if;

    v_stage := 'create payer notification';
    v_sender_notification := public.create_notification_message(
        v_preparation.country_code,
        'merchant_payment'::public."TransactionType",
        'sender'::public."NotificationAudience",
        v_preparation.payer_debit_amount::numeric,
        upper(v_preparation.currency_code),
        v_reference || '-01',
        0,
        'Ngoda',
        coalesce(v_merchant.email, v_merchant.phone, v_merchant.id)
    );

    v_stage := 'create merchant notification';
    v_receiver_notification := public.create_notification_message(
        v_preparation.country_code,
        'merchant_payment'::public."TransactionType",
        'receiver'::public."NotificationAudience",
        v_preparation.merchant_credit_amount::numeric,
        upper(v_preparation.currency_code),
        v_reference || '-02',
        0,
        coalesce(v_payer.email, v_payer.phone, v_payer.id),
        coalesce(v_merchant.email, v_merchant.phone, v_merchant.id)
    );

    v_stage := 'fetch merchant device tokens';
    v_device_tokens := coalesce(
        public.fetch_device_tokens(
            v_preparation.country_code,
            v_merchant.id
        ),
        array[]::text[]
    );

    v_stage := 'generate document number';
    v_document_number := public.generate_document_number(
        v_preparation.document_prefix,
        v_preparation.fiscal_year,
        v_preparation.period,
        v_preparation.country_code
    );

    if nullif(btrim(v_document_number), '') is null then
        raise exception 'DOCUMENT_NUMBER_GENERATION_FAILED';
    end if;

    v_stage := 'insert financial transaction';
    insert into public.financial_transaction (
        fiscal_year,
        period,
        document_number,
        transaction_type,
        description,
        created_by,
        gross_amount,
        currency_code,
        reference,
        country_code
    )
    values (
        v_preparation.fiscal_year,
        v_preparation.period,
        v_document_number,
        'merchant_payment'::public."TransactionType",
        'User ' ||
        coalesce(v_payer.email, v_payer.phone, v_payer.id) ||
        ' pays merchant ' ||
        coalesce(v_merchant.email, v_merchant.phone, v_merchant.id),
        v_payer.id,
        v_preparation.payer_debit_amount::numeric,
        v_preparation.currency_code,
        v_reference,
        v_preparation.country_code
    )
    returning id into v_financial_transaction_id;

    v_stage := 'post financial entries';
    perform *
    from public.post_financial_entries(
        p_document_number => v_document_number,
        p_country_code => v_preparation.country_code,
        p_transaction_id => v_financial_transaction_id,
        p_transaction_type =>
            'merchant_payment'::public."TransactionType",
        p_created_by => v_payer.id,
        p_components => v_preparation.components,
        p_mappings => v_preparation.mappings,
        p_currency_code => v_preparation.currency_code,
        p_fiscal_year => v_preparation.fiscal_year,
        p_period => v_preparation.period,
        p_reference => v_reference,
        p_deposit_type => null
    );

    v_stage := 'post wallet entries';
    select wallet_result.receiver_notification_id
    into v_receiver_notification_id
    from public.post_wallet_entries(
        p_fiscal_year => v_preparation.fiscal_year,
        p_period => v_preparation.period,
        p_document_number => v_document_number,
        p_reference => v_reference,
        p_receiver_id => v_merchant.id,
        p_sender_id => v_payer.id,
        p_transaction_type =>
            'merchant_payment'::public."TransactionType",
        p_credit_amount =>
            v_preparation.merchant_credit_amount::numeric,
        p_debit_amount =>
            v_preparation.payer_debit_amount::numeric,
        p_sender_wallet_owner =>
            'customer'::public."WalletOwnerType",
        p_receiver_wallet_owner =>
            'merchant'::public."WalletOwnerType",
        p_currency_code => v_preparation.currency_code,
        p_country_code => v_preparation.country_code,
        p_audit_action_type =>
            'merchant_payment'::public."AuditActionType",
        p_treasury_id => v_preparation.treasury_id,
        p_fee_amount => v_preparation.payment_fee::numeric,
        p_ip_address => p_ip_address,
        p_receiver_notification => v_receiver_notification,
        p_sender_notification => v_sender_notification
    ) as wallet_result;

    v_stage := 'complete transaction state';
    update public.transaction_state state_record
    set
        user_id = v_merchant.id,
        status = 'success'::public."TransactionStatus",
        message = null,
        updated_at = now()
    where state_record.id::text = p_transaction_state_id
      and state_record.created_by = p_payer_id
      and state_record.user_id = v_merchant.id
      and state_record.transaction_type =
          'merchant_payment'::public."TransactionType"
      and state_record.status =
          'processing'::public."TransactionStatus"
      and state_record.payment_fee_contribution =
          p_payment_fee_contribution;

    if not found then
        raise exception 'TRANSACTION_STATE_UPDATE_FAILED';
    end if;

    v_stage := 'return merchant payment result';
    return query
    select
        true,
        v_document_number,
        v_financial_transaction_id::text,
        v_preparation.amount::text,
        v_amount_usd::text,
        v_preparation.payment_fee::text,
        v_payment_fee_usd::text,
        v_contributed,
        v_preparation.payer_debit_amount::text,
        v_preparation.currency_code::text,
        v_receiver_notification_id,
        v_device_tokens,
        v_receiver_notification.title,
        v_receiver_notification.body,
        v_receiver_notification.payload ->> 'reference';

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
                'MERCHANT_PAYMENT_FAILED at [%s]: %s',
                v_stage,
                v_error_message
            ),
            detail = coalesce(
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
            hint = coalesce(
                nullif(v_error_hint, ''),
                'Check the Merchant Payment stage reported in the error'
            );
end;
$$;


/* =========================================================
 * FUNCTION PRIVILEGES AND SCHEMA CACHE
 * ========================================================= */

revoke all on function public.create_my_merchant_payment_state(
    jsonb,
    jsonb,
    boolean
) from public, anon;

grant execute on function public.create_my_merchant_payment_state(
    jsonb,
    jsonb,
    boolean
) to authenticated;

revoke all on function public.prepare_merchant_payment(
    text,
    jsonb,
    jsonb,
    text,
    text,
    boolean
) from public, anon, authenticated;

grant execute on function public.prepare_merchant_payment(
    text,
    jsonb,
    jsonb,
    text,
    text,
    boolean
) to service_role;

revoke all on function public.complete_merchant_payment(
    text,
    jsonb,
    jsonb,
    text,
    text,
    boolean,
    text
) from public, anon, authenticated;

grant execute on function public.complete_merchant_payment(
    text,
    jsonb,
    jsonb,
    text,
    text,
    boolean,
    text
) to service_role;

notify pgrst, 'reload schema';