CREATE OR REPLACE FUNCTION public.fetch_active_operational_countries()
RETURNS TABLE(
    country_code text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
begin
    /*
     * This function is used by the liquidation cron
     * running with the service-role client.
     */
    if coalesce(
        auth.role(),
        ''
    ) <> 'service_role'
    then
        raise exception using
            errcode = '42501',
            message = 'SERVICE_ROLE_REQUIRED';
    end if;

    return query
    select
        lower(
            btrim(
                country_record.country_code
            )
        ) as country_code

    from public.operational_country
        country_record

    where country_record.is_active =
              true

      and nullif(
          btrim(
              country_record.country_code
          ),
          ''
      ) is not null

    order by
        lower(
            btrim(
                country_record.country_code
            )
        );
end;
$function$;
