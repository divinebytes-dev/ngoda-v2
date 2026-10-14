/*
 * Ngoda Gamification - Core Schema
 *
 * This migration creates the durable contracts used by the points engine.
 * It deliberately does not couple loyalty points to financial balances.
 *
 * Core invariants:
 *   1. Business events are idempotent.
 *   2. Points movements are append-only.
 *   3. Spendable points and tier points are separate balances.
 *   4. Redemptions do not demote a user.
 *   5. Reversals link to the exact original award.
 *   6. Flutter displays backend-issued reward notifications and never
 *      calculates authoritative points itself.
 */


/* =========================================================
 * ENUMS
 * ========================================================= */

do $$
begin
    create type public."LoyaltyEventType" as enum (
        'kyc_completed',
        'user_deposit',
        'user_transfer',
        'merchant_payment',
        'gold_token_buy',
        'gold_token_sell',
        'loan_repayment',
        'loan_repayment_on_time_bonus',
        'referral_completed',
        'monthly_activity_bonus',
        'challenge_completed',
        'manual_adjustment',
        'reversal'
    );
exception
    when duplicate_object then null;
end;
$$;


do $$
begin
    create type public."GamificationEventStatus" as enum (
        'pending',
        'processing',
        'completed',
        'ignored',
        'failed',
        'reversed'
    );
exception
    when duplicate_object then null;
end;
$$;


do $$
begin
    create type public."LoyaltyLedgerType" as enum (
        'earn',
        'redeem',
        'reverse',
        'expire',
        'adjustment'
    );
exception
    when duplicate_object then null;
end;
$$;


do $$
begin
    create type public."LoyaltyRuleCalculationType" as enum (
        'fixed',
        'amount_based',
        'fixed_plus_amount',
        'amount_band'
    );
exception
    when duplicate_object then null;
end;
$$;


do $$
begin
    create type public."LoyaltyCapPeriodType" as enum (
        'daily',
        'monthly'
    );
exception
    when duplicate_object then null;
end;
$$;


do $$
begin
    create type public."LoyaltyLevelChangeReason" as enum (
        'account_created',
        'points_earned',
        'points_reversed',
        'manual_adjustment'
    );
exception
    when duplicate_object then null;
end;
$$;


do $$
begin
    create type public."GamificationNotificationType" as enum (
        'points_earned',
        'level_up',
        'level_down',
        'badge_awarded',
        'challenge_completed',
        'reward_available'
    );
exception
    when duplicate_object then null;
end;
$$;


/* =========================================================
 * CONFIGURATION
 * ========================================================= */

create table if not exists public.loyalty_level (
    id text primary key
        default (gen_random_uuid())::text,

    level_code text not null unique,
    name text not null,

    min_tier_points bigint not null unique,
    max_tier_points bigint,
    sort_order integer not null unique,

    benefits jsonb not null
        default '{}'::jsonb,

    is_active boolean not null
        default true,

    created_at timestamptz not null
        default now(),

    updated_at timestamptz not null
        default now(),

    constraint loyalty_level_code_check
        check (
            level_code = lower(btrim(level_code))
            and level_code ~ '^[a-z][a-z0-9_]*$'
        ),

    constraint loyalty_level_name_check
        check (nullif(btrim(name), '') is not null),

    constraint loyalty_level_points_check
        check (
            min_tier_points >= 0
            and (
                max_tier_points is null
                or max_tier_points >= min_tier_points
            )
        ),

    constraint loyalty_level_sort_order_check
        check (sort_order >= 1),

    constraint loyalty_level_benefits_object_check
        check (jsonb_typeof(benefits) = 'object')
);


create table if not exists public.loyalty_program_config (
    id text primary key
        default (gen_random_uuid())::text,

    country_code text,

    daily_points_cap bigint not null
        default 500,

    monthly_points_cap bigint not null
        default 5000,

    points_expiry_months integer,

    is_active boolean not null
        default true,

    created_at timestamptz not null
        default now(),

    updated_at timestamptz not null
        default now(),

    constraint loyalty_program_config_country_check
        check (
            country_code is null
            or country_code = lower(btrim(country_code))
        ),

    constraint loyalty_program_config_caps_check
        check (
            daily_points_cap >= 0
            and monthly_points_cap >= daily_points_cap
        ),

    constraint loyalty_program_config_expiry_check
        check (
            points_expiry_months is null
            or points_expiry_months >= 1
        )
);


create unique index if not exists
    loyalty_program_config_global_unique
on public.loyalty_program_config ((country_code is null))
where country_code is null
  and is_active = true;


create unique index if not exists
    loyalty_program_config_country_unique
