/*
 * Ngoda Gamification - Transactional Points and Tier Engine
 *
 * Run after:
 *   01_core_schema.sql
 *   02_seed_core_configuration.sql
 *
 * Public service contract:
 *   1. award_loyalty_points(...)
 *   2. reverse_loyalty_points(...)
 *
 * Each RPC completes all database work in its own PostgreSQL transaction.
 * A successful response therefore means the event, cap usage, ledger,
 * balances, level history, and Flutter notification are consistent.
 */


/* Notification points must use the same range as the points ledger. */
alter table public.gamification_notification
    alter column points type bigint;


/* =========================================================
 * AWARD POINTS
 * ========================================================= */

create or replace function public.award_loyalty_points(
    p_idempotency_key text,
    p_event_type public."LoyaltyEventType",
    p_user_id text,
    p_source_reference text,
    p_source_transaction_id text default null,
    p_transaction_type public."TransactionType" default null,
    p_amount numeric default null,
    p_amount_usd numeric default null,
    p_country_code text default null,
    p_currency_code text default null,
    p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_idempotency_key text;
    v_user_id text;
    v_source_reference text;
    v_country_code text;
    v_currency_code text;
    v_metadata jsonb;

    v_event public.gamification_event%rowtype;
    v_rule public.loyalty_rule%rowtype;
    v_band public.loyalty_rule_band%rowtype;
    v_account public.loyalty_account%rowtype;
    v_program public.loyalty_program_config%rowtype;
    v_previous_level text;
    v_new_level text;

    v_existing_ledger public.loyalty_ledger%rowtype;
    v_ledger public.loyalty_ledger%rowtype;

    v_raw_points numeric := 0;
    v_calculated_points bigint := 0;
    v_awarded_points bigint := 0;

    v_event_time timestamptz;
    v_daily_start date;
    v_monthly_start date;

    v_program_daily_used bigint := 0;
    v_program_monthly_used bigint := 0;
    v_rule_daily_used bigint := 0;
    v_rule_monthly_used bigint := 0;

    v_program_daily_remaining bigint;
    v_program_monthly_remaining bigint;
    v_rule_daily_remaining bigint;
    v_rule_monthly_remaining bigint;

    v_rule_snapshot jsonb;
    v_result jsonb;
begin
    if coalesce(auth.role(), '') <> 'service_role' then
        raise exception using
            errcode = '42501',
            message = 'SERVICE_ROLE_REQUIRED';
    end if;

    v_idempotency_key := nullif(btrim(p_idempotency_key), '');
    v_user_id := nullif(btrim(p_user_id), '');
    v_source_reference := nullif(btrim(p_source_reference), '');
    v_country_code := lower(nullif(btrim(p_country_code), ''));
    v_currency_code := lower(nullif(btrim(p_currency_code), ''));
    v_metadata := coalesce(p_metadata, '{}'::jsonb);

    if v_idempotency_key is null then
        raise exception 'GAMIFICATION_IDEMPOTENCY_KEY_REQUIRED';
    end if;

    if p_event_type is null or p_event_type = 'reversal' then
        raise exception 'INVALID_GAMIFICATION_EARNING_EVENT_TYPE';
    end if;

    if v_user_id is null then
        raise exception 'GAMIFICATION_USER_ID_REQUIRED';
    end if;

    if v_source_reference is null then
        raise exception 'GAMIFICATION_SOURCE_REFERENCE_REQUIRED';
    end if;

    if p_amount is not null and p_amount < 0 then
        raise exception 'INVALID_GAMIFICATION_AMOUNT';
    end if;

    if p_amount_usd is not null and p_amount_usd < 0 then
        raise exception 'INVALID_GAMIFICATION_USD_AMOUNT';
    end if;

    if jsonb_typeof(v_metadata) <> 'object' then
        raise exception 'INVALID_GAMIFICATION_METADATA';
    end if;

    perform 1
    from public.users user_record
    where user_record.id = v_user_id;

    if not found then
        raise exception 'GAMIFICATION_USER_NOT_FOUND';
    end if;

    /*
     * Insert once. The idempotency key is the primary retry contract.
     * A separate user/event/reference key protects callers that accidentally
     * generate a different idempotency key for the same business event.
     */
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
        claimed_at,
        lease_expires_at
    )
    values (
        v_idempotency_key,
        p_event_type,
        'processing'::public."GamificationEventStatus",
        v_user_id,
        v_source_reference,
        nullif(btrim(p_source_transaction_id), ''),
        p_transaction_type,
        p_amount,
        p_amount_usd,
        v_country_code,
        v_currency_code,
        v_metadata,
        1,
        now(),
        now() + interval '5 minutes'
    )
    on conflict do nothing
    returning *
    into v_event;

    if not found then
        select event_record.*
        into v_event
        from public.gamification_event event_record
        where event_record.idempotency_key = v_idempotency_key
           or (
               event_record.user_id = v_user_id
               and event_record.event_type = p_event_type
               and event_record.source_reference = v_source_reference
           )
        order by
            case
                when event_record.idempotency_key = v_idempotency_key
                    then 0
                else 1
            end,
            event_record.created_at,
            event_record.id
        limit 1
        for update;

        if not found then
            raise exception 'GAMIFICATION_EVENT_CONFLICT_NOT_FOUND';
        end if;

        if v_event.user_id <> v_user_id
           or v_event.event_type <> p_event_type
           or v_event.source_reference <> v_source_reference
        then
            raise exception 'GAMIFICATION_IDEMPOTENCY_KEY_PAYLOAD_MISMATCH';
        end if;

        select ledger_record.*
        into v_existing_ledger
        from public.loyalty_ledger ledger_record
        where ledger_record.event_id = v_event.id
          and ledger_record.ledger_type = 'earn'
        limit 1;

        if found then
            return jsonb_build_object(
                'success', true,
                'idempotent_replay', true,
                'event_id', v_event.id,
                'event_status', v_event.status,
                'user_id', v_event.user_id,
                'event_type', v_event.event_type,
                'source_reference', v_event.source_reference,
                'points_awarded', v_existing_ledger.points_delta,
                'available_points',
                    v_existing_ledger.available_balance_after,
                'tier_points', v_existing_ledger.tier_balance_after,
                'level_code', (
                    select account_record.level_code
                    from public.loyalty_account account_record
                    where account_record.id =
                          v_existing_ledger.loyalty_account_id
                ),
                'ledger_id', v_existing_ledger.id
            );
        end if;

        if v_event.status in ('ignored', 'failed', 'reversed') then
            return jsonb_build_object(
                'success', v_event.status <> 'failed',
                'idempotent_replay', true,
                'event_id', v_event.id,
                'event_status', v_event.status,
                'user_id', v_event.user_id,
                'event_type', v_event.event_type,
                'source_reference', v_event.source_reference,
                'points_awarded', 0,
                'reason', v_event.error_message
            );
        end if;

        /* A prior call cannot still be processing while this row is locked. */
        raise exception 'GAMIFICATION_EVENT_ALREADY_PROCESSING';
    end if;

    v_event_time := v_event.created_at;
    v_daily_start := (v_event_time at time zone 'UTC')::date;
    v_monthly_start :=
        date_trunc('month', v_event_time at time zone 'UTC')::date;

    /* Country-specific configuration overrides the global configuration. */
    select config_record.*
    into v_program
    from public.loyalty_program_config config_record
    where config_record.is_active = true
      and (
          config_record.country_code = v_country_code
          or config_record.country_code is null
      )
    order by
        case
            when config_record.country_code = v_country_code then 0
            else 1
        end,
        config_record.updated_at desc,
        config_record.id
    limit 1;

    if not found then
        raise exception 'ACTIVE_LOYALTY_PROGRAM_CONFIGURATION_NOT_FOUND';
    end if;

    /* Resolve one rule deterministically from most specific to least. */
    select rule_record.*
    into v_rule
    from public.loyalty_rule rule_record
    where rule_record.event_type = p_event_type
      and rule_record.is_active = true
      and (rule_record.country_code is null
           or rule_record.country_code = v_country_code)
      and (rule_record.currency_code is null
           or rule_record.currency_code = v_currency_code)
      and (rule_record.valid_from is null
           or rule_record.valid_from <= v_event_time)
      and (rule_record.valid_until is null
           or rule_record.valid_until > v_event_time)
      and (rule_record.min_amount_usd is null
           or coalesce(p_amount_usd, 0) >= rule_record.min_amount_usd)
      and (rule_record.max_amount_usd is null
           or coalesce(p_amount_usd, 0) <= rule_record.max_amount_usd)
    order by
        case when rule_record.country_code is not null then 0 else 1 end,
        case when rule_record.currency_code is not null then 0 else 1 end,
        rule_record.priority,
        rule_record.valid_from desc nulls last,
        rule_record.id
    limit 1;

    if not found then
        update public.gamification_event
        set
            status = 'ignored'::public."GamificationEventStatus",
            processed_at = now(),
            lease_expires_at = null,
            error_message = 'NO_ACTIVE_LOYALTY_RULE'
        where id = v_event.id
        returning * into v_event;

        return jsonb_build_object(
            'success', true,
            'idempotent_replay', false,
            'event_id', v_event.id,
            'event_status', v_event.status,
            'user_id', v_event.user_id,
            'event_type', v_event.event_type,
            'source_reference', v_event.source_reference,
            'points_awarded', 0,
            'reason', v_event.error_message
        );
    end if;

    /*
     * Serialize awards for this customer before evaluating once-per-user
     * rules or cap usage. This closes the race between different events for
     * the same user while still allowing different users to process in
     * parallel.
     */
    perform pg_advisory_xact_lock(
        hashtext('loyalty-award:' || v_user_id)
    );

    if coalesce((v_rule.condition_config ->> 'once_per_user')::boolean, false)
       and exists (
           select 1
           from public.loyalty_ledger ledger_record
           where ledger_record.user_id = v_user_id
             and ledger_record.rule_id = v_rule.id
             and ledger_record.ledger_type = 'earn'
       )
    then
        update public.gamification_event
        set
            status = 'ignored'::public."GamificationEventStatus",
            processed_at = now(),
            lease_expires_at = null,
            error_message = 'LOYALTY_RULE_ALREADY_AWARDED'
        where id = v_event.id
        returning * into v_event;

        return jsonb_build_object(
            'success', true,
            'idempotent_replay', false,
            'event_id', v_event.id,
            'event_status', v_event.status,
            'user_id', v_event.user_id,
            'event_type', v_event.event_type,
            'source_reference', v_event.source_reference,
            'rule_code', v_rule.rule_code,
            'points_awarded', 0,
            'reason', v_event.error_message
        );
    end if;

    if v_rule.calculation_type in ('amount_based', 'fixed_plus_amount')
       and p_amount_usd is null
    then
        raise exception 'GAMIFICATION_USD_AMOUNT_REQUIRED_FOR_RULE_%',
            upper(v_rule.rule_code);
    end if;

    if v_rule.calculation_type = 'fixed' then
        v_raw_points := v_rule.fixed_points;

    elsif v_rule.calculation_type = 'amount_based' then
        v_raw_points := p_amount_usd * v_rule.points_per_usd;

    elsif v_rule.calculation_type = 'fixed_plus_amount' then
        v_raw_points :=
            v_rule.fixed_points +
            (p_amount_usd * v_rule.points_per_usd);

    elsif v_rule.calculation_type = 'amount_band' then
        if p_amount_usd is null then
            raise exception 'GAMIFICATION_USD_AMOUNT_REQUIRED_FOR_RULE_%',
                upper(v_rule.rule_code);
        end if;

        select band_record.*
        into v_band
        from public.loyalty_rule_band band_record
        where band_record.rule_id = v_rule.id
          and p_amount_usd >= band_record.min_amount_usd
          and (band_record.max_amount_usd is null
               or p_amount_usd <= band_record.max_amount_usd)
        order by
            band_record.min_amount_usd desc,
            band_record.sort_order,
            band_record.id
        limit 1;

        if not found then
            update public.gamification_event
            set
                status = 'ignored'::public."GamificationEventStatus",
                processed_at = now(),
                lease_expires_at = null,
                error_message = 'NO_MATCHING_LOYALTY_RULE_BAND'
            where id = v_event.id
            returning * into v_event;

            return jsonb_build_object(
                'success', true,
                'idempotent_replay', false,
                'event_id', v_event.id,
                'event_status', v_event.status,
                'user_id', v_event.user_id,
                'event_type', v_event.event_type,
                'source_reference', v_event.source_reference,
                'rule_code', v_rule.rule_code,
                'points_awarded', 0,
                'reason', v_event.error_message
            );
        end if;

        v_raw_points :=
            v_band.fixed_points +
            (p_amount_usd * v_band.points_per_usd);
    else
        raise exception 'UNSUPPORTED_LOYALTY_CALCULATION_TYPE';
    end if;

    v_raw_points := v_raw_points * v_rule.multiplier;
    v_calculated_points := floor(v_raw_points)::bigint;

    if v_rule.min_points_per_event is not null then
        v_calculated_points := greatest(
            v_calculated_points,
            v_rule.min_points_per_event
        );
    end if;

    if v_rule.max_points_per_event is not null then
        v_calculated_points := least(
            v_calculated_points,
            v_rule.max_points_per_event
        );
    end if;

    if v_calculated_points <= 0 then
        update public.gamification_event
        set
            status = 'ignored'::public."GamificationEventStatus",
            processed_at = now(),
            lease_expires_at = null,
            error_message = 'CALCULATED_LOYALTY_POINTS_ZERO'
        where id = v_event.id
        returning * into v_event;

        return jsonb_build_object(
            'success', true,
            'idempotent_replay', false,
            'event_id', v_event.id,
            'event_status', v_event.status,
            'user_id', v_event.user_id,
            'event_type', v_event.event_type,
            'source_reference', v_event.source_reference,
            'rule_code', v_rule.rule_code,
            'calculated_points', v_calculated_points,
            'points_awarded', 0,
            'reason', v_event.error_message
        );
    end if;

    /*
     * Lock one account per user before cap buckets. This produces a stable
     * lock order and serializes simultaneous awards for the same customer.
     */
    insert into public.loyalty_account (user_id)
    values (v_user_id)
    on conflict (user_id) do nothing;

    select account_record.*
    into v_account
    from public.loyalty_account account_record
    where account_record.user_id = v_user_id
    for update;

    if not v_account.is_active then
        raise exception 'LOYALTY_ACCOUNT_NOT_ACTIVE';
    end if;

    v_previous_level := v_account.level_code;

    /* Create and lock the global daily cap bucket. */
    insert into public.loyalty_cap_usage (
        user_id,
        rule_id,
        period_type,
        period_start,
        points_awarded
    )
    values (
        v_user_id,
        null,
        'daily'::public."LoyaltyCapPeriodType",
        v_daily_start,
        0
    )
    on conflict (user_id, period_type, period_start)
    where rule_id is null
    do nothing;

    select usage_record.points_awarded
    into v_program_daily_used
    from public.loyalty_cap_usage usage_record
    where usage_record.user_id = v_user_id
      and usage_record.rule_id is null
      and usage_record.period_type = 'daily'
      and usage_record.period_start = v_daily_start
    for update;

    /* Create and lock the global monthly cap bucket. */
    insert into public.loyalty_cap_usage (
        user_id,
        rule_id,
        period_type,
        period_start,
        points_awarded
    )
    values (
        v_user_id,
        null,
        'monthly'::public."LoyaltyCapPeriodType",
        v_monthly_start,
        0
    )
    on conflict (user_id, period_type, period_start)
    where rule_id is null
    do nothing;

    select usage_record.points_awarded
    into v_program_monthly_used
    from public.loyalty_cap_usage usage_record
    where usage_record.user_id = v_user_id
      and usage_record.rule_id is null
      and usage_record.period_type = 'monthly'
      and usage_record.period_start = v_monthly_start
    for update;

    v_program_daily_remaining := greatest(
        v_program.daily_points_cap - v_program_daily_used,
        0
    );

    v_program_monthly_remaining := greatest(
        v_program.monthly_points_cap - v_program_monthly_used,
        0
    );

    v_awarded_points := least(
        v_calculated_points,
        v_program_daily_remaining,
        v_program_monthly_remaining
    );

    /* Rule cap buckets are only created when that rule defines a cap. */
    if v_rule.daily_cap_points is not null then
        insert into public.loyalty_cap_usage (
            user_id,
            rule_id,
            period_type,
            period_start,
            points_awarded
        )
        values (
            v_user_id,
            v_rule.id,
            'daily'::public."LoyaltyCapPeriodType",
            v_daily_start,
            0
        )
        on conflict (user_id, rule_id, period_type, period_start)
        where rule_id is not null
        do nothing;

        select usage_record.points_awarded
        into v_rule_daily_used
        from public.loyalty_cap_usage usage_record
        where usage_record.user_id = v_user_id
          and usage_record.rule_id = v_rule.id
          and usage_record.period_type = 'daily'
          and usage_record.period_start = v_daily_start
        for update;

        v_rule_daily_remaining := greatest(
            v_rule.daily_cap_points - v_rule_daily_used,
            0
        );

        v_awarded_points := least(
            v_awarded_points,
            v_rule_daily_remaining
        );
    end if;

    if v_rule.monthly_cap_points is not null then
        insert into public.loyalty_cap_usage (
            user_id,
            rule_id,
            period_type,
            period_start,
            points_awarded
        )
        values (
            v_user_id,
            v_rule.id,
            'monthly'::public."LoyaltyCapPeriodType",
            v_monthly_start,
            0
        )
        on conflict (user_id, rule_id, period_type, period_start)
        where rule_id is not null
        do nothing;

        select usage_record.points_awarded
        into v_rule_monthly_used
        from public.loyalty_cap_usage usage_record
        where usage_record.user_id = v_user_id
          and usage_record.rule_id = v_rule.id
          and usage_record.period_type = 'monthly'
          and usage_record.period_start = v_monthly_start
        for update;

        v_rule_monthly_remaining := greatest(
            v_rule.monthly_cap_points - v_rule_monthly_used,
            0
        );

        v_awarded_points := least(
            v_awarded_points,
            v_rule_monthly_remaining
        );
    end if;

    if v_awarded_points <= 0 then
        update public.gamification_event
        set
            status = 'ignored'::public."GamificationEventStatus",
            processed_at = now(),
            lease_expires_at = null,
            error_message = 'LOYALTY_POINTS_CAP_REACHED',
            metadata = metadata || jsonb_build_object(
                'calculated_points', v_calculated_points,
                'points_awarded', 0
            )
        where id = v_event.id
        returning * into v_event;

        return jsonb_build_object(
            'success', true,
            'idempotent_replay', false,
            'event_id', v_event.id,
            'event_status', v_event.status,
            'user_id', v_event.user_id,
            'event_type', v_event.event_type,
            'source_reference', v_event.source_reference,
            'rule_code', v_rule.rule_code,
            'calculated_points', v_calculated_points,
            'points_awarded', 0,
            'reason', v_event.error_message
        );
    end if;

    update public.loyalty_cap_usage
    set
        points_awarded = points_awarded + v_awarded_points,
        updated_at = now()
    where user_id = v_user_id
      and rule_id is null
      and period_type = 'daily'
      and period_start = v_daily_start;

    update public.loyalty_cap_usage
    set
        points_awarded = points_awarded + v_awarded_points,
        updated_at = now()
    where user_id = v_user_id
      and rule_id is null
      and period_type = 'monthly'
      and period_start = v_monthly_start;

    if v_rule.daily_cap_points is not null then
        update public.loyalty_cap_usage
        set
            points_awarded = points_awarded + v_awarded_points,
            updated_at = now()
        where user_id = v_user_id
          and rule_id = v_rule.id
          and period_type = 'daily'
          and period_start = v_daily_start;
    end if;

    if v_rule.monthly_cap_points is not null then
        update public.loyalty_cap_usage
        set
            points_awarded = points_awarded + v_awarded_points,
            updated_at = now()
        where user_id = v_user_id
          and rule_id = v_rule.id
          and period_type = 'monthly'
          and period_start = v_monthly_start;
    end if;

    update public.loyalty_account
    set
        available_points = available_points + v_awarded_points,
        tier_points = tier_points + v_awarded_points,
        lifetime_earned_points =
            lifetime_earned_points + v_awarded_points,
        last_event_at = v_event_time
    where id = v_account.id
    returning * into v_account;

    select level_record.level_code
    into v_new_level
    from public.loyalty_level level_record
    where level_record.is_active = true
      and level_record.min_tier_points <= v_account.tier_points
      and (level_record.max_tier_points is null
           or level_record.max_tier_points >= v_account.tier_points)
    order by level_record.min_tier_points desc
    limit 1;

    if not found then
        raise exception 'LOYALTY_LEVEL_NOT_FOUND_FOR_POINTS_%',
            v_account.tier_points;
    end if;

    if v_new_level <> v_previous_level then
        update public.loyalty_account
        set level_code = v_new_level
        where id = v_account.id
        returning * into v_account;

        insert into public.loyalty_level_history (
            loyalty_account_id,
            user_id,
            event_id,
            previous_level_code,
            new_level_code,
            tier_points,
            reason
        )
        values (
            v_account.id,
            v_user_id,
            v_event.id,
            v_previous_level,
            v_new_level,
            v_account.tier_points,
            'points_earned'::public."LoyaltyLevelChangeReason"
        );
    end if;

    v_rule_snapshot := jsonb_build_object(
        'rule_code', v_rule.rule_code,
        'rule_name', v_rule.rule_name,
        'calculation_type', v_rule.calculation_type,
        'fixed_points', v_rule.fixed_points,
        'points_per_usd', v_rule.points_per_usd,
        'multiplier', v_rule.multiplier,
        'min_points_per_event', v_rule.min_points_per_event,
        'max_points_per_event', v_rule.max_points_per_event,
        'daily_cap_points', v_rule.daily_cap_points,
        'monthly_cap_points', v_rule.monthly_cap_points,
        'condition_config', v_rule.condition_config,
        'calculated_points', v_calculated_points,
        'awarded_points', v_awarded_points
    );

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
        description,
        rule_snapshot,
        metadata
    )
    values (
        v_account.id,
        v_user_id,
        v_event.id,
        v_rule.id,
        'earn'::public."LoyaltyLedgerType",
        p_event_type,
        v_awarded_points,
        v_account.available_points,
        v_awarded_points,
        v_account.tier_points,
        v_source_reference,
        v_rule.rule_name,
        v_rule_snapshot,
        v_metadata
    )
    returning * into v_ledger;

    update public.gamification_event
    set
        status = 'completed'::public."GamificationEventStatus",
        processed_at = now(),
        lease_expires_at = null,
        error_message = null,
        metadata = metadata || jsonb_build_object(
            'rule_code', v_rule.rule_code,
            'calculated_points', v_calculated_points,
            'points_awarded', v_awarded_points,
            'level_code', v_account.level_code
        )
    where id = v_event.id
    returning * into v_event;

    insert into public.gamification_notification (
        user_id,
        event_id,
        notification_type,
        points,
        title,
        subtitle,
        display_priority,
        payload
    )
    values (
        v_user_id,
        v_event.id,
        'points_earned'::public."GamificationNotificationType",
        v_awarded_points,
        '+' || v_awarded_points::text || ' points',
        v_rule.rule_name,
        100,
        jsonb_build_object(
            'event_type', p_event_type,
            'source_reference', v_source_reference,
            'points_awarded', v_awarded_points,
            'available_points', v_account.available_points,
            'tier_points', v_account.tier_points,
            'level_code', v_account.level_code
        )
    )
    on conflict (event_id, notification_type)
    where event_id is not null
    do nothing;

    if v_new_level <> v_previous_level then
        insert into public.gamification_notification (
            user_id,
            event_id,
            notification_type,
            points,
            title,
            subtitle,
            display_priority,
            payload
        )
        values (
            v_user_id,
            v_event.id,
            'level_up'::public."GamificationNotificationType",
            0,
            'Level up!',
            'You reached ' || initcap(v_new_level),
            10,
            jsonb_build_object(
                'previous_level_code', v_previous_level,
                'new_level_code', v_new_level,
                'tier_points', v_account.tier_points
            )
        )
        on conflict (event_id, notification_type)
        where event_id is not null
        do nothing;
    end if;

    v_result := jsonb_build_object(
        'success', true,
        'idempotent_replay', false,
        'event_id', v_event.id,
        'event_status', v_event.status,
        'user_id', v_event.user_id,
        'event_type', v_event.event_type,
        'source_reference', v_event.source_reference,
        'rule_code', v_rule.rule_code,
        'calculated_points', v_calculated_points,
        'points_awarded', v_awarded_points,
        'available_points', v_account.available_points,
        'tier_points', v_account.tier_points,
        'lifetime_earned_points', v_account.lifetime_earned_points,
        'previous_level_code', v_previous_level,
        'level_code', v_account.level_code,
        'level_changed', v_new_level <> v_previous_level,
        'ledger_id', v_ledger.id
    );

    return v_result;
