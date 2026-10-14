DROP INDEX IF EXISTS
    public.agent_settlement_one_active_batch_per_currency;

CREATE UNIQUE INDEX
    agent_settlement_one_active_batch_per_currency
ON public.agent_settlement_batch (
    lower(
        btrim(country_code)
    ),
    lower(
        btrim(currency_code)
    )
)
WHERE status IN (
    'draft'::public."SettlementStatus",
    'approved'::public."SettlementStatus"
);

