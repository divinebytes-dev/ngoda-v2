BEGIN;

REVOKE ALL ON FUNCTION public.calculate_financial_behavior(
    text, text, text, integer, integer
)
FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.calculate_financial_behavior(
    text, text, text, integer, integer
)
TO service_role;


REVOKE ALL ON FUNCTION public.calculate_financial_behavior_snapshot(
    text, text, text, integer, integer,
    public.financial_behavior_scope
)
FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.calculate_financial_behavior_snapshot(
    text, text, text, integer, integer,
    public.financial_behavior_scope
)
TO service_role;


REVOKE ALL ON FUNCTION public.calculate_financial_pot_percentages(
    text, text, integer, integer
)
FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.calculate_financial_pot_percentages(
    text, text, integer, integer
)
TO service_role;

COMMIT;