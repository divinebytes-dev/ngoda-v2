CREATE OR REPLACE FUNCTION public.fetch_my_active_loans()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
declare
    v_user   public.users%rowtype;
    v_result jsonb;
begin
    /*
     * Authorize customer.
     */
    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHORIZED';
    end if;

    if not public.has_role(
        array[
            'customer',
            'agent',
            'vendor'
        ]::text[]
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
        raise exception
            'USER_NOT_FOUND';
    end if;

    if v_user.status <> 'active'::public."UserStatus" then
        raise exception
            'USER_NOT_ACTIVE';
    end if;

    /*
     * Fetch active loans and aggregate their ledger entries.
     *
     * Loan accounting:
     *
     * Principal:
     *   debit_principal  = principal created / increased
     *   credit_principal = principal repaid / reduced
     *
     * Interest:
     *   debit_interest   = interest accrued
     *   credit_interest  = interest repaid / reduced
     *
     * Therefore:
     *
     * outstanding_principal =
     *   debit_principal - credit_principal
     *
     * accrued_interest =
     *   debit_interest - credit_interest
     */
    select coalesce(
        jsonb_agg(
            jsonb_build_object(
                'id',
                active_loan.id,

                'principal',
                to_char(
                    round(
                        coalesce(
                            active_loan.principal,
                            0
                        ),
                        2
                    ),
                    'FM999999999999999999999999990.00'
                ),

                'initiation_fee',
                to_char(
                    round(
                        coalesce(
                            active_loan.initiation_fee,
                            0
                        ),
                        2
                    ),
                    'FM999999999999999999999999990.00'
                ),

                'net_amount',
                to_char(
                    round(
                        coalesce(
                            active_loan.net_amount,
                            0
                        ),
                        2
                    ),
                    'FM999999999999999999999999990.00'
                ),

                'interest_rate',
                trim_scale(
                    coalesce(
                        active_loan.interest_rate,
                        0
                    )
                )::text,

                /*
                 * The database column is collateral.
                 * The API response remains collateral_grams.
                 */
                'collateral_grams',
                to_char(
                    round(
                        coalesce(
                            active_loan.collateral,
                            0
                        ),
                        6
                    ),
                    'FM999999999999999999999999990.000000'
                ),

                'liquidation_price',
                to_char(
                    round(
                        coalesce(
                            active_loan.liquidation_price,
                            0
                        ),
                        2
                    ),
                    'FM999999999999999999999999990.00'
                ),

                /*
                 * Outstanding principal is the actual
                 * loan principal ledger balance.
                 */
                'outstanding_principal',
                to_char(
                    round(
                        coalesce(
                            entry_totals.debit_principal,
                            0
                        )
                        -
                        coalesce(
                            entry_totals.credit_principal,
                            0
                        ),
                        2
                    ),
                    'FM999999999999999999999999990.00'
                ),

                /*
                 * Accrued interest is the actual
                 * interest ledger balance.
                 *
                 * Accrual   -> debit
                 * Repayment -> credit
                 */
                'accrued_interest',
                to_char(
                    round(
                        coalesce(
                            entry_totals.debit_interest,
                            0
                        )
                        -
                        coalesce(
                            entry_totals.credit_interest,
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
            /*
             * Principal ledger totals.
             */
            coalesce(
                sum(
                    coalesce(
                        loan_entry_record.debit_principal,
                        0
                    )
                ),
                0
            ) as debit_principal,

            coalesce(
                sum(
                    coalesce(
                        loan_entry_record.credit_principal,
                        0
                    )
                ),
                0
            ) as credit_principal,

            /*
             * Interest ledger totals.
             */
            coalesce(
                sum(
                    coalesce(
                        loan_entry_record.debit_interest,
                        0
                    )
                ),
                0
            ) as debit_interest,

            coalesce(
                sum(
                    coalesce(
                        loan_entry_record.credit_interest,
                        0
                    )
                ),
                0
            ) as credit_interest

        from public.loan_entry loan_entry_record
        where loan_entry_record.loan_id = active_loan.id
    ) as entry_totals
        on true

    where active_loan.user_id = v_user.id
      and active_loan.status = 'active'::public."LoanStatus";

    return v_result;
end;
$function$;