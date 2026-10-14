CREATE OR REPLACE FUNCTION public.fetch_device_tokens(
    p_country_code text,
    p_user_id text
)
RETURNS text[]
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$

    select
        case
            when exists (
                select 1
                from public.user_presence p
                where p.user_id =
                      p_user_id

                  and p.is_online =
                      true

                  and p.last_seen_at >
                      current_timestamp
                      - interval '2 minutes'
            )
            then
                array[]::text[]

            else
                coalesce(
                    (
                        select
                            array_agg(
                                distinct d.token
                            )
                        from public.device_tokens d
                        where d.user_id =
                              p_user_id

                          and lower(
                              btrim(d.country_code)
                          ) =
                              lower(
                                  btrim(
                                      p_country_code
                                  )
                              )

                          and d.token is not null

                          and btrim(
                              d.token
                          ) <> ''
                    ),
                    array[]::text[]
                )
        end;

$function$;