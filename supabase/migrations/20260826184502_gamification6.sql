/*
 * Ngoda Gamification - Badges
 *
 * Run after:
 *   01_core_schema.sql
 *   02_seed_core_configuration.sql
 *   03_points_and_tier_engine.sql
 *   04_customer_read_rpcs.sql
 *
 * Badge progress is evaluated from completed gamification events and the
 * authoritative loyalty account. A badge is awarded once and is permanent.
 */


do $$
begin
    create type public."LoyaltyBadgeCategory" as enum (
        'wallet',
        'gold',
        'lending',
        'community',
        'merchant',
        'agent'
    );
exception
    when duplicate_object then null;
end;
$$;


do $$
begin
    create type public."LoyaltyBadgeCriteriaType" as enum (
        'event_count',
        'lifetime_points',
        'tier_points',
        'available_points'
    );
exception
    when duplicate_object then null;
end;
$$;


create table if not exists public.loyalty_badge (
    id text primary key
        default (gen_random_uuid())::text,

    badge_code text not null unique,
    name text not null,
    description text not null,

    category public."LoyaltyBadgeCategory" not null,
    criteria_type public."LoyaltyBadgeCriteriaType" not null,
    event_type public."LoyaltyEventType",
    target_value bigint not null,

    icon_key text not null,
    sort_order integer not null,
    criteria_config jsonb not null default '{}'::jsonb,

    is_secret boolean not null default false,
    is_active boolean not null default true,
    valid_from timestamptz,
    valid_until timestamptz,

    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),

    constraint loyalty_badge_code_check
        check (
            badge_code = lower(btrim(badge_code))
            and badge_code ~ '^[a-z][a-z0-9_]*$'
        ),

    constraint loyalty_badge_text_check
        check (
            nullif(btrim(name), '') is not null
            and nullif(btrim(description), '') is not null
            and nullif(btrim(icon_key), '') is not null
        ),

    constraint loyalty_badge_target_check
        check (target_value >= 1),

    constraint loyalty_badge_sort_check
        check (sort_order >= 1),

    constraint loyalty_badge_criteria_check
        check (
            (
                criteria_type = 'event_count'
                and event_type is not null
            )
            or (
                criteria_type <> 'event_count'
                and event_type is null
            )
        ),

    constraint loyalty_badge_config_check
        check (jsonb_typeof(criteria_config) = 'object'),

    constraint loyalty_badge_dates_check
        check (
            valid_until is null
            or valid_from is null
            or valid_until > valid_from
        )
);


create unique index if not exists loyalty_badge_sort_unique
on public.loyalty_badge (sort_order);


create index if not exists loyalty_badge_evaluation_idx
on public.loyalty_badge (
    is_active,
    criteria_type,
    event_type,
    sort_order
);


create table if not exists public.loyalty_badge_progress (
    id text primary key
        default (gen_random_uuid())::text,

    user_id text not null
        references public.users(id)
        on update cascade
        on delete restrict,

    badge_id text not null
        references public.loyalty_badge(id)
        on update cascade
        on delete restrict,

    current_value bigint not null default 0,
    target_value bigint not null,
    completed_at timestamptz,

    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),

    constraint loyalty_badge_progress_value_check
        check (
            current_value >= 0
            and target_value >= 1
        ),

    constraint loyalty_badge_progress_unique
        unique (user_id, badge_id)
);


create index if not exists loyalty_badge_progress_user_idx
on public.loyalty_badge_progress (
    user_id,
    completed_at,
    updated_at desc
);


create table if not exists public.user_badge (
    id text primary key
        default (gen_random_uuid())::text,

    user_id text not null
        references public.users(id)
        on update cascade
        on delete restrict,

    badge_id text not null
        references public.loyalty_badge(id)
        on update cascade
        on delete restrict,

    awarded_event_id text
        references public.gamification_event(id)
        on update cascade
        on delete restrict,

    awarded_at timestamptz not null default now(),
    metadata jsonb not null default '{}'::jsonb,

    constraint user_badge_metadata_check
        check (jsonb_typeof(metadata) = 'object'),

    constraint user_badge_unique
        unique (user_id, badge_id)
);


create index if not exists user_badge_user_history_idx
on public.user_badge (
    user_id,
    awarded_at desc,
    id desc
);


drop trigger if exists loyalty_badge_updated_at_trigger
on public.loyalty_badge;

