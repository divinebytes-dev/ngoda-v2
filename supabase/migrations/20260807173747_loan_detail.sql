/*
 * ============================================================
 * AUTHENTICATED ACTIVE LOAN DETAIL
 * ============================================================
 */

create or replace function public.fetch_my_active_loan_detail(
    p_loan_id text
)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
    v_user public.users%rowtype;
    v_loan public.loan%rowtype;

    v_entries jsonb := '[]'::jsonb;

    v_debit_principal numeric := 0;
    v_credit_principal numeric := 0;
    v_debit_interest numeric := 0;
    v_credit_interest numeric := 0;

    v_principal_balance numeric := 0;
    v_interest_balance numeric := 0;
    v_outstanding_balance numeric := 0;
begin
    /*
     * Authenticate and authorize customer.
     */
    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHORIZED';
    end if;

    if not public.has_role(
        array[
            'customer'
        ]::text[]
    ) then
        raise exception using
            errcode = '42501',
            message = 'FORBIDDEN';
    end if;

    select user_record.*
    into v_user
    from public.users user_record
    where user_record.id =
          auth.uid()::text
    limit 1;

    if not found then
        raise exception
            'USER_NOT_FOUND';
    end if;

    if v_user.status <>
       'active'::public."UserStatus"
    then
        raise exception
            'USER_NOT_ACTIVE';
    end if;

    /*
     * Validate the loan ID.
     */
    if p_loan_id is null
       or btrim(p_loan_id) = ''
    then
        raise exception
            'LOAN_ID_UNDEFINED';
    end if;

    /*
     * Fetch only an active loan belonging to the authenticated
     * customer.
     */
    select loan_record.*
    into v_loan
    from public.loan loan_record
    where loan_record.id =
          btrim(p_loan_id)
      and loan_record.user_id =
          v_user.id
      and loan_record.status =
          'active'::public."LoanStatus"
    limit 1;

    if not found then
        raise exception
            'ACTIVE_LOAN_NOT_FOUND';
    end if;

    /*
     * Fetch loan entries in newest-first display order.
     *
     * Entry amounts remain strings, matching Prisma Decimal
     * serialization from the original API.
     */
    select coalesce(
        jsonb_agg(
            jsonb_build_object(
                'created_at',
                loan_entry_record.created_at,

                'entry_type',
                loan_entry_record.entry_type::text,

                'debit_principal',
                coalesce(
                    loan_entry_record.debit_principal,
                    0
                )::text,

                'credit_principal',
                coalesce(
                    loan_entry_record.credit_principal,
                    0
                )::text,

                'debit_interest',
                coalesce(
                    loan_entry_record.debit_interest,
                    0
                )::text,

                'credit_interest',
                coalesce(
                    loan_entry_record.credit_interest,
                    0
                )::text,

                'accrual_date',
                loan_entry_record.accrual_date
            )
            order by
                loan_entry_record.created_at desc,
                loan_entry_record.id desc
        ),
        '[]'::jsonb
    )
    into v_entries
    from public.loan_entry
        loan_entry_record
    where loan_entry_record.loan_id =
          v_loan.id;

    /*
     * Calculate totals using PostgreSQL numeric values rather
     * than JavaScript Number conversion.
     */
    select
        coalesce(
            sum(
                loan_entry_record.debit_principal
            ),
            0
        ),

        coalesce(
            sum(
                loan_entry_record.credit_principal
            ),
            0
        ),

        coalesce(
            sum(
                loan_entry_record.debit_interest
            ),
            0
        ),

        coalesce(
            sum(
                loan_entry_record.credit_interest
            ),
            0
        )
    into
        v_debit_principal,
        v_credit_principal,
        v_debit_interest,
        v_credit_interest
    from public.loan_entry
        loan_entry_record
    where loan_entry_record.loan_id =
          v_loan.id;

    v_principal_balance :=
        v_debit_principal -
        v_credit_principal;

    v_interest_balance :=
        v_debit_interest -
        v_credit_interest;

    v_outstanding_balance :=
        v_principal_balance +
        v_interest_balance;

    return jsonb_build_object(
        'entries',
        v_entries,

        'totals',
        jsonb_build_object(
            'debit_principal',
            v_debit_principal,

            'credit_principal',
            v_credit_principal,

            'debit_interest',
            v_debit_interest,

            'credit_interest',
            v_credit_interest
        ),

        'balances',
        jsonb_build_object(
            'principal_balance',
            v_principal_balance,

            'interest_balance',
            v_interest_balance,

            'outstanding_balance',
            v_outstanding_balance
        )
    );
end;
$function$;


/*
 * ============================================================
 * PRIVILEGES
 * ============================================================
 */

revoke all on function
    public.fetch_my_active_loan_detail(
        text
    )
from public;

revoke execute on function
    public.fetch_my_active_loan_detail(
        text
    )
from anon;

grant execute on function
    public.fetch_my_active_loan_detail(
        text
    )
to authenticated;