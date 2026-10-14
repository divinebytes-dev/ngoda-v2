DELETE FROM public.financial_behavior_rule;

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
  'NEUTRAL_V1',
  'neutral',
  'Neutral',
  'There is not enough qualifying activity to classify a financial behaviour.',
  1,
  '{
    "rule_type": "zero_activity"
  }'::jsonb
),

(
  'BALANCED_V1',
  'balanced',
  'Balanced',
  'The two strongest financial behaviours are close enough that there is no clear dominant behaviour.',
  10,
  '{
    "rule_type": "lead_gap",
    "maximum_lead_percentage": 10
  }'::jsonb
),

(
  'INVESTOR_V1',
  'investor',
  'Investor',
  'Investment is the dominant qualifying financial behaviour.',
  20,
  '{
    "rule_type": "dominant",
    "metric": "investment",
    "minimum_percentage": 30
  }'::jsonb
),

(
  'SAVER_V1',
  'saver',
  'Saver',
  'Saving is the dominant qualifying financial behaviour.',
  30,
  '{
    "rule_type": "dominant",
    "metric": "saving",
    "minimum_percentage": 30
  }'::jsonb
),

(
  'BORROWER_V1',
  'borrower',
  'Borrower',
  'Borrowing is the dominant qualifying financial behaviour.',
  40,
  '{
    "rule_type": "dominant",
    "metric": "borrowing",
    "minimum_percentage": 30
  }'::jsonb
),

(
  'SHOPPER_V1',
  'shopper',
  'Shopper',
  'Merchant spending is the dominant qualifying financial behaviour.',
  50,
  '{
    "rule_type": "dominant",
    "metric": "spending",
    "minimum_percentage": 30
  }'::jsonb
);