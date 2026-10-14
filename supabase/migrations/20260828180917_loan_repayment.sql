/*
 * Trusted context required by the Loan Repayment loyalty publisher.
 * The authenticated caller is resolved inside PostgreSQL; the Edge Function
 * must not accept the loyalty beneficiary or country from the request body.
 */

begin;

create or replace function public.fetch_my_loan_repayment_context()
returns table (
    user_id text,
    country_code text
)
language plpgsql
security definer
set search_path = ''
as $function$
declare
    v_user public.users%rowtype;
begin
    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHORIZED';
    end if;

    if not public.has_role(
        array[
            'customer'::public."Role",
            'agent'::public."Role",
            'vendor'::public."Role"
        ]::public."Role"[]
    ) then
        raise exception using
            errcode = '42501',
            message = 'FORBIDDEN';
    end if;

    select user_record.*
    into v_user
    from public.users user_record
    where user_record.id = auth.uid()::text
    limit 1;

    if not found then
        raise exception 'USER_NOT_FOUND';
    end if;

    if v_user.status <>
       'active'::public."UserStatus"
    then
        raise exception 'USER_NOT_ACTIVE';
    end if;

    if v_user.country_code is null
       or btrim(v_user.country_code) = ''
    then
        raise exception
            'USER_COUNTRY_NOT_CONFIGURED';
    end if;

    return query
    select
        v_user.id,
        lower(btrim(v_user.country_code));
end;
$function$;

revoke all
on function public.fetch_my_loan_repayment_context()
from public;

revoke all
on function public.fetch_my_loan_repayment_context()
from anon;

grant execute
on function public.fetch_my_loan_repayment_context()
to authenticated;

commit;
