create or replace function public.fetch_public_gold_price()
returns numeric
language sql
stable
security definer
set search_path to ''
as $function$
    select public.fetch_gold_price();
$function$;

alter function public.fetch_public_gold_price()
owner to postgres;

/*
 * Prevent clients from calling the underlying
 * security-invoker function directly.
 */
revoke all
on function public.fetch_gold_price()
from public, anon, authenticated;

/*
 * Only expose the controlled wrapper.
 */
revoke all
on function public.fetch_public_gold_price()
from public;

grant execute
on function public.fetch_public_gold_price()
to anon, authenticated;