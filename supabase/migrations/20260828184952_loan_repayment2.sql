update public.loyalty_rule
set
    calculation_type = 'amount_based',
    fixed_points = null,
    points_per_usd = 1,
    min_points_per_event = null,
    max_points_per_event = 250,
    multiplier = 0.7500,
    condition_config =
        '{"exclude_reversal": true, "exclude_liquidation": true}'::jsonb,
    updated_at = now()
where rule_code = 'loan_repayment_standard';