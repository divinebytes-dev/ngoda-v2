BEGIN;

DROP FUNCTION IF EXISTS
    public.build_my_vendor_dashboard();

DROP FUNCTION IF EXISTS
    public.build_my_vendor_dashboard(
        text
    );

CREATE FUNCTION public.build_my_vendor_dashboard(
    p_token_balance text
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
declare
    v_user public.users%rowtype;

    v_currencies jsonb;
    v_wallet jsonb;
    v_daily_summary jsonb;
    v_loan_summary jsonb;

    v_total_tokens numeric := 0;
    v_locked_tokens numeric := 0;
    v_available_tokens numeric := 0;

    v_principal numeric := 0;
    v_interest numeric := 0;

    v_gold_price numeric := 0;
    v_collateral_value numeric := 0;
    v_ltv numeric := 0;

    v_health text :=
        'SAFE';
begin
    /*
     * Authentication.
     */
    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHORIZED';
    end if;

    /*
     * Resolve the authenticated application user and
     * enforce active vendor status.
     */
    select user_record.*
    into v_user
    from public.users
        user_record
    join public.user_role
        role_record
      on role_record.id =
         user_record.role_id
    where user_record.id =
              auth.uid()::text

      and user_record.status =
              'active'::public."UserStatus"

      and lower(
          role_record.name::text
      ) =
              'vendor'
    limit 1;

    if not found then
        raise exception using
            errcode = '42501',
            message = 'VENDOR_NOT_AUTHORIZED';
    end if;

    /*
     * Parse the blockchain gold-token balance.
     */
    begin
        v_total_tokens :=
            coalesce(
                nullif(
                    btrim(
                        p_token_balance
                    ),
                    ''
                ),
                '0'
            )::numeric;

    exception
        when invalid_text_representation then
            raise exception
                'INVALID_BLOCKCHAIN_TOKEN_BALANCE';
    end;

    if v_total_tokens < 0 then
        raise exception
            'INVALID_BLOCKCHAIN_TOKEN_BALANCE';
    end if;

    /*
     * Preserve the existing supported currencies.
     */
    v_currencies :=
        public.build_country_supported_currencies(
            v_user.country_code
        );

    /*
     * Preserve the existing vendor wallet containers:
     *
     * - agent
     * - merchant
     * - customer
     */
    v_wallet :=
        jsonb_build_object(
            'agent',
            jsonb_build_object(
                'balances',
                '{}'::jsonb
            ),

            'merchant',
            jsonb_build_object(
                'balances',
                '{}'::jsonb
            ),

            'customer',
            jsonb_build_object(
                'balances',
                '{}'::jsonb
            )
        )
        ||
        public.build_user_wallet_balance(
            v_user.id
        );

    /*
     * Preserve the existing vendor daily summary.
     */
    v_daily_summary :=
        public.build_user_daily_summary(
            v_user.id
        );

    /*
     * Fetch locked collateral using the same calculation
     * as the customer dashboard.
     */
    select coalesce(
        collateral_record.locked_tokens,
        0
    )
    into v_locked_tokens
    from public.collateral
        collateral_record
    where collateral_record.user_id =
          v_user.id
    limit 1;

    v_locked_tokens :=
        coalesce(
            v_locked_tokens,
            0
        );

    v_available_tokens :=
        v_total_tokens -
        v_locked_tokens;

    /*
     * Current gold price in USD.
     */
    select coalesce(
        rate_record.rate_to_usd,
        0
    )
    into v_gold_price
    from public.current_rates
        rate_record
    where lower(
        btrim(
            rate_record.code
        )
    ) =
        'gold'
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
     * Aggregate all active vendor loans across all
     * fiscal years.
     */
    select
        coalesce(
            sum(
                loan_entry_record.debit_principal
            ),
            0
        ) -
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
        ) -
        coalesce(
            sum(
                loan_entry_record.credit_interest
            ),
            0
        )
    into
        v_principal,
        v_interest
    from public.loan
        loan_record
    left join public.loan_entry
        loan_entry_record
      on loan_entry_record.loan_id =
         loan_record.id
    where loan_record.user_id =
              v_user.id

      and loan_record.status =
              'active'::public."LoanStatus";

    v_principal :=
        coalesce(
            v_principal,
            0
        );

    v_interest :=
        coalesce(
            v_interest,
            0
        );

    /*
     * Calculate collateral value and LTV.
     */
    v_collateral_value :=
        v_locked_tokens *
        v_gold_price;

    if v_collateral_value > 0 then
        v_ltv :=
            (
                v_principal +
                v_interest
            ) /
            v_collateral_value *
            100;
    else
        v_ltv :=
            0;
    end if;

    /*
     * Preserve the customer dashboard health rules.
     */
    if v_ltv >= 85 then
        v_health :=
            'LIQUIDATION_RISK';

    elsif v_ltv >= 70 then
        v_health :=
            'WARNING';

    else
        v_health :=
            'SAFE';
    end if;

    /*
     * Build the LoanSummary structure.
     */
    v_loan_summary :=
        jsonb_build_object(
            'principal_outstanding',
            trim_scale(
                v_principal
            )::text,

            'interest_outstanding',
            trim_scale(
                v_interest
            )::text,

            'collateral_locked',
            trim_scale(
                v_locked_tokens
            )::text,

            'ltv_percent',
            to_char(
                round(
                    v_ltv,
                    2
                ),
                'FM999999999999999999999999990.00'
            ),

            'health',
            v_health,

            'gold',
            jsonb_build_object(
                'total',
                jsonb_build_object(
                    'grams',
                    to_char(
                        round(
                            v_total_tokens,
                            6
                        ),
                        'FM999999999999999999999999990.000000'
                    ),

                    'usdValue',
                    to_char(
                        round(
                            v_total_tokens *
                            v_gold_price,
                            2
                        ),
                        'FM999999999999999999999999990.00'
                    )
                ),

                'locked',
                jsonb_build_object(
                    'grams',
                    to_char(
                        round(
                            v_locked_tokens,
                            6
                        ),
                        'FM999999999999999999999999990.000000'
                    ),

                    'usdValue',
                    to_char(
                        round(
                            v_locked_tokens *
                            v_gold_price,
                            2
                        ),
                        'FM999999999999999999999999990.00'
                    )
                ),

                'available',
                jsonb_build_object(
                    'grams',
                    to_char(
                        round(
                            v_available_tokens,
                            6
                        ),
                        'FM999999999999999999999999990.000000'
                    ),

                    'usdValue',
                    to_char(
                        round(
                            v_available_tokens *
                            v_gold_price,
                            2
                        ),
                        'FM999999999999999999999999990.00'
                    )
                )
            )
        );

    /*
     * Existing vendor dashboard structure plus
     * loanSummary.
     */
    return jsonb_build_object(
        'currencies',
        v_currencies,

        'wallet',
        v_wallet,

        'dailySummary',
        v_daily_summary,

        'loanSummary',
        v_loan_summary
    );
end;
$function$;

REVOKE ALL ON FUNCTION
    public.build_my_vendor_dashboard(
        text
    )
FROM PUBLIC;

REVOKE ALL ON FUNCTION
    public.build_my_vendor_dashboard(
        text
    )
FROM anon;

GRANT EXECUTE ON FUNCTION
    public.build_my_vendor_dashboard(
        text
    )
TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';