on public.loyalty_program_config (lower(btrim(country_code)))
where country_code is not null
  and is_active = true;


create table if not exists public.loyalty_rule (
    id text primary key
        default (gen_random_uuid())::text,

    event_type public."LoyaltyEventType" not null,
    rule_code text not null unique,
    rule_name text not null,

    calculation_type
        public."LoyaltyRuleCalculationType" not null,

    fixed_points numeric(20, 6),
    points_per_usd numeric(20, 6),

    min_amount_usd numeric(20, 6),
    max_amount_usd numeric(20, 6),

    min_points_per_event bigint,
    max_points_per_event bigint,

    daily_cap_points bigint,
    monthly_cap_points bigint,

    country_code text,
    currency_code text,

    multiplier numeric(10, 4) not null
        default 1,

    priority integer not null
        default 100,

    condition_config jsonb not null
        default '{}'::jsonb,

    valid_from timestamptz,
    valid_until timestamptz,

    is_active boolean not null
        default true,

    created_at timestamptz not null
        default now(),

    updated_at timestamptz not null
        default now(),

    constraint loyalty_rule_code_check
        check (
            rule_code = lower(btrim(rule_code))
            and rule_code ~ '^[a-z][a-z0-9_]*$'
        ),

    constraint loyalty_rule_name_check
        check (nullif(btrim(rule_name), '') is not null),

    constraint loyalty_rule_amount_values_check
        check (
            coalesce(fixed_points, 0) >= 0
            and coalesce(points_per_usd, 0) >= 0
            and coalesce(min_amount_usd, 0) >= 0
            and coalesce(max_amount_usd, 0) >= 0
        ),

    constraint loyalty_rule_amount_range_check
        check (
            max_amount_usd is null
            or min_amount_usd is null
            or max_amount_usd >= min_amount_usd
        ),

    constraint loyalty_rule_points_range_check
        check (
            coalesce(min_points_per_event, 0) >= 0
            and coalesce(max_points_per_event, 0) >= 0
            and (
                max_points_per_event is null
                or min_points_per_event is null
                or max_points_per_event >= min_points_per_event
            )
        ),

    constraint loyalty_rule_caps_check
        check (
            coalesce(daily_cap_points, 0) >= 0
            and coalesce(monthly_cap_points, 0) >= 0
            and (
                monthly_cap_points is null
                or daily_cap_points is null
                or monthly_cap_points >= daily_cap_points
            )
        ),

    constraint loyalty_rule_scope_check
        check (
            (
                country_code is null
                or country_code = lower(btrim(country_code))
            )
            and (
                currency_code is null
                or currency_code = lower(btrim(currency_code))
            )
        ),

    constraint loyalty_rule_multiplier_check
        check (multiplier > 0),

    constraint loyalty_rule_priority_check
        check (priority >= 0),

    constraint loyalty_rule_condition_object_check
        check (jsonb_typeof(condition_config) = 'object'),

    constraint loyalty_rule_dates_check
        check (
            valid_until is null
            or valid_from is null
            or valid_until > valid_from
        ),

    constraint loyalty_rule_calculation_fields_check
        check (
            (
                calculation_type = 'fixed'
                and fixed_points is not null
                and points_per_usd is null
            )
            or (
                calculation_type = 'amount_based'
                and points_per_usd is not null
                and fixed_points is null
            )
            or (
                calculation_type = 'fixed_plus_amount'
                and fixed_points is not null
                and points_per_usd is not null
            )
            or calculation_type = 'amount_band'
        )
);


create index if not exists loyalty_rule_resolution_idx
on public.loyalty_rule (
    event_type,
    is_active,
    priority,
    valid_from,
    valid_until
);


create table if not exists public.loyalty_rule_band (
    id text primary key
        default (gen_random_uuid())::text,

    rule_id text not null
        references public.loyalty_rule(id)
        on update cascade
        on delete restrict,

    min_amount_usd numeric(20, 6) not null,
    max_amount_usd numeric(20, 6),

    fixed_points numeric(20, 6) not null
        default 0,

    points_per_usd numeric(20, 6) not null
        default 0,

    sort_order integer not null,

    created_at timestamptz not null
        default now(),

    constraint loyalty_rule_band_amount_check
        check (
            min_amount_usd >= 0
            and (
                max_amount_usd is null
                or max_amount_usd >= min_amount_usd
            )
        ),

    constraint loyalty_rule_band_points_check
        check (
            fixed_points >= 0
            and points_per_usd >= 0
        ),

    constraint loyalty_rule_band_sort_check
        check (sort_order >= 1),

    constraint loyalty_rule_band_rule_sort_unique
        unique (rule_id, sort_order)
);