create trigger loyalty_badge_updated_at_trigger
before update on public.loyalty_badge
for each row
execute function public.set_gamification_updated_at();


drop trigger if exists loyalty_badge_progress_updated_at_trigger
on public.loyalty_badge_progress;

create trigger loyalty_badge_progress_updated_at_trigger
before update on public.loyalty_badge_progress
for each row
execute function public.set_gamification_updated_at();


drop trigger if exists user_badge_append_only_trigger
on public.user_badge;

create trigger user_badge_append_only_trigger
before update or delete on public.user_badge
for each row
execute function public.prevent_loyalty_history_mutation();


/* =========================================================
 * INITIAL BADGE CATALOGUE
 * ========================================================= */

insert into public.loyalty_badge (
    badge_code,
    name,
    description,
    category,
    criteria_type,
    event_type,
    target_value,
    icon_key,
    sort_order
)
values
    (
        'first_deposit',
        'First Deposit',
        'Complete your first successful wallet deposit.',
        'wallet',
        'event_count',
        'user_deposit',
        1,
        'account_balance_wallet',
        10
    ),
    (
        'first_transfer',
        'First Transfer',
        'Complete your first successful wallet transfer.',
        'wallet',
        'event_count',
        'user_transfer',
        1,
        'swap_horiz',
        20
    ),
    (
        'first_merchant_payment',
        'First Merchant Payment',
        'Make your first successful merchant payment.',
        'merchant',
        'event_count',
        'merchant_payment',
        1,
        'storefront',
        30
    ),
    (
        'first_gold_purchase',
        'First Gold Purchase',
        'Complete your first successful Gold purchase.',
        'gold',
        'event_count',
        'gold_token_buy',
        1,
        'diamond',
        40
    ),
    (
        'gold_saver',
        'Gold Saver',
        'Complete ten successful Gold purchases.',
        'gold',
        'event_count',
        'gold_token_buy',
        10,
        'savings',
        50
    ),
    (
        'responsible_borrower',
        'Responsible Borrower',
        'Complete your first successful SVA repayment.',
        'lending',
        'event_count',
        'loan_repayment',
        1,
        'verified',
        60
    ),
    (
        'referral_champion',
        'Referral Champion',
        'Complete five successful customer referrals.',
        'community',
        'event_count',
        'referral_completed',
        5,
        'groups',
        70
    ),
    (
        'points_collector',
        'Points Collector',
        'Earn 5,000 lifetime loyalty points.',
        'wallet',
        'lifetime_points',
        null,
        5000,
        'stars',
        80
    )
on conflict (badge_code) do update
set
    name = excluded.name,
    description = excluded.description,
    category = excluded.category,
    criteria_type = excluded.criteria_type,
    event_type = excluded.event_type,
    target_value = excluded.target_value,
    icon_key = excluded.icon_key,
    sort_order = excluded.sort_order,
    is_active = true;


/* =========================================================
 * BADGE EVALUATION
 * ========================================================= */

