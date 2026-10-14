/*
 * ============================================================
 * FETCH AUTHENTICATED CUSTOMER ACTIVE LOANS
 * ============================================================
 */

create or replace function public.fetch_my_active_loans()
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
    v_user public.users%rowtype;
    v_result jsonb;
begin
    /*
     * ========================================================
     * AUTHORIZE CUSTOMER
     * ========================================================
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
     * ========================================================
     * FETCH ACTIVE LOANS
     * ========================================================
     *
     * Outstanding balances:
     *
     * principal = debit principal - credit principal
     * interest  = debit interest  - credit interest
     *
     * greatest(..., 0) prevents an overpayment from being
     * displayed as a new positive debt.
     */

    select coalesce(
        jsonb_agg(
            jsonb_build_object(
                'id',
                active_loan.id,

                'principal',
                to_char(
                    round(
                        active_loan.principal,
                        2
                    ),
                    'FM999999999999999999999999990.00'
                ),

                'initiation_fee',
                to_char(
                    round(
                        active_loan.initiation_fee,
                        2
                    ),
                    'FM999999999999999999999999990.00'
                ),

                'net_amount',
                to_char(
                    round(
                        active_loan.net_amount,
                        2
                    ),
                    'FM999999999999999999999999990.00'
                ),

                'interest_rate',
                trim_scale(
                    active_loan.interest_rate
                )::text,

                'collateral_grams',
                to_char(
                    round(
                        active_loan.collateral_grams,
                        6
                    ),
                    'FM999999999999999999999999990.000000'
                ),

                'liquidation_price',
                to_char(
                    round(
                        active_loan.liquidation_price,
                        2
                    ),
                    'FM999999999999999999999999990.00'
                ),

                'outstanding_principal',
                to_char(
                    round(
                        greatest(
                            coalesce(
                                entry_totals.debit_principal,
                                0
                            ) -
                            coalesce(
                                entry_totals.credit_principal,
                                0
                            ),
                            0
                        ),
                        2
                    ),
                    'FM999999999999999999999999990.00'
                ),

                'accrued_interest',
                to_char(
                    round(
                        greatest(
                            coalesce(
                                entry_totals.debit_interest,
                                0
                            ) -
                            coalesce(
                                entry_totals.credit_interest,
                                0
                            ),
                            0
                        ),
                        2
                    ),
                    'FM999999999999999999999999990.00'
                )
            )
            order by
                active_loan.fiscal_year desc,
                active_loan.period desc,
                active_loan.document_number desc
        ),
        '[]'::jsonb
    )
    into v_result
    from public.loan active_loan

    left join lateral (
        select
            coalesce(
                sum(
                    loan_entry_record.debit_principal
                ),
                0
            ) as debit_principal,

            coalesce(
                sum(
                    loan_entry_record.credit_principal
                ),
                0
            ) as credit_principal,

            coalesce(
                sum(
                    loan_entry_record.debit_interest
                ),
                0
            ) as debit_interest,

            coalesce(
                sum(
                    loan_entry_record.credit_interest
                ),
                0
            ) as credit_interest

        from public.loan_entry
            loan_entry_record
        where loan_entry_record.loan_id =
              active_loan.id
    ) as entry_totals
      on true

    where active_loan.user_id =
          v_user.id
      and active_loan.status =
          'active'::public."LoanStatus";

    return v_result;
end;
$function$;


/*
 * ============================================================
 * PRIVILEGES
 * ============================================================
 */

revoke all on function
    public.fetch_my_active_loans()
from public;

revoke execute on function
    public.fetch_my_active_loans()
from anon;

grant execute on function
    public.fetch_my_active_loans()
to authenticated;