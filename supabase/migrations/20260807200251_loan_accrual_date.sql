create or replace function public.fetch_my_last_loan_interest_accrual()
returns table (
    last_accrual_run timestamptz
)
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
    v_user public.users%rowtype;
    v_last_accrual_run timestamptz;
begin
    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHENTICATED';
    end if;

    /*
     * Preserve the original authorization:
     * only finance users may access this information.
     */
    if not public.has_role(
        array[
            'finance'
        ]::text[]
    ) then
        raise exception using
            errcode = '42501',
            message = 'FORBIDDEN';
    end if;

    v_user :=
        public.fetch_user_by_id(
            auth.uid()::text
        );

    if v_user.id is null then
        raise exception
            'USER_NOT_FOUND';
    end if;

    if v_user.country_code is null then
        raise exception
            'USER_COUNTRY_NOT_CONFIGURED';
    end if;

    select max(
        loan_entry_record.created_at
    )
    into v_last_accrual_run
    from public.loan_entry
        loan_entry_record
    where loan_entry_record.country_code =
          v_user.country_code
      and loan_entry_record.entry_type =
          'interest_accrual'::public."LoanEntryType"
      and loan_entry_record.debit_interest > 0;

    return query
    select v_last_accrual_run;
end;
$function$;


revoke all on function
    public.fetch_my_last_loan_interest_accrual()
from public;

revoke all on function
    public.fetch_my_last_loan_interest_accrual()
from anon;

grant execute on function
    public.fetch_my_last_loan_interest_accrual()
to authenticated;