end;
$$;


/* =========================================================
 * REVERSE THE EXACT ORIGINAL AWARD
 *
 * Reversal does not reduce cap usage. This prevents a user from repeatedly
 * earning, reversing, and re-earning within the same cap period.
 * ========================================================= */

create or replace function public.reverse_loyalty_points(
    p_original_event_id text,
    p_idempotency_key text,
    p_source_reference text,
    p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_original_event public.gamification_event%rowtype;
    v_reversal_event public.gamification_event%rowtype;
    v_original_ledger public.loyalty_ledger%rowtype;
    v_reversal_ledger public.loyalty_ledger%rowtype;
    v_account public.loyalty_account%rowtype;
    v_existing_reversal public.loyalty_ledger%rowtype;

    v_original_event_id text;
    v_idempotency_key text;
    v_source_reference text;
    v_metadata jsonb;

    v_previous_level text;
    v_new_level text;
    v_tier_reversal bigint;
begin
    if coalesce(auth.role(), '') <> 'service_role' then
        raise exception using
            errcode = '42501',
            message = 'SERVICE_ROLE_REQUIRED';
    end if;

    v_original_event_id := nullif(btrim(p_original_event_id), '');
    v_idempotency_key := nullif(btrim(p_idempotency_key), '');
    v_source_reference := nullif(btrim(p_source_reference), '');
    v_metadata := coalesce(p_metadata, '{}'::jsonb);

    if v_original_event_id is null then
        raise exception 'ORIGINAL_GAMIFICATION_EVENT_ID_REQUIRED';
    end if;

    if v_idempotency_key is null then
        raise exception 'GAMIFICATION_IDEMPOTENCY_KEY_REQUIRED';
    end if;

    if v_source_reference is null then
        raise exception 'GAMIFICATION_SOURCE_REFERENCE_REQUIRED';
    end if;

    if jsonb_typeof(v_metadata) <> 'object' then
        raise exception 'INVALID_GAMIFICATION_METADATA';
    end if;

    select event_record.*
    into v_original_event
    from public.gamification_event event_record
    where event_record.id::text = v_original_event_id
    for update;

    if not found then
        raise exception 'ORIGINAL_GAMIFICATION_EVENT_NOT_FOUND';
    end if;

    select ledger_record.*
    into v_original_ledger
    from public.loyalty_ledger ledger_record
    where ledger_record.event_id = v_original_event.id
      and ledger_record.ledger_type = 'earn'
    limit 1;

    if not found then
        raise exception 'ORIGINAL_LOYALTY_AWARD_NOT_FOUND';
    end if;

    select ledger_record.*
    into v_existing_reversal
    from public.loyalty_ledger ledger_record
    where ledger_record.reversal_of_ledger_id = v_original_ledger.id
    limit 1;

    if found then
        return jsonb_build_object(
            'success', true,
            'idempotent_replay', true,
            'original_event_id', v_original_event.id,
            'reversal_event_id', v_existing_reversal.event_id,
            'reversal_ledger_id', v_existing_reversal.id,
            'points_reversed', abs(v_existing_reversal.points_delta),
            'available_points',
                v_existing_reversal.available_balance_after,
            'tier_points', v_existing_reversal.tier_balance_after
        );
    end if;

    insert into public.gamification_event (
        idempotency_key,
        event_type,
        status,
        user_id,
        source_reference,
        source_transaction_id,
        transaction_type,
        country_code,
        currency_code,
        metadata,
        attempt_count,
        claimed_at,
        processed_at
    )
    values (
        v_idempotency_key,
        'reversal'::public."LoyaltyEventType",
        'completed'::public."GamificationEventStatus",
        v_original_event.user_id,
        v_source_reference,
        v_original_event.source_transaction_id,
        v_original_event.transaction_type,
        v_original_event.country_code,
        v_original_event.currency_code,
        v_metadata || jsonb_build_object(
            'original_event_id', v_original_event.id,
            'original_source_reference',
                v_original_event.source_reference
        ),
        1,
        now(),
        now()
    )
    on conflict (idempotency_key)
    do nothing
    returning *
    into v_reversal_event;

    if not found then
        select event_record.*
        into v_reversal_event
        from public.gamification_event event_record
        where event_record.idempotency_key = v_idempotency_key
        for update;

        if v_reversal_event.event_type <> 'reversal'
           or v_reversal_event.user_id <> v_original_event.user_id
           or v_reversal_event.source_reference <> v_source_reference
        then
            raise exception 'GAMIFICATION_IDEMPOTENCY_KEY_PAYLOAD_MISMATCH';
        end if;

        select ledger_record.*
        into v_existing_reversal
        from public.loyalty_ledger ledger_record
        where ledger_record.event_id = v_reversal_event.id
          and ledger_record.ledger_type = 'reverse'
        limit 1;

        if found then
            return jsonb_build_object(
                'success', true,
                'idempotent_replay', true,
                'original_event_id', v_original_event.id,
                'reversal_event_id', v_reversal_event.id,
                'reversal_ledger_id', v_existing_reversal.id,
                'points_reversed', abs(v_existing_reversal.points_delta),
                'available_points',
                    v_existing_reversal.available_balance_after,
                'tier_points', v_existing_reversal.tier_balance_after
            );
        end if;

        raise exception 'GAMIFICATION_REVERSAL_EVENT_INCOMPLETE';
    end if;

    select account_record.*
    into v_account
    from public.loyalty_account account_record
    where account_record.id = v_original_ledger.loyalty_account_id
      and account_record.user_id = v_original_event.user_id
    for update;

    if not found then
        raise exception 'LOYALTY_ACCOUNT_NOT_FOUND';
    end if;

    v_previous_level := v_account.level_code;
    v_tier_reversal := least(
        v_original_ledger.tier_points_delta,
        v_account.tier_points
    );

    update public.loyalty_account
    set
        available_points =
            available_points - v_original_ledger.points_delta,
        tier_points = tier_points - v_tier_reversal,
        last_event_at = now()
    where id = v_account.id
    returning * into v_account;

    select level_record.level_code
    into v_new_level
    from public.loyalty_level level_record
    where level_record.is_active = true
      and level_record.min_tier_points <= v_account.tier_points
      and (level_record.max_tier_points is null
           or level_record.max_tier_points >= v_account.tier_points)
    order by level_record.min_tier_points desc
    limit 1;

    if not found then
        raise exception 'LOYALTY_LEVEL_NOT_FOUND_FOR_POINTS_%',
            v_account.tier_points;
    end if;

    if v_new_level <> v_previous_level then
        update public.loyalty_account
        set level_code = v_new_level
        where id = v_account.id
        returning * into v_account;

        insert into public.loyalty_level_history (
            loyalty_account_id,
            user_id,
            event_id,
            previous_level_code,
            new_level_code,
            tier_points,
            reason
        )
        values (
            v_account.id,
            v_account.user_id,
            v_reversal_event.id,
            v_previous_level,
            v_new_level,
            v_account.tier_points,
            'points_reversed'::public."LoyaltyLevelChangeReason"
        );
    end if;

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
        description,
        reversal_of_ledger_id,
        rule_snapshot,
        metadata
    )
    values (
        v_account.id,
        v_account.user_id,
        v_reversal_event.id,
        v_original_ledger.rule_id,
        'reverse'::public."LoyaltyLedgerType",
        'reversal'::public."LoyaltyEventType",
        -v_original_ledger.points_delta,
        v_account.available_points,
        -v_tier_reversal,
        v_account.tier_points,
        v_source_reference,
        'Reversal of ' ||
            coalesce(v_original_ledger.description, 'loyalty award'),
        v_original_ledger.id,
        v_original_ledger.rule_snapshot,
        v_metadata
    )
    returning * into v_reversal_ledger;

    update public.gamification_event
    set
        status = 'reversed'::public."GamificationEventStatus",
        reversed_at = now(),
        reversal_event_id = v_reversal_event.id
    where id = v_original_event.id;

    if v_new_level <> v_previous_level then
        insert into public.gamification_notification (
            user_id,
            event_id,
            notification_type,
            points,
            title,
            subtitle,
            display_priority,
            payload
        )
        values (
            v_account.user_id,
            v_reversal_event.id,
            'level_down'::public."GamificationNotificationType",
            0,
            'Level updated',
            'Your level is now ' || initcap(v_new_level),
            20,
            jsonb_build_object(
                'previous_level_code', v_previous_level,
                'new_level_code', v_new_level,
                'tier_points', v_account.tier_points,
                'original_event_id', v_original_event.id
            )
        )
        on conflict (event_id, notification_type)
        where event_id is not null
        do nothing;
    end if;

    return jsonb_build_object(
        'success', true,
        'idempotent_replay', false,
        'original_event_id', v_original_event.id,
        'reversal_event_id', v_reversal_event.id,
        'reversal_ledger_id', v_reversal_ledger.id,
        'points_reversed', v_original_ledger.points_delta,
        'available_points', v_account.available_points,
        'tier_points', v_account.tier_points,
        'previous_level_code', v_previous_level,
        'level_code', v_account.level_code,
        'level_changed', v_new_level <> v_previous_level
    );
end;
$$;


/* =========================================================
 * EXECUTION SECURITY
 * ========================================================= */

revoke all on function public.award_loyalty_points(
    text,
    public."LoyaltyEventType",
    text,
    text,
    text,
    public."TransactionType",
    numeric,
    numeric,
    text,
    text,
    jsonb
)
from public, anon, authenticated;


grant execute on function public.award_loyalty_points(
    text,
    public."LoyaltyEventType",
    text,
    text,
    text,
    public."TransactionType",
    numeric,
    numeric,
    text,
    text,
    jsonb
)
to service_role;


revoke all on function public.reverse_loyalty_points(
    text,
    text,
    text,
    jsonb
)
from public, anon, authenticated;


grant execute on function public.reverse_loyalty_points(
    text,
    text,
    text,
    jsonb
)
to service_role;


/* =========================================================
 * VERIFICATION
 * ========================================================= */

select
    routine_name,
    security_type,
    data_type
from information_schema.routines
where routine_schema = 'public'
  and routine_name in (
      'award_loyalty_points',
      'reverse_loyalty_points'
  )
order by routine_name;