create or replace function public.evaluate_user_badges(
    p_user_id text,
    p_event_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_user_id text;
    v_event_id text;
    v_badge public.loyalty_badge%rowtype;
    v_account public.loyalty_account%rowtype;
    v_current_value bigint;
    v_awarded public.user_badge%rowtype;
    v_evaluated integer := 0;
    v_newly_awarded integer := 0;
    v_badges jsonb := '[]'::jsonb;
begin
    if coalesce(auth.role(), '') <> 'service_role' then
        raise exception using
            errcode = '42501',
            message = 'SERVICE_ROLE_REQUIRED';
    end if;

    v_user_id := nullif(btrim(p_user_id), '');
    v_event_id := nullif(btrim(p_event_id), '');

    if v_user_id is null then
        raise exception 'BADGE_USER_ID_REQUIRED';
    end if;

    perform pg_advisory_xact_lock(
        hashtext('loyalty-badge:' || v_user_id)
    );

    select account_record.*
    into v_account
    from public.loyalty_account account_record
    where account_record.user_id = v_user_id;

    if not found then
        raise exception 'LOYALTY_ACCOUNT_NOT_FOUND';
    end if;

    for v_badge in
        select badge_record.*
        from public.loyalty_badge badge_record
        where badge_record.is_active = true
          and (
              badge_record.valid_from is null
              or badge_record.valid_from <= now()
          )
          and (
              badge_record.valid_until is null
              or badge_record.valid_until > now()
          )
        order by badge_record.sort_order, badge_record.id
    loop
        v_evaluated := v_evaluated + 1;

        v_current_value :=
            case v_badge.criteria_type
                when 'event_count' then (
                    select count(*)::bigint
                    from public.gamification_event event_record
                    where event_record.user_id = v_user_id
                      and event_record.event_type = v_badge.event_type
                      and event_record.status =
                          'completed'::public."GamificationEventStatus"
                )
                when 'lifetime_points' then
                    v_account.lifetime_earned_points
                when 'tier_points' then
                    v_account.tier_points
                when 'available_points' then
                    greatest(v_account.available_points, 0)
            end;

        v_current_value := greatest(coalesce(v_current_value, 0), 0);

        insert into public.loyalty_badge_progress (
            user_id,
            badge_id,
            current_value,
            target_value,
            completed_at
        )
        values (
            v_user_id,
            v_badge.id,
            v_current_value,
            v_badge.target_value,
            case
                when v_current_value >= v_badge.target_value then now()
                else null
            end
        )
        on conflict (user_id, badge_id) do update
        set
            current_value = excluded.current_value,
            target_value = excluded.target_value,
            completed_at = coalesce(
                public.loyalty_badge_progress.completed_at,
                excluded.completed_at
            );

        if v_current_value < v_badge.target_value then
            continue;
        end if;

        v_awarded := null;

        insert into public.user_badge (
            user_id,
            badge_id,
            awarded_event_id,
            metadata
        )
        values (
            v_user_id,
            v_badge.id,
            v_event_id,
            jsonb_build_object(
                'current_value', v_current_value,
                'target_value', v_badge.target_value
            )
        )
        on conflict (user_id, badge_id) do nothing
        returning * into v_awarded;

        if v_awarded.id is null then
            continue;
        end if;

        v_newly_awarded := v_newly_awarded + 1;
        v_badges := v_badges || jsonb_build_array(
            jsonb_build_object(
                'badge_code', v_badge.badge_code,
                'name', v_badge.name,
                'awarded_at', v_awarded.awarded_at
            )
        );

        /*
         * event_id is intentionally null here. The existing notification
         * uniqueness contract allows one notification of each type per event,
         * while one event may unlock more than one badge. user_badge provides
         * the durable idempotency contract for badge notifications.
         */
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
            null,
            'badge_awarded'::public."GamificationNotificationType",
            0,
            'Badge unlocked',
            v_badge.name,
            20,
            jsonb_build_object(
                'user_badge_id', v_awarded.id,
                'badge_id', v_badge.id,
                'badge_code', v_badge.badge_code,
                'name', v_badge.name,
                'description', v_badge.description,
                'category', v_badge.category,
                'icon_key', v_badge.icon_key,
                'source_event_id', v_event_id
            )
        );
    end loop;

    return jsonb_build_object(
        'success', true,
        'user_id', v_user_id,
        'evaluated', v_evaluated,
        'newly_awarded', v_newly_awarded,
        'badges', v_badges
    );
end;
$$;


create or replace function public.evaluate_badges_after_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    perform public.evaluate_user_badges(new.user_id, new.id);
    return new;
exception
    when others then
        raise warning 'BADGE_EVALUATION_FAILED event_id=% user_id=% error=%',
            new.id,
            new.user_id,
            sqlerrm;
        return new;
end;
$$;


drop trigger if exists gamification_event_badge_evaluation_trigger
on public.gamification_event;

create trigger gamification_event_badge_evaluation_trigger
after update of status on public.gamification_event
for each row
when (
    new.status = 'completed'::public."GamificationEventStatus"
    and old.status is distinct from new.status
)
execute function public.evaluate_badges_after_event();


/*
 * Initialize progress from completed historical events without generating
 * old celebration notifications. This makes the catalogue correct as soon as
 * the migration is installed.
 */
with calculated_progress as materialized (
    select
        account_record.user_id,
        badge_record.id as badge_id,
        badge_record.target_value,
        greatest(
            case badge_record.criteria_type
                when 'event_count' then (
                    select count(*)::bigint
                    from public.gamification_event event_record
                    where event_record.user_id = account_record.user_id
                      and event_record.event_type = badge_record.event_type
                      and event_record.status =
                          'completed'::public."GamificationEventStatus"
                )
                when 'lifetime_points' then
                    account_record.lifetime_earned_points
                when 'tier_points' then
                    account_record.tier_points
                when 'available_points' then
                    greatest(account_record.available_points, 0)
            end,
            0
        )::bigint as current_value
    from public.loyalty_account account_record
    cross join public.loyalty_badge badge_record
    where badge_record.is_active = true
)
insert into public.loyalty_badge_progress (
    user_id,
    badge_id,
    current_value,
    target_value,
    completed_at
)
select
    progress_record.user_id,
    progress_record.badge_id,
    progress_record.current_value,
    progress_record.target_value,
    case
        when progress_record.current_value >= progress_record.target_value
            then now()
        else null
    end
