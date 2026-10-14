INSERT INTO public.financial_behavior_rule (
  code,
  behavior,
  name,
  description,
  priority,
  conditions
)
VALUES

(
  'BALANCED_V1',
  'balanced',
  'Balanced',
  'The main financial allocations are close enough that there is no clear dominant behaviour.',
  10,
  '{
    "rule_type": "spread",
    "included_pots": [
      "spending",
      "saving",
      "investment"
    ],
    "maximum_spread_percentage": 10
  }'::jsonb
),

(
  'INVESTOR_V1',
  'investor',
  'Investor',
  'Investment is the dominant financial behaviour for the period.',
  20,
  '{
    "rule_type": "dominant",
    "dominant_pot": "investment",
    "minimum_percentage": 30
  }'::jsonb
),

(
  'SAVER_V1',
  'saver',
  'Saver',
  'Saving is the dominant financial behaviour for the period.',
  30,
  '{
    "rule_type": "dominant",
    "dominant_pot": "saving",
    "minimum_percentage": 30
  }'::jsonb
),

(
  'SHOPPER_V1',
  'shopper',
  'Shopper',
  'Merchant spending is the dominant financial behaviour for the period.',
  40,
  '{
    "rule_type": "dominant",
    "dominant_pot": "spending",
    "minimum_percentage": 30
  }'::jsonb
)

ON CONFLICT (code)
DO UPDATE SET
  behavior = EXCLUDED.behavior,
  name = EXCLUDED.name,
  description = EXCLUDED.description,
  priority = EXCLUDED.priority,
  conditions = EXCLUDED.conditions,
  is_active = true,
  updated_at = now();