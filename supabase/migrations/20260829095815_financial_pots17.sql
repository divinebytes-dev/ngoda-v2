DROP POLICY IF EXISTS
user_financial_badge_select_own
ON public.user_financial_badge;


CREATE POLICY user_financial_badge_select_own
ON public.user_financial_badge
FOR SELECT
TO authenticated
USING (
  user_id = auth.uid()::text
);


DROP POLICY IF EXISTS
financial_pot_select_own
ON public.financial_pot;


CREATE POLICY financial_pot_select_own
ON public.financial_pot
FOR SELECT
TO authenticated
USING (
  user_id = auth.uid()::text
);


DROP POLICY IF EXISTS
financial_behavior_select_own
ON public.financial_behavior;


CREATE POLICY financial_behavior_select_own
ON public.financial_behavior
FOR SELECT
TO authenticated
USING (
  user_id = auth.uid()::text
);


GRANT USAGE
ON SCHEMA public
TO authenticated;


GRANT SELECT
ON public.financial_badge
TO authenticated;


GRANT SELECT
ON public.user_financial_badge
TO authenticated;


GRANT SELECT
ON public.financial_pot
TO authenticated;


GRANT SELECT
ON public.financial_behavior
TO authenticated;

GRANT USAGE
ON SCHEMA public
TO authenticated;


GRANT SELECT
ON public.financial_badge
TO authenticated;


GRANT SELECT
ON public.user_financial_badge
TO authenticated;


GRANT SELECT
ON public.financial_pot
TO authenticated;


GRANT SELECT
ON public.financial_behavior
TO authenticated;