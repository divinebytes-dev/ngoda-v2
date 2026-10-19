-- Existing Supabase publication required; table policies are handled separately.
BEGIN;
DO $realtime$
DECLARE t text; all_tables boolean;
BEGIN
  SELECT puballtables INTO all_tables FROM pg_publication WHERE pubname='supabase_realtime';
  IF NOT FOUND THEN RAISE EXCEPTION 'SUPABASE_REALTIME_PUBLICATION_MISSING'; END IF;
  IF NOT all_tables THEN
    FOREACH t IN ARRAY ARRAY['notifications','transaction_state'] LOOP
      IF NOT EXISTS (SELECT 1 FROM pg_publication_tables
        WHERE pubname='supabase_realtime' AND schemaname='public' AND tablename=t)
      THEN
        EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I',t);
      END IF;
    END LOOP;
  END IF;
END;
$realtime$;
COMMIT;
