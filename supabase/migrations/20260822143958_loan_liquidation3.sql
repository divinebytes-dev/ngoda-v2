CREATE OR REPLACE FUNCTION public.fetch_gold_rate_api()
RETURNS TABLE(rate_api text)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
begin
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
        btrim(
            currency_record.rate_api
        )
    from public.supported_currency
        currency_record
    where lower(
        btrim(
            currency_record.currency_code
        )
    ) = 'gold'

      and currency_record.is_active = true

      and nullif(
          btrim(
              currency_record.rate_api
          ),
          ''
      ) is not null
    limit 1;
end;
$function$;
