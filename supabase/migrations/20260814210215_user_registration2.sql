create or replace function public.fetch_country_calling_code(
    p_country_code text
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_calling_code text;
begin
    select calling_code
      into v_calling_code
      from public.operational_country
     where country_code = lower(p_country_code);

    if v_calling_code is null then
        raise exception 'COUNTRY_CALLING_CODE_NOT_CONFIGURED';
    end if;

    return v_calling_code;
end;
$$;