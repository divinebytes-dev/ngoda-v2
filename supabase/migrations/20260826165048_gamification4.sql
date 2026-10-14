/*
 * Ngoda Gamification - Authenticated Customer Read RPCs
 *
 * Run after 03_points_and_tier_engine.sql.
 */


/* =========================================================
 * LOYALTY SUMMARY AND TIER PROGRESS
 * ========================================================= */

create or replace function public.fetch_my_loyalty_summary()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    v_user_id text;
    v_account public.loyalty_account%rowtype;
    v_level public.loyalty_level%rowtype;
    v_next_level public.loyalty_level%rowtype;

    v_available_points bigint := 0;
    v_tier_points bigint := 0;
    v_lifetime_earned_points bigint := 0;
    v_progress_points bigint := 0;
    v_level_span bigint;
    v_points_to_next bigint := 0;
    v_progress_percent numeric := 100;
begin
    v_user_id := auth.uid()::text;

    if v_user_id is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHENTICATED';
    end if;

    perform 1
    from public.users user_record
    where user_record.id = v_user_id
      and user_record.status::text = 'active';

    if not found then
        raise exception using
            errcode = '42501',
            message = 'USER_NOT_ACTIVE';
    end if;

    select account_record.*
    into v_account
    from public.loyalty_account account_record
    where account_record.user_id = v_user_id
      and account_record.is_active = true;

    if found then
        v_available_points := v_account.available_points;
        v_tier_points := v_account.tier_points;
        v_lifetime_earned_points :=
            v_account.lifetime_earned_points;

        select level_record.*
        into v_level
        from public.loyalty_level level_record
        where level_record.level_code = v_account.level_code
          and level_record.is_active = true;
    else
        select level_record.*
        into v_level
        from public.loyalty_level level_record
        where level_record.is_active = true
        order by
            level_record.min_tier_points,
            level_record.sort_order,
            level_record.id
        limit 1;
    end if;

    if not found then
        raise exception 'ACTIVE_LOYALTY_LEVEL_NOT_FOUND';
    end if;

    select level_record.*
    into v_next_level
    from public.loyalty_level level_record
    where level_record.is_active = true
      and level_record.min_tier_points > v_level.min_tier_points
    order by
        level_record.min_tier_points,
        level_record.sort_order,
        level_record.id
    limit 1;

    if found then
        v_progress_points := greatest(
            v_tier_points - v_level.min_tier_points,
            0
        );

        v_level_span :=
            v_next_level.min_tier_points -
            v_level.min_tier_points;

        v_points_to_next := greatest(
            v_next_level.min_tier_points - v_tier_points,
            0
        );

        v_progress_percent :=
            case
                when v_level_span <= 0 then 100
                else least(
                    round(
                        (
                            v_progress_points::numeric /
                            v_level_span::numeric
                        ) * 100,
                        2
                    ),
                    100
                )
            end;
    else
        v_progress_points := 0;
        v_points_to_next := 0;
        v_progress_percent := 100;
    end if;

    return jsonb_build_object(
        'user_id', v_user_id,
        'account_id', v_account.id,
        'available_points', v_available_points,
        'tier_points', v_tier_points,
        'lifetime_earned_points', v_lifetime_earned_points,
        'level', jsonb_build_object(
            'code', v_level.level_code,
            'name', v_level.name,
            'min_tier_points', v_level.min_tier_points,
            'max_tier_points', v_level.max_tier_points,
            'sort_order', v_level.sort_order,
            'benefits', v_level.benefits
        ),
        'next_level',
            case
                when v_next_level.id is null then null
                else jsonb_build_object(
                    'code', v_next_level.level_code,
                    'name', v_next_level.name,
                    'min_tier_points',
                        v_next_level.min_tier_points,
                    'max_tier_points',
                        v_next_level.max_tier_points,
                    'sort_order', v_next_level.sort_order,
                    'benefits', v_next_level.benefits
                )
            end,
        'progress', jsonb_build_object(
            'points_in_current_level', v_progress_points,
            'points_to_next_level', v_points_to_next,
            'percent', v_progress_percent,
            'is_highest_level', v_next_level.id is null
        ),
        'last_event_at', v_account.last_event_at,
        'updated_at', v_account.updated_at
    );
end;
$$;


/* =========================================================
 * PAGINATED LEDGER HISTORY
 * ========================================================= */

