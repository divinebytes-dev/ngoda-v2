alter table public.operational_country
add column calling_code text;

update public.operational_country
set calling_code = '263'
where country_code = 'zw';

update public.operational_country
set calling_code = '27'
where country_code = 'za';

update public.operational_country
set calling_code = '267'
where country_code = 'bw';