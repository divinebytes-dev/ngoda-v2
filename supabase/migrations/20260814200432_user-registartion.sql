create or replace function public.get_next_wallet_index()
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
begin
  return nextval(
    'public.wallet_index_seq'::regclass
  );
end;
$$;


create or replace function public.create_customer_profile(
  p_user_id uuid,
  p_country_code text,
  p_phone text,
  p_email text,
  p_wallet_address text,
  p_wallet_index bigint,
  p_referral_code text,
  p_upliner_code text default null
)
returns public.users
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role_id uuid;
  v_upliner text;
  v_user public.users%rowtype;
begin
  select id
  into v_role_id
  from public.user_role
  where name = 'customer'
  limit 1;

  if v_role_id is null then
    raise exception 'ROLE_NOT_CONFIGURED';
  end if;

  v_upliner := null;

  if nullif(trim(p_upliner_code), '') is not null then
    select referral_code
    into v_upliner
    from public.users
    where referral_code = trim(p_upliner_code)
    limit 1;
  end if;

  insert into public.users (
    id,
    email,
    phone,
    country_code,
    role_id,
    wallet_address,
    wallet_index,
    referral_code,
    upliner
  )
  values (
    p_user_id,
    nullif(trim(p_email), ''),
    trim(p_phone),
    lower(trim(p_country_code)),
    v_role_id,
    p_wallet_address,
    p_wallet_index,
    p_referral_code,
    v_upliner
  )
  returning *
  into v_user;

  return v_user;
end;
$$;