-- ============================================================
-- USER PRESENCE RLS
-- user_presence.user_id is TEXT
-- auth.uid() returns UUID
-- ============================================================

ALTER TABLE public.user_presence
ENABLE ROW LEVEL SECURITY;


-- ============================================================
-- REMOVE EXISTING POLICIES
-- ============================================================

DROP POLICY IF EXISTS "Users can view own presence"
ON public.user_presence;

DROP POLICY IF EXISTS "Users can update own presence"
ON public.user_presence;


-- ============================================================
-- SELECT
-- ============================================================

CREATE POLICY "Users can view own presence"
ON public.user_presence
FOR SELECT
TO authenticated
USING (
    user_id = auth.uid()::text
);


-- ============================================================
-- UPDATE
-- ============================================================

CREATE POLICY "Users can update own presence"
ON public.user_presence
FOR UPDATE
TO authenticated
USING (
    user_id = auth.uid()::text
)
WITH CHECK (
    user_id = auth.uid()::text
);


-- ============================================================
-- TABLE PRIVILEGES
-- ============================================================

GRANT SELECT, UPDATE
ON TABLE public.user_presence
TO authenticated;