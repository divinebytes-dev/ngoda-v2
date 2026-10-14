CREATE OR REPLACE FUNCTION public.preview_my_loan(p_requested_amount text, p_token_balance text, p_currency_code text DEFAULT 'usd'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
    v_user public.users%rowtype;

    v_currency text;

    v_requested_amount numeric;
    v_onchain_balance numeric;

    v_locked_tokens numeric := 0;
    v_available_tokens numeric := 0;

    v_market_price numeric := 0;
    v_collateral_value numeric := 0;

    v_ltv_percent numeric := 0;
    v_liquidation_ltv_percent numeric := 0;
    v_initiation_fee_percent numeric := 0;

    v_max_borrowable numeric := 0;
    v_required_collateral numeric := 0;

    v_loan_fee numeric := 0;
    v_net_disbursed numeric := 0;

    v_current_ltv numeric := 0;
    v_liquidation_price numeric := 0;
    v_health_factor numeric := 0;

    v_risk_level text := 'LOW';
begin
    /*
     * ========================================================
     * AUTHORIZE CUSTOMER, VENDOR AND AGENT
     * ========================================================
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

    if v_user.country_code is null
       or btrim(v_user.country_code) = ''
    then
        raise exception
            'USER_COUNTRY_NOT_CONFIGURED';
    end if;

    /*
     * ========================================================
     * PARSE INPUT
     * ========================================================
     */

    v_currency :=
        lower(
            nullif(
                btrim(p_currency_code),
                ''
            )
        );

    if v_currency is null then
        raise exception
            'CURRENCY_MISSING';
    end if;

    /*
     * Gold collateral is currently valued in USD.
     */
    if v_currency <> 'usd' then
        raise exception
            'UNSUPPORTED_LOAN_CURRENCY';
    end if;

    begin
        v_requested_amount :=
            nullif(
                btrim(p_requested_amount),
                ''
            )::numeric;
    exception
        when invalid_text_representation
          or numeric_value_out_of_range
        then
            raise exception
                'INVALID_LOAN_AMOUNT';
    end;

    if v_requested_amount is null
       or v_requested_amount <= 0
    then
        raise exception
            'INVALID_LOAN_AMOUNT';
    end if;

    begin
        v_onchain_balance :=
            coalesce(
                nullif(
                    btrim(p_token_balance),
                    ''
                ),
                '0'
            )::numeric;
    exception
        when invalid_text_representation
          or numeric_value_out_of_range
        then
            raise exception
                'INVALID_BLOCKCHAIN_TOKEN_BALANCE';
    end;

    if v_onchain_balance <= 0 then
        raise exception
            'NO_ONCHAIN_GOLD_TOKENS_AVAILABLE';
    end if;

    /*
     * ========================================================
     * FETCH LOCKED COLLATERAL
     * ========================================================
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

    if v_locked_tokens < 0 then
        raise exception
            'INVALID_LOCKED_COLLATERAL';
    end if;

    v_available_tokens :=
        greatest(
            v_onchain_balance -
            v_locked_tokens,
            0
        );

    if v_available_tokens <= 0 then
        raise exception
            'ALL_TOKENS_LOCKED';
    end if;

    /*
     * ========================================================
     * FETCH GOLD PRICE
     * ========================================================
     */

    select current_rate.rate_to_usd
    into v_market_price
    from public.current_rates
        current_rate
    where lower(
        btrim(current_rate.code)
    ) = 'gold'
    limit 1;

    v_market_price :=
        coalesce(
            v_market_price,
            0
        );

    if v_market_price <= 0 then
        raise exception
            'INVALID_MARKET_PRICE';
    end if;

    /*
     * ========================================================
     * FETCH LOAN LTV CONFIGURATION
     * ========================================================
     */

    select loan_config_record.rate
    into v_ltv_percent
    from public.loan_config
        loan_config_record
    where loan_config_record.config_type =
          'loan_ltv'
      and loan_config_record.is_active =
          true
    limit 1;

    if not found
       or v_ltv_percent is null
    then
        raise exception
            'LTV_CONFIGURATION_NOT_FOUND';
    end if;

    if v_ltv_percent <= 0
       or v_ltv_percent >= 100
    then
        raise exception
            'INVALID_LTV_CONFIGURATION';
    end if;

    /*
     * ========================================================
     * FETCH LIQUIDATION LTV CONFIGURATION
     * ========================================================
     */

    select loan_config_record.rate
    into v_liquidation_ltv_percent
    from public.loan_config
        loan_config_record
    where loan_config_record.config_type =
          'liquidation_ltv'
      and loan_config_record.is_active =
          true
    limit 1;

    if not found
       or v_liquidation_ltv_percent is null
    then
        raise exception
            'LIQUIDATION_CONFIGURATION_NOT_FOUND';
    end if;

    if v_liquidation_ltv_percent <= 0
       or v_liquidation_ltv_percent > 100
    then
        raise exception
            'INVALID_LIQUIDATION_LTV';
    end if;

    if v_liquidation_ltv_percent <=
       v_ltv_percent
    then
        raise exception
            'LIQUIDATION_LTV_MUST_EXCEED_LOAN_LTV';
    end if;

    /*
     * ========================================================
     * FETCH LOAN INITIATION FEE
     * ========================================================
     */

    select fee_config.rate
    into v_initiation_fee_percent
    from public.transaction_type_fee_config
        fee_config
    where fee_config.transaction_type =
          'loan_disbursement'::public."TransactionType"
      and lower(
          btrim(fee_config.currency_code)
      ) = v_currency
      and fee_config.country_code =
          v_user.country_code
      and fee_config.is_active =
          true
    limit 1;

    v_initiation_fee_percent :=
        coalesce(
            v_initiation_fee_percent,
            0
        );

    if v_initiation_fee_percent < 0 then
        raise exception
            'INVALID_LOAN_FEE_CONFIGURATION';
    end if;

    /*
     * ========================================================
     * CALCULATE MAXIMUM BORROWABLE
     * ========================================================
     */

    v_collateral_value :=
        v_available_tokens *
        v_market_price;

    v_max_borrowable :=
        v_collateral_value *
        v_ltv_percent /
        100;

    if v_requested_amount >
       v_max_borrowable
    then
        raise exception
            'AMOUNT_EXCEEDS_MAX_BORROWABLE';
    end if;

    /*
     * ========================================================
     * CALCULATE REQUIRED COLLATERAL
     * ========================================================
     */

    v_required_collateral :=
        (
            v_requested_amount *
            100
        ) /
        (
            v_ltv_percent *
            v_market_price
        );

    if v_required_collateral <= 0 then
        raise exception
            'INVALID_COLLATERAL_AMOUNT';
    end if;

    if v_required_collateral >
       v_available_tokens
    then
        raise exception
            'INSUFFICIENT_COLLATERAL';
    end if;

    /*
     * ========================================================
     * CALCULATE LOAN INITIATION FEE
     * ========================================================
     */

    if v_initiation_fee_percent > 0 then
        v_loan_fee :=
            v_requested_amount *
            v_initiation_fee_percent /
            100;
    else
        v_loan_fee := 0;
    end if;

    v_net_disbursed :=
        v_requested_amount -
        v_loan_fee;

    if v_net_disbursed <= 0 then
        raise exception
            'LOAN_TOO_SMALL_AFTER_FEES';
    end if;

    /*
     * ========================================================
     * CALCULATE CURRENT LTV
     * ========================================================
     */

    v_current_ltv :=
        (
            v_requested_amount *
            100
        ) /
        (
            v_required_collateral *
            v_market_price
        );

    if v_current_ltv <= 0 then
        raise exception
            'INVALID_CURRENT_LTV';
    end if;

    /*
     * ========================================================
     * CALCULATE LIQUIDATION PRICE
     * ========================================================
     */

    v_liquidation_price :=
        v_requested_amount /
        (
            v_required_collateral *
            (
                v_liquidation_ltv_percent /
                100
            )
        );

    /*
     * ========================================================
     * CALCULATE HEALTH FACTOR AND RISK
     * ========================================================
     */

    v_health_factor :=
        v_liquidation_ltv_percent /
        v_current_ltv;

    if v_health_factor <= 1 then
        v_risk_level :=
            'LIQUIDATION_RISK';

    elsif v_health_factor <= 1.1 then
        v_risk_level :=
            'HIGH';

    elsif v_health_factor <= 1.3 then
        v_risk_level :=
            'MEDIUM';

    else
        v_risk_level :=
            'LOW';
    end if;

    /*
     * ========================================================
     * RETURN LOAN PREVIEW
     * ========================================================
     */

    return jsonb_build_object(
        'success',
        true,

        'data',
        jsonb_build_object(
            'onchain_balance',
            to_char(
                round(
                    v_onchain_balance,
                    6
                ),
                'FM999999999999999999999999990.000000'
            ),

            'locked_collateral',
            to_char(
                round(
                    v_locked_tokens,
                    6
                ),
                'FM999999999999999999999999990.000000'
            ),

            'available_tokens',
            to_char(
                round(
                    v_available_tokens,
                    6
                ),
                'FM999999999999999999999999990.000000'
            ),

            'collateral_value',
            to_char(
                round(
                    v_collateral_value,
                    2
                ),
                'FM999999999999999999999999990.00'
            ),

            'requested_amount',
            to_char(
                round(
                    v_requested_amount,
                    2
                ),
                'FM999999999999999999999999990.00'
            ),

            'market_price_per_gram',
            to_char(
                round(
                    v_market_price,
                    2
                ),
                'FM999999999999999999999999990.00'
            ),

            'max_borrowable',
            to_char(
                round(
                    v_max_borrowable,
                    2
                ),
                'FM999999999999999999999999990.00'
            ),

            'required_collateral_grams',
            to_char(
                round(
                    v_required_collateral,
                    6
                ),
                'FM999999999999999999999999990.000000'
            ),

            'initiation_fee',
            to_char(
                round(
                    v_loan_fee,
                    2
                ),
                'FM999999999999999999999999990.00'
            ),

            'net_disbursed',
            to_char(
                round(
                    v_net_disbursed,
                    2
                ),
                'FM999999999999999999999999990.00'
            ),

            'ltv_percent',
            to_char(
                round(
                    v_current_ltv,
                    2
                ),
                'FM999999999999999999999999990.00'
            ),

            'liquidation_ltv_percent',
            to_char(
                round(
                    v_liquidation_ltv_percent,
                    2
                ),
                'FM999999999999999999999999990.00'
            ),

            'risk',
            jsonb_build_object(
                'currentLtv',
                to_char(
                    round(
                        v_current_ltv,
                        2
                    ),
                    'FM999999999999999999999999990.00'
                ),

                'liquidationPrice',
                to_char(
                    round(
                        v_liquidation_price,
                        2
                    ),
                    'FM999999999999999999999999990.00'
                ),

                'healthFactor',
                to_char(
                    round(
                        v_health_factor,
                        4
                    ),
                    'FM999999999999999999999999990.0000'
                ),

                'riskLevel',
                v_risk_level
            )
        )
    );
end;
$function$