create index if not exists loyalty_rule_band_resolution_idx
on public.loyalty_rule_band (
    rule_id,
    min_amount_usd,
    max_amount_usd
);


/* =========================================================
 * USER ACCOUNT AND EVENT INBOX
 * ========================================================= */

create table if not exists public.loyalty_account (
    id text primary key
        default (gen_random_uuid())::text,

    user_id text not null unique
        references public.users(id)
        on update cascade
        on delete restrict,

    /* Spendable points. Redemptions reduce this value. */
    available_points bigint not null
        default 0,

    /* Tier progression. Redemptions do not reduce this value. */
    tier_points bigint not null
        default 0,

    /* Gross points ever earned, retained for analytics. */
    lifetime_earned_points bigint not null
        default 0,

    level_code text not null
        default 'bronze'
        references public.loyalty_level(level_code)
        on update cascade
        on delete restrict,

    is_active boolean not null
        default true,

    last_event_at timestamptz,

    created_at timestamptz not null
        default now(),

    updated_at timestamptz not null
        default now(),

    constraint loyalty_account_tier_points_check
        check (tier_points >= 0),

    constraint loyalty_account_lifetime_points_check
        check (lifetime_earned_points >= 0)
);


create index if not exists loyalty_account_level_idx
on public.loyalty_account (level_code, tier_points desc);


create table if not exists public.gamification_event (
    id text primary key
        default (gen_random_uuid())::text,

    idempotency_key text not null unique,

    event_type public."LoyaltyEventType" not null,
    status public."GamificationEventStatus" not null
        default 'pending',

    user_id text not null
        references public.users(id)
        on update cascade
        on delete restrict,

    source_reference text not null,
    source_transaction_id text,
    transaction_type public."TransactionType",

    amount numeric(20, 6),
    amount_usd numeric(20, 6),

    country_code text,
    currency_code text,

    metadata jsonb not null
        default '{}'::jsonb,

    attempt_count integer not null
        default 0,

    claimed_at timestamptz,
    lease_expires_at timestamptz,
    processed_at timestamptz,

    error_message text,

    reversed_at timestamptz,
    reversal_event_id text,

    created_at timestamptz not null
        default now(),

    updated_at timestamptz not null
        default now(),

    constraint gamification_event_idempotency_key_check
        check (nullif(btrim(idempotency_key), '') is not null),

    constraint gamification_event_reference_check
        check (nullif(btrim(source_reference), '') is not null),

    constraint gamification_event_amount_check
        check (
            coalesce(amount, 0) >= 0
            and coalesce(amount_usd, 0) >= 0
        ),

    constraint gamification_event_scope_check
        check (
            (
                country_code is null
                or country_code = lower(btrim(country_code))
            )
            and (
                currency_code is null
                or currency_code = lower(btrim(currency_code))
            )
        ),

    constraint gamification_event_metadata_object_check
        check (jsonb_typeof(metadata) = 'object'),

    constraint gamification_event_attempt_count_check
        check (attempt_count >= 0),

    constraint gamification_event_reversal_self_check
        check (
            reversal_event_id is null
            or reversal_event_id <> id
        ),

    constraint gamification_event_user_source_unique
        unique (user_id, event_type, source_reference)
);


alter table public.gamification_event
    drop constraint if exists
        gamification_event_reversal_event_id_fkey;


alter table public.gamification_event
    add constraint gamification_event_reversal_event_id_fkey
    foreign key (reversal_event_id)
    references public.gamification_event(id)
    on update cascade
    on delete restrict;


create index if not exists gamification_event_claim_idx
on public.gamification_event (
    status,
    lease_expires_at,
    created_at,
    id
);


create index if not exists gamification_event_user_history_idx
on public.gamification_event (
    user_id,
    event_type,
    created_at desc
);


create index if not exists gamification_event_source_transaction_idx
on public.gamification_event (source_transaction_id)
where source_transaction_id is not null;


/* =========================================================
 * CAP BUCKETS AND IMMUTABLE LEDGER
 * ========================================================= */

create table if not exists public.loyalty_cap_usage (
    id text primary key
        default (gen_random_uuid())::text,

    user_id text not null
        references public.users(id)
        on update cascade
        on delete restrict,

    rule_id text
        references public.loyalty_rule(id)
        on update cascade
        on delete restrict,

    period_type public."LoyaltyCapPeriodType" not null,
    period_start date not null,

    points_awarded bigint not null
        default 0,

    updated_at timestamptz not null
        default now(),

    constraint loyalty_cap_usage_points_check
        check (points_awarded >= 0)
);


