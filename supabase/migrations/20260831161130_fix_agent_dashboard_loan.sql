CREATE OR REPLACE FUNCTION public.calculate_required_collateral(
    p_user_id text
)
RETURNS numeric
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
declare
    v_gold_price numeric := 0;
    v_locked_tokens numeric := 0;

    v_loan public.loan%rowtype;

    v_principal numeric := 0;
    v_interest numeric := 0;
    v_exposure numeric := 0;

    v_target_ltv numeric := 0;
    v_required_for_loan numeric := 0;

    v_total_required_pool numeric := 0;
    v_required_collateral numeric := 0;

begin
    /*
     * ==========================================================
     * VALIDATE USER
     * ==========================================================
     */
    if p_user_id is null
       or btrim(p_user_id) = ''
    then
        raise exception
            'USER_ID_REQUIRED';
    end if;


    perform 1
    from public.users user_record
    where user_record.id =
          p_user_id
    limit 1;


    if not found then
        raise exception
            'USER_NOT_FOUND';
    end if;


    /*
     * ==========================================================
     * CURRENT GOLD PRICE
     * ==========================================================
     */
    select
        coalesce(
            rate_record.rate_to_usd,
            0
        )
    into
        v_gold_price
    from public.current_rates rate_record
    where lower(
        btrim(
            rate_record.code
        )
    ) = 'gold'
    limit 1;


    v_gold_price :=
        coalesce(
            v_gold_price,
            0
        );


    if v_gold_price <= 0 then
        raise exception
            'INVALID_GOLD_RATE';
    end if;


    /*
     * ==========================================================
     * CURRENT POOLED COLLATERAL
     * ==========================================================
     */
    select
        coalesce(
            collateral_record.locked_tokens,
            0
        )
    into
        v_locked_tokens
    from public.collateral collateral_record
    where collateral_record.user_id =
          p_user_id
    limit 1;


    v_locked_tokens :=
        greatest(
            coalesce(
                v_locked_tokens,
                0
            ),
            0
        );


    /*
     * ==========================================================
     * CALCULATE REQUIRED COLLATERAL POOL
     * ==========================================================
     *
     * For every active loan:
     *
     * exposure =
     *     outstanding principal
     *     +
     *     outstanding interest
     *
     * target collateral gold =
     *
     *     exposure
     *     /
     *     (max_ltv_percent / 100)
     *     /
     *     current gold price
     *
     * The pool requirement is the SUM of all active-loan
     * requirements.
     *
     * loan.collateral is NOT used to determine the shortage.
     */
    for v_loan in
        select
            loan_record.*
        from public.loan loan_record
        where loan_record.user_id =
              p_user_id
          and loan_record.status =
              'active'::public."LoanStatus"
        order by
            loan_record.created_at asc,
            loan_record.id asc
    loop
        /*
         * Current outstanding principal and interest
         * for this loan.
         */
        select
            greatest(
                coalesce(
                    sum(
                        entry_record.debit_principal
                    ),
                    0
                ) -
                coalesce(
                    sum(
                        entry_record.credit_principal
                    ),
                    0
                ),
                0
            ),

            greatest(
                coalesce(
                    sum(
                        entry_record.debit_interest
                    ),
                    0
                ) -
                coalesce(
                    sum(
                        entry_record.credit_interest
                    ),
                    0
                ),
                0
            )
        into
            v_principal,
            v_interest
        from public.loan_entry entry_record
        where entry_record.loan_id =
              v_loan.id;


        v_exposure :=
            v_principal +
            v_interest;


        if v_exposure <= 0 then
            continue;
        end if;


        /*
         * max_ltv_percent is stored as a percentage.
         *
         * Example:
         *
         * 60.00 -> 0.60
         */
        v_target_ltv :=
            coalesce(
                v_loan.max_ltv_percent,
                0
            );


        if v_target_ltv <= 0
           or v_target_ltv > 100
        then
            raise exception
                'INVALID_LOAN_LTV_CONFIGURATION';
        end if;


        /*
         * Required Gold for this loan at the current
         * exposure and Gold price.
         */
        v_required_for_loan :=
            (
                v_exposure /
                (
                    v_target_ltv /
                    100
                )
            ) /
            v_gold_price;


        /*
         * Collateral quantities are maintained at
         * six decimal places.
         *
         * Round upward so we never understate what is
         * required to reach the configured target LTV.
         */
        v_required_for_loan :=
            ceil(
                v_required_for_loan *
                1000000
            ) /
            1000000;


        v_total_required_pool :=
            v_total_required_pool +
            v_required_for_loan;
    end loop;


    /*
     * ==========================================================
     * CALCULATE ADDITIONAL COLLATERAL REQUIRED
     * ==========================================================
     *
     * required collateral =
     *
     *     total required pool
     *     -
     *     actual pooled locked collateral
     */
    v_required_collateral :=
        greatest(
            v_total_required_pool -
            v_locked_tokens,
            0
        );


    if v_required_collateral > 0 then
        v_required_collateral :=
            ceil(
                v_required_collateral *
                1000000
            ) /
            1000000;
    else
        v_required_collateral := 0;
    end if;


    return
        v_required_collateral;
end;
$function$;