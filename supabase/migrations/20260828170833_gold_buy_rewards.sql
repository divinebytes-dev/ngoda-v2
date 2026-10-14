/*
 * Ngoda Gamification - Initial Levels, Program Caps, and Points Rules
 *
 * Run after 01_core_schema.sql.
 * These are pilot values and remain configurable in the database.
 */

begin;


/* =========================================================
 * LEVELS
 *
 * Tier progression uses loyalty_account.tier_points.
 * Spending available points does not reduce tier_points.
 * ========================================================= */

insert into public.loyalty_level (
    level_code,
    name,
    min_tier_points,
    max_tier_points,
    sort_order,
    benefits,
    is_active
)
values
    (
        'bronze',
        'Bronze',
        0,
        4999,
        1,
        '{}'::jsonb,
        true
    ),
    (
        'silver',
        'Silver',
        5000,
        9999,
        2,
        '{}'::jsonb,
        true
    ),
    (
        'gold',
        'Gold',
        10000,
        14999,
        3,
        '{}'::jsonb,
        true
    ),
    (
        'platinum',
        'Platinum',
        15000,
        19999,
        4,
        '{}'::jsonb,
        true
    ),
    (
        'diamond',
        'Diamond',
        20000,
        null,
        5,
        '{}'::jsonb,
        true
    )
on conflict (level_code)
do update
set
    name = excluded.name,
    min_tier_points = excluded.min_tier_points,
    max_tier_points = excluded.max_tier_points,
    sort_order = excluded.sort_order,
    benefits = excluded.benefits,
    is_active = excluded.is_active;


/* =========================================================
 * GLOBAL PROGRAM CAPS
 * ========================================================= */

insert into public.loyalty_program_config (
    country_code,
    daily_points_cap,
    monthly_points_cap,
    points_expiry_months,
    is_active
)
select
    null,
    500,
    5000,
    null,
    true
where not exists (
    select 1
    from public.loyalty_program_config
    where country_code is null
      and is_active = true
);


/* =========================================================
 * INITIAL POINTS RULES
 *
 * All amount-based rules use the USD equivalent supplied by the
 * trusted backend event publisher.
 * ========================================================= */

insert into public.loyalty_rule (
    event_type,
    rule_code,
    rule_name,
    calculation_type,
    fixed_points,
    points_per_usd,
    min_points_per_event,
    max_points_per_event,
    daily_cap_points,
    monthly_cap_points,
    multiplier,
    priority,
    condition_config,
    is_active
)
values
    (
        'kyc_completed',
        'kyc_completed_standard',
        'KYC completed',
        'fixed',
        100,
        null,
        100,
        100,
        100,
        100,
        1,
        100,
        '{"once_per_user": true}'::jsonb,
        true
    ),
    (
        'user_deposit',
        'user_deposit_standard',
        'Successful user deposit',
        'amount_based',
        null,
        1,
        1,
        200,
        null,
        null,
        1,
        100,
        '{"exclude_test_transactions": true}'::jsonb,
        true
    ),
    (
        'user_transfer',
        'user_transfer_standard',
        'Successful user transfer',
        'fixed_plus_amount',
        2,
        0.25,
        2,
        50,
        150,
        null,
        1,
        100,
        '{"beneficiary": "sender", "exclude_self_transfer": true}'::jsonb,
        true
    ),
    (
        'merchant_payment',
        'merchant_payment_standard',
        'Successful merchant payment',
        'fixed_plus_amount',
        5,
        0.5,
        5,
        100,
        300,
        null,
        1,
        100,
        '{"beneficiary": "customer", "exclude_merchant_self_payment": true}'::jsonb,
        true
    ),
    (
        'gold_token_buy',
        'gold_token_buy_standard',
        'Successful Gold purchase',
        'fixed_plus_amount',
        5,
        1.5,
        5,
        300,
        500,
        null,
        1,
        100,
        '{"amount_basis": "gross_fiat_before_fee", "requires_completed_mint": true}'::jsonb,
        true
    ),
    (
        'gold_token_sell',
        'gold_token_sell_standard',
        'Gold sale - points disabled',
        'fixed_plus_amount',
        2,
        0.25,
        2,
        50,
        null,
        null,
        1,
        100,
        '{"campaign_multiplier_allowed": false}'::jsonb,
        false
    ),
    (
        'loan_repayment',
        'loan_repayment_standard',
        'Successful voluntary loan repayment',
        'fixed_plus_amount',
        10,
        1,
        10,
        250,
        null,
        null,
        1,
        100,
        '{"exclude_liquidation": true, "exclude_reversal": true}'::jsonb,
        true
    ),
    (
        'loan_repayment_on_time_bonus',
        'loan_repayment_on_time_bonus_standard',
        'On-time loan repayment bonus',
        'fixed',
        50,
        null,
        50,
        50,
        null,
        null,
        1,
        100,
        '{"requires_on_or_before_due_date": true}'::jsonb,
        true
    ),
    (
        'referral_completed',
        'referral_completed_standard',
        'Qualified referral completed',
        'fixed',
        250,
        null,
        250,
        250,
        null,
        2000,
        1,
        100,
        '{"requires_referred_kyc": true, "requires_first_successful_transaction": true}'::jsonb,
        true
    )
on conflict (rule_code)
do update
set
    event_type = excluded.event_type,
    rule_name = excluded.rule_name,
    calculation_type = excluded.calculation_type,
    fixed_points = excluded.fixed_points,
    points_per_usd = excluded.points_per_usd,
    min_points_per_event = excluded.min_points_per_event,
    max_points_per_event = excluded.max_points_per_event,
    daily_cap_points = excluded.daily_cap_points,
    monthly_cap_points = excluded.monthly_cap_points,
    multiplier = excluded.multiplier,
    priority = excluded.priority,
    condition_config = excluded.condition_config,
    is_active = excluded.is_active;


commit;


/* =========================================================
 * VERIFICATION
 * ========================================================= */

select
    level_code,
    name,
    min_tier_points,
    max_tier_points,
    sort_order,
    is_active
from public.loyalty_level
order by sort_order;


select
    event_type,
    rule_code,
    calculation_type,
    fixed_points,
    points_per_usd,
    min_points_per_event,
    max_points_per_event,
    daily_cap_points,
    monthly_cap_points,
    is_active
from public.loyalty_rule
order by event_type, priority, rule_code;
