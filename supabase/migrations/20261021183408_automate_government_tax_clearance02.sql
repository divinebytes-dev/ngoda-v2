BEGIN;

SELECT cron.schedule(
    'monthly-government-tax-batches',
    '0 1 1 * *',
    'SELECT public.run_monthly_government_tax_batches();'
);

COMMIT;