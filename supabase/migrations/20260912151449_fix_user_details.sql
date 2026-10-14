create type public."GenderType" as enum (
  'male',
  'female',
  'prefer_not_to_say'
);


alter table public.users
add column if not exists gender public."GenderType" null,
add column if not exists city text null,
add column if not exists province_state text null;

alter table public.users
rename column address to residential_address;


alter table public.user_kyc
rename column document_type to id_type;

alter table public.user_kyc
rename column document_number to id_number;

alter table public.user_kyc
rename column verification_status to kyc_status;

alter table public.user_kyc
add column if not exists expiry_date date null,
add column if not exists occupation text null,
add column if not exists source_of_funds text null,
add column if not exists tax_number text null;

create unique index if not exists user_kyc_user_id_key
on public.user_kyc (user_id);
