CREATE UNIQUE INDEX IF NOT EXISTS
    agent_settlement_one_active_batch_per_currency
ON public.agent_settlement_batch (
    lower(
        btrim(country_code)
    ),
    lower(
        btrim(currency_code)
    )
)
WHERE status <>
      'settled'::public."SettlementStatus";