create or replace function public.fetch_my_loyalty_ledger(
    p_page integer default 1,
    p_page_size integer default 50
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    v_user_id text;
    v_offset integer;
    v_total_entries bigint := 0;
    v_total_pages integer := 1;
    v_rows jsonb := '[]'::jsonb;
begin
    v_user_id := auth.uid()::text;

    if v_user_id is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHENTICATED';
    end if;

    if p_page is null or p_page < 1 then
        raise exception 'INVALID_PAGE';
    end if;

    if p_page_size is null
       or p_page_size < 1
       or p_page_size > 100
    then
        raise exception 'INVALID_PAGE_SIZE';
    end if;

    v_offset := (p_page - 1) * p_page_size;

    select count(*)::bigint
    into v_total_entries
    from public.loyalty_ledger ledger_record
    where ledger_record.user_id = v_user_id;

    select coalesce(
        jsonb_agg(
            jsonb_build_object(
                'id', ledger_record.id,
                'event_id', ledger_record.event_id,
                'ledger_type', ledger_record.ledger_type,
                'event_type', ledger_record.event_type,
                'points_delta', ledger_record.points_delta,
                'available_balance_after',
                    ledger_record.available_balance_after,
                'tier_points_delta',
                    ledger_record.tier_points_delta,
                'tier_balance_after',
                    ledger_record.tier_balance_after,
                'source_reference',
                    ledger_record.source_reference,
                'description', ledger_record.description,
                'reversal_of_ledger_id',
                    ledger_record.reversal_of_ledger_id,
                'metadata', ledger_record.metadata,
                'created_at', ledger_record.created_at
            )
            order by
                ledger_record.created_at desc,
                ledger_record.id desc
        ),
        '[]'::jsonb
    )
    into v_rows
    from (
        select ledger_source.*
        from public.loyalty_ledger ledger_source
        where ledger_source.user_id = v_user_id
        order by
            ledger_source.created_at desc,
            ledger_source.id desc
        limit p_page_size
        offset v_offset
    ) ledger_record;

    v_total_pages := greatest(
        ceil(
            v_total_entries::numeric /
            p_page_size::numeric
        )::integer,
        1
    );

    return jsonb_build_object(
        'rows', v_rows,
        'pagination', jsonb_build_object(
            'page', p_page,
            'page_size', p_page_size,
            'total_entries', v_total_entries,
            'total_pages', v_total_pages,
            'has_previous', p_page > 1,
            'has_next', p_page < v_total_pages
        )
    );
end;
$$;


/* =========================================================
 * UNDISPLAYED FLUTTER CELEBRATIONS
 * ========================================================= */

create or replace function public.fetch_my_gamification_notifications(
    p_limit integer default 20
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    v_user_id text;
    v_rows jsonb := '[]'::jsonb;
begin
    v_user_id := auth.uid()::text;

    if v_user_id is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHENTICATED';
    end if;

    if p_limit is null
       or p_limit < 1
       or p_limit > 50
    then
        raise exception 'INVALID_NOTIFICATION_LIMIT';
    end if;

    select coalesce(
        jsonb_agg(
            jsonb_build_object(
                'id', notification_record.id,
                'event_id', notification_record.event_id,
                'notification_type',
                    notification_record.notification_type,
                'points', notification_record.points,
                'title', notification_record.title,
                'subtitle', notification_record.subtitle,
                'display_priority',
                    notification_record.display_priority,
                'payload', notification_record.payload,
                'seen_at', notification_record.seen_at,
                'displayed_at', notification_record.displayed_at,
                'created_at', notification_record.created_at
            )
            order by
                notification_record.display_priority,
                notification_record.created_at,
                notification_record.id
        ),
        '[]'::jsonb
    )
    into v_rows
    from (
        select notification_source.*
        from public.gamification_notification notification_source
        where notification_source.user_id = v_user_id
          and notification_source.displayed_at is null
        order by
            notification_source.display_priority,
            notification_source.created_at,
            notification_source.id
        limit p_limit
    ) notification_record;

    return jsonb_build_object(
        'rows', v_rows,
        'count', jsonb_array_length(v_rows)
    );
end;
$$;


/* =========================================================
 * ACKNOWLEDGE A CELEBRATION
 * ========================================================= */

create or replace function public.acknowledge_my_gamification_notification(
    p_notification_id text,
    p_mark_seen boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_user_id text;
    v_notification_id text;
    v_notification public.gamification_notification%rowtype;
begin
    v_user_id := auth.uid()::text;

    if v_user_id is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHENTICATED';
    end if;

    v_notification_id :=
        nullif(btrim(p_notification_id), '');

    if v_notification_id is null then
        raise exception 'GAMIFICATION_NOTIFICATION_ID_REQUIRED';
    end if;

    if p_mark_seen is null then
        raise exception 'INVALID_GAMIFICATION_NOTIFICATION_SEEN_VALUE';
    end if;

    update public.gamification_notification
    set
        displayed_at = coalesce(displayed_at, now()),
        seen_at = case
            when p_mark_seen then coalesce(seen_at, now())
            else seen_at
        end
    where id::text = v_notification_id
      and user_id = v_user_id
    returning * into v_notification;

    if not found then
        raise exception 'GAMIFICATION_NOTIFICATION_NOT_FOUND';
    end if;

    return jsonb_build_object(
        'success', true,
        'notification_id', v_notification.id,
        'displayed_at', v_notification.displayed_at,
        'seen_at', v_notification.seen_at
    );
end;
$$;


/* =========================================================
 * EXECUTION SECURITY
 * ========================================================= */

revoke all on function public.fetch_my_loyalty_summary()
from public, anon;

grant execute on function public.fetch_my_loyalty_summary()
to authenticated;


revoke all on function public.fetch_my_loyalty_ledger(integer, integer)
from public, anon;

grant execute on function public.fetch_my_loyalty_ledger(integer, integer)
to authenticated;


revoke all on function public.fetch_my_gamification_notifications(integer)
from public, anon;

grant execute on function public.fetch_my_gamification_notifications(integer)
to authenticated;


revoke all on function
    public.acknowledge_my_gamification_notification(text, boolean)
from public, anon;

grant execute on function
    public.acknowledge_my_gamification_notification(text, boolean)
to authenticated;


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
      'fetch_my_loyalty_summary',
      'fetch_my_loyalty_ledger',
      'fetch_my_gamification_notifications',
      'acknowledge_my_gamification_notification'
  )
order by routine_name;