from calculated_progress progress_record
on conflict (user_id, badge_id) do update
set
    current_value = excluded.current_value,
    target_value = excluded.target_value,
    completed_at = coalesce(
        public.loyalty_badge_progress.completed_at,
        excluded.completed_at
    );


insert into public.user_badge (
    user_id,
    badge_id,
    awarded_event_id,
    metadata
)
select
    progress_record.user_id,
    progress_record.badge_id,
    null,
    jsonb_build_object(
        'historical_backfill', true,
        'current_value', progress_record.current_value,
        'target_value', progress_record.target_value
    )
from public.loyalty_badge_progress progress_record
where progress_record.current_value >= progress_record.target_value
on conflict (user_id, badge_id) do nothing;


/* =========================================================
 * CUSTOMER READ RPC
 * ========================================================= */

create or replace function public.fetch_my_loyalty_badges()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    v_user_id text;
    v_rows jsonb := '[]'::jsonb;
    v_total integer := 0;
    v_earned integer := 0;
begin
    v_user_id := auth.uid()::text;

    if v_user_id is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHENTICATED';
    end if;

    with badge_rows as materialized (
        select
            badge_record.id,
            badge_record.badge_code,
            badge_record.name,
            badge_record.description,
            badge_record.category::text as category,
            badge_record.icon_key,
            badge_record.sort_order,
            badge_record.is_secret,
            user_badge_record.id as user_badge_id,
            user_badge_record.awarded_at,
            user_badge_record.id is not null as is_earned,
            least(
                coalesce(progress_record.current_value, 0),
                badge_record.target_value
            ) as current_value,
            badge_record.target_value,
            least(
                round(
                    (
                        least(
                            coalesce(progress_record.current_value, 0),
                            badge_record.target_value
                        )::numeric /
                        badge_record.target_value::numeric
                    ) * 100,
                    2
                ),
                100
            ) as progress_percent
        from public.loyalty_badge badge_record
        left join public.loyalty_badge_progress progress_record
          on progress_record.badge_id = badge_record.id
         and progress_record.user_id = v_user_id
        left join public.user_badge user_badge_record
          on user_badge_record.badge_id = badge_record.id
         and user_badge_record.user_id = v_user_id
        where badge_record.is_active = true
          and (
              badge_record.valid_from is null
              or badge_record.valid_from <= now()
          )
          and (
              badge_record.valid_until is null
              or badge_record.valid_until > now()
          )
          and (
              badge_record.is_secret = false
              or user_badge_record.id is not null
          )
    )
    select
        count(*)::integer,
        count(*) filter (where badge_row.is_earned)::integer,
        coalesce(
            jsonb_agg(
                to_jsonb(badge_row)
                order by
                    badge_row.is_earned desc,
                    badge_row.sort_order,
                    badge_row.id
            ),
            '[]'::jsonb
        )
    into v_total, v_earned, v_rows
    from badge_rows badge_row;

    return jsonb_build_object(
        'rows', v_rows,
        'summary', jsonb_build_object(
            'total', v_total,
            'earned', v_earned,
            'remaining', greatest(v_total - v_earned, 0)
        )
    );
end;
$$;


/* =========================================================
 * SECURITY
 * ========================================================= */

alter table public.loyalty_badge enable row level security;
alter table public.loyalty_badge_progress enable row level security;
alter table public.user_badge enable row level security;

revoke all on table public.loyalty_badge from anon, authenticated;
revoke all on table public.loyalty_badge_progress from anon, authenticated;
revoke all on table public.user_badge from anon, authenticated;

revoke all on function public.evaluate_user_badges(text, text)
from public, anon, authenticated;

grant execute on function public.evaluate_user_badges(text, text)
to service_role;

revoke all on function public.evaluate_badges_after_event()
from public, anon, authenticated;

revoke all on function public.fetch_my_loyalty_badges()
from public, anon;

grant execute on function public.fetch_my_loyalty_badges()
to authenticated;
