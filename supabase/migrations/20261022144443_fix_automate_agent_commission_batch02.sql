-- One execution each Monday: 01:00 UTC = 03:00 in current UTC+02 countries.
-- No every-minute job. Run in QA SQL editor as postgres.
BEGIN;
DO $check$
BEGIN
  IF current_user <> 'postgres' THEN RAISE EXCEPTION 'RUN_SCHEDULE_AS_POSTGRES'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_extension WHERE extname = 'pg_cron') THEN
    RAISE EXCEPTION 'PG_CRON_EXTENSION_REQUIRED';
  END IF;
  IF coalesce(current_setting('cron.timezone', true), 'GMT')
    NOT IN ('GMT','UTC','Etc/UTC') THEN RAISE EXCEPTION 'CRON_MUST_USE_UTC_FOR_THIS_SCHEDULE'; END IF;
  -- Validate the active-country zones for this fixed UTC schedule (winter
  -- and summer). Countries with other offsets need a separate schedule.
  IF EXISTS (
    SELECT 1 FROM public.operational_country c
    WHERE c.is_active AND (
      c.time_zone IS NULL OR
      NOT EXISTS (SELECT 1 FROM pg_catalog.pg_timezone_names t WHERE t.name = c.time_zone)
    )
  ) THEN RAISE EXCEPTION 'INVALID_ACTIVE_COUNTRY_TIME_ZONE'; END IF;
  IF EXISTS (
    SELECT 1 FROM public.operational_country c
    CROSS JOIN (VALUES (timestamp '2027-01-04 01:00'), (timestamp '2027-07-05 01:00')) d(utc_time)
    WHERE c.is_active AND
      ((d.utc_time AT TIME ZONE 'UTC') AT TIME ZONE c.time_zone) - d.utc_time <> interval '2 hours'
  ) THEN RAISE EXCEPTION 'ACTIVE_COUNTRY_REQUIRES_DIFFERENT_WEEKLY_SCHEDULE'; END IF;
END;
$check$;
SELECT cron.schedule(
  'weekly-agent-commission-batches', '0 1 * * 1',
  'SELECT public.run_weekly_agent_commission_batches();'
);
COMMIT;