create unique index if not exists
    loyalty_cap_usage_program_unique
on public.loyalty_cap_usage (
    user_id,
    period_type,
    period_start
)
where rule_id is null;


create unique index if not exists
    loyalty_cap_usage_rule_unique
on public.loyalty_cap_usage (
    user_id,
    rule_id,
    period_type,
    period_start
)
where rule_id is not null;


create table if not exists public.loyalty_ledger (
    id text primary key
        default (gen_random_uuid())::text,

    loyalty_account_id text not null
        references public.loyalty_account(id)
        on update cascade
        on delete restrict,

    user_id text not null
        references public.users(id)
        on update cascade
        on delete restrict,

    event_id text
        references public.gamification_event(id)
        on update cascade
        on delete restrict,

    rule_id text
        references public.loyalty_rule(id)
        on update cascade
        on delete restrict,

    ledger_type public."LoyaltyLedgerType" not null,
    event_type public."LoyaltyEventType",

    /* Signed movement applied to available points. */
    points_delta bigint not null,
    available_balance_after bigint not null,

    /* Signed movement applied to tier progression. */
    tier_points_delta bigint not null
        default 0,

    tier_balance_after bigint not null,

    source_reference text,
    description text,

    reversal_of_ledger_id text
        references public.loyalty_ledger(id)
        on update cascade
        on delete restrict,

    rule_snapshot jsonb,
    metadata jsonb not null
        default '{}'::jsonb,

    created_at timestamptz not null
        default now(),

    constraint loyalty_ledger_points_direction_check
        check (
            (
                ledger_type = 'earn'
                and points_delta > 0
                and tier_points_delta >= 0
            )
            or (
                ledger_type in ('redeem', 'expire')
                and points_delta < 0
                and tier_points_delta = 0
            )
            or (
                ledger_type = 'reverse'
                and points_delta < 0
                and tier_points_delta <= 0
            )
            or (
                ledger_type = 'adjustment'
                and points_delta <> 0
            )
        ),

    constraint loyalty_ledger_tier_balance_check
        check (tier_balance_after >= 0),

    constraint loyalty_ledger_reversal_link_check
        check (
            (
                ledger_type = 'reverse'
                and reversal_of_ledger_id is not null
            )
            or (
                ledger_type <> 'reverse'
                and reversal_of_ledger_id is null
            )
        ),

    constraint loyalty_ledger_rule_snapshot_check
        check (
            rule_snapshot is null
            or jsonb_typeof(rule_snapshot) = 'object'
        ),

    constraint loyalty_ledger_metadata_object_check
        check (jsonb_typeof(metadata) = 'object')
);


create unique index if not exists loyalty_ledger_event_earn_unique
on public.loyalty_ledger (event_id)
where event_id is not null
  and ledger_type = 'earn';


create unique index if not exists loyalty_ledger_reversal_unique
on public.loyalty_ledger (reversal_of_ledger_id)
where reversal_of_ledger_id is not null;


create index if not exists loyalty_ledger_account_history_idx
on public.loyalty_ledger (
    loyalty_account_id,
    created_at desc,
    id desc
);


create index if not exists loyalty_ledger_user_history_idx
on public.loyalty_ledger (
    user_id,
    created_at desc,
    id desc
);


create index if not exists loyalty_ledger_source_reference_idx
on public.loyalty_ledger (source_reference)
where source_reference is not null;


/* =========================================================
 * TIER HISTORY AND FLUTTER REWARD INBOX
 * ========================================================= */

create table if not exists public.loyalty_level_history (
    id text primary key
        default (gen_random_uuid())::text,

    loyalty_account_id text not null
        references public.loyalty_account(id)
        on update cascade
        on delete restrict,

    user_id text not null
        references public.users(id)
        on update cascade
        on delete restrict,

    event_id text
        references public.gamification_event(id)
        on update cascade
        on delete restrict,

    previous_level_code text
        references public.loyalty_level(level_code)
        on update cascade
        on delete restrict,

    new_level_code text not null
        references public.loyalty_level(level_code)
        on update cascade
        on delete restrict,

    tier_points bigint not null,

    reason public."LoyaltyLevelChangeReason" not null,

    created_at timestamptz not null
        default now(),

    constraint loyalty_level_history_tier_points_check
        check (tier_points >= 0),

    constraint loyalty_level_history_actual_change_check
        check (
            previous_level_code is null
            or previous_level_code <> new_level_code
        )
);


create index if not exists loyalty_level_history_user_idx
on public.loyalty_level_history (
    user_id,
    created_at desc,
    id desc
);


