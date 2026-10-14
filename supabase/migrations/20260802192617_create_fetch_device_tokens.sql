create or replace function public.fetch_device_tokens(
    p_country_code text,
    p_user_id text
)
returns text[]
language sql
stable
as $$
    select coalesce(
        array_agg(d.token),
        array[]::text[]
    )
    from public.device_tokens d
    where d.user_id = p_user_id
      and d.country_code = p_country_code;
$$;