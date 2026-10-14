/* Enable the scheduling extensions. */

create extension if not exists pg_cron
with schema pg_catalog;

create extension if not exists pg_net
with schema extensions;


/* Schedule the Edge Function every minute. */

select cron.schedule(
  'update-fiat-prices',
  '* * * * *',
  $cron$
    select net.http_post(
      url := (
        select decrypted_secret
        from vault.decrypted_secrets
        where name = 'project_url'
      ) || '/functions/v1/update-fiat-prices',

      headers := jsonb_build_object(
        'Content-Type',
        'application/json',

        'x-cron-secret',
        (
          select decrypted_secret
          from vault.decrypted_secrets
          where name =
            'fiat_price_cron_secret'
        )
      ),

      body := '{}'::jsonb
    );
  $cron$
);