create table if not exists public.gamification_notification (
    id text primary key
        default (gen_random_uuid())::text,

    user_id text not null
        references public.users(id)
        on update cascade
        on delete restrict,

    event_id text
        references public.gamification_event(id)
        on update cascade
        on delete restrict,

    notification_type
        public."GamificationNotificationType" not null,

    points integer not null
        default 0,

    title text,
    subtitle text,

    display_priority integer not null
        default 100,

    payload jsonb not null
        default '{}'::jsonb,

    seen_at timestamptz,
    displayed_at timestamptz,

    created_at timestamptz not null
        default now(),

    constraint gamification_notification_points_check
        check (points >= 0),

    constraint gamification_notification_priority_check
        check (display_priority >= 0),

    constraint gamification_notification_payload_object_check
        check (jsonb_typeof(payload) = 'object')
);


create unique index if not exists
    gamification_notification_event_type_unique
on public.gamification_notification (
    event_id,
    notification_type
)
where event_id is not null;


create index if not exists gamification_notification_inbox_idx
on public.gamification_notification (
    user_id,
    displayed_at,
    display_priority,
    created_at,
    id
);


/* =========================================================
 * UPDATE AND APPEND-ONLY PROTECTION
 * ========================================================= */

create or replace function public.set_gamification_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    new.updated_at := now();
    return new;
end;
$$;


drop trigger if exists loyalty_level_updated_at_trigger
on public.loyalty_level;

create trigger loyalty_level_updated_at_trigger
before update on public.loyalty_level
for each row
execute function public.set_gamification_updated_at();


drop trigger if exists loyalty_program_config_updated_at_trigger
on public.loyalty_program_config;

create trigger loyalty_program_config_updated_at_trigger
before update on public.loyalty_program_config
for each row
execute function public.set_gamification_updated_at();


drop trigger if exists loyalty_rule_updated_at_trigger
on public.loyalty_rule;

create trigger loyalty_rule_updated_at_trigger
before update on public.loyalty_rule
for each row
execute function public.set_gamification_updated_at();


drop trigger if exists loyalty_account_updated_at_trigger
on public.loyalty_account;

create trigger loyalty_account_updated_at_trigger
before update on public.loyalty_account
for each row
execute function public.set_gamification_updated_at();


drop trigger if exists gamification_event_updated_at_trigger
on public.gamification_event;

create trigger gamification_event_updated_at_trigger
before update on public.gamification_event
for each row
execute function public.set_gamification_updated_at();


create or replace function public.prevent_loyalty_history_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    raise exception using
        errcode = '55000',
        message = format(
            '%s_IS_APPEND_ONLY',
            upper(tg_table_name)
        );
end;
$$;


drop trigger if exists loyalty_ledger_append_only_trigger
on public.loyalty_ledger;

create trigger loyalty_ledger_append_only_trigger
before update or delete on public.loyalty_ledger
for each row
execute function public.prevent_loyalty_history_mutation();


drop trigger if exists loyalty_level_history_append_only_trigger
on public.loyalty_level_history;

create trigger loyalty_level_history_append_only_trigger
before update or delete on public.loyalty_level_history
for each row
execute function public.prevent_loyalty_history_mutation();


/* =========================================================
 * SECURITY BASELINE
 *
 * Application access will be exposed through narrowly scoped RPCs.
 * The service-role processing function bypasses RLS.
 * ========================================================= */

alter table public.loyalty_level
    enable row level security;

alter table public.loyalty_program_config
    enable row level security;

alter table public.loyalty_rule
    enable row level security;

alter table public.loyalty_rule_band
    enable row level security;

alter table public.loyalty_account
    enable row level security;

alter table public.gamification_event
    enable row level security;

alter table public.loyalty_cap_usage
    enable row level security;

alter table public.loyalty_ledger
    enable row level security;

alter table public.loyalty_level_history
    enable row level security;

alter table public.gamification_notification
    enable row level security;


revoke all on table public.loyalty_level
from anon, authenticated;

revoke all on table public.loyalty_program_config
from anon, authenticated;

revoke all on table public.loyalty_rule
from anon, authenticated;

revoke all on table public.loyalty_rule_band
from anon, authenticated;

revoke all on table public.loyalty_account
from anon, authenticated;

revoke all on table public.gamification_event
from anon, authenticated;

revoke all on table public.loyalty_cap_usage
from anon, authenticated;

revoke all on table public.loyalty_ledger
from anon, authenticated;

revoke all on table public.loyalty_level_history
from anon, authenticated;

revoke all on table public.gamification_notification
from anon, authenticated;

