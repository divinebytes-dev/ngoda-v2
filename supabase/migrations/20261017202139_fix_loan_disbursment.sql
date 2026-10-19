-- Deploy before the new loan-disbursement Edge. Old execution clients fail closed until redeployed.
BEGIN;
CREATE OR REPLACE FUNCTION public.preview_loan_for_user(p_user_id text, p_requested_amount text, p_token_balance text, p_currency_code text DEFAULT 'usd'::text)
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

    if coalesce(auth.role(), '') <> 'service_role' then
        raise exception using errcode='42501', message='SERVICE_ROLE_REQUIRED';
    end if;

    if nullif(btrim(p_user_id), '') is null then
        raise exception 'USER_ID_REQUIRED';
    end if;

    if not public.user_has_role(
        p_user_id,
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
          p_user_id
    limit 1;

    if not found then
        raise exception
            'USER_NOT_FOUND';
    end if;

    if v_user.status is distinct from
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
       or v_requested_amount::text in ('NaN', 'Infinity', '-Infinity')
       or v_requested_amount <> trunc(v_requested_amount, 2)
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

    if v_onchain_balance::text in ('NaN', 'Infinity', '-Infinity')
       or v_onchain_balance < 0 then
        raise exception 'INVALID_BLOCKCHAIN_TOKEN_BALANCE';
    end if;

    -- Total on-chain GOLD supplied by the Edge, at six-decimal precision.
    v_onchain_balance := trunc(v_onchain_balance, 6);

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

    if v_locked_tokens::text in ('NaN', 'Infinity', '-Infinity')
       or v_locked_tokens < 0 then
        raise exception
            'INVALID_LOCKED_COLLATERAL';
    end if;

    v_available_tokens := trunc(
        greatest(v_onchain_balance - v_locked_tokens, 0),
        6
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

    if v_market_price::text in ('NaN', 'Infinity', '-Infinity')
       or v_market_price <= 0 then
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

    if v_ltv_percent::text in ('NaN', 'Infinity', '-Infinity')
       or v_ltv_percent <= 0
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

    if v_liquidation_ltv_percent::text in ('NaN', 'Infinity', '-Infinity')
       or v_liquidation_ltv_percent <= 0
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

    if v_initiation_fee_percent::text in ('NaN', 'Infinity', '-Infinity')
       or v_initiation_fee_percent < 0 then
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

    v_max_borrowable := trunc(
        v_collateral_value * v_ltv_percent / 100,
        2
    );

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

    v_required_collateral := ceil(
        (v_requested_amount * 100) /
        (v_ltv_percent * v_market_price) * 1000000
    ) / 1000000;

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
        v_loan_fee := trunc(
            v_requested_amount * v_initiation_fee_percent / 100,
            2
        );
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
$function$;

CREATE OR REPLACE FUNCTION public.execute_loan_disbursement(p_user_id text, p_requested_amount text, p_token_balance text, p_reference text, p_currency_code text DEFAULT 'usd'::text, p_ip_address text DEFAULT NULL::text)
 RETURNS TABLE(success boolean, document_number text, loan_id text, customer_id text, country_code text, currency_code text, principal_amount text, collateral_locked text, initiation_fee text, net_disbursed text, notification_id text, device_tokens text[], push_title text, push_body text, push_reference text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
    v_transaction_type
        public."TransactionType" :=
        'loan_disbursement'::public."TransactionType";

    v_stage text :=
        'initialization';

    v_user
        public.users%rowtype;

    v_treasury
        public.users%rowtype;

    v_collateral
        public.collateral%rowtype;

    v_reference text;
    v_currency text;

    /*
     * Full loan principal.
     *
     * Example:
     *
     * requested loan = 100
     *
     * principal = 100
     */
    v_requested_amount numeric;

    v_preview jsonb;
    v_preview_data jsonb;

    v_required_collateral numeric;
    v_initiation_fee numeric;

    /*
     * Actual USD amount credited to the customer's wallet.
     *
     * Example:
     *
     * principal       = 100
     * initiation fee  = 2
     * net disbursed   = 98
     */
    v_net_disbursed numeric;

    v_liquidation_price numeric;
    v_ltv_percent numeric;
    v_liquidation_ltv_percent numeric;

    v_loan_interest numeric :=
        12;

    v_fiscal_year integer;
    v_period integer;

    v_mappings
        public.transaction_gl_mapping[];

    v_components
        public.posting_component[];

    v_document_prefix text;
    v_document_number text;

    v_financial_transaction_id bigint;
    v_loan_id text;

    v_receiver_notification
        public.notification_message;

    v_receiver_notification_id text;

    v_device_tokens text[] :=
        array[]::text[];

    v_error_state text;
    v_error_message text;
    v_error_detail text;
    v_error_hint text;
    v_error_context text;

begin
    /*
     * ==========================================================
     * AUTHENTICATION / AUTHORIZATION
     * ==========================================================
     */
    v_stage :=
        'authorize customer';

    if coalesce(auth.role(), '') <> 'service_role' then
        raise exception using errcode='42501', message='SERVICE_ROLE_REQUIRED';
    end if;

    if nullif(btrim(p_user_id), '') is null then
        raise exception 'USER_ID_REQUIRED';
    end if;


    if not public.user_has_role(
        p_user_id,
        array[
            'customer',
            'agent',
            'vendor'
        ]::text[]
    ) then
        raise exception using
            errcode =
                '42501',
            message =
                'FORBIDDEN';
    end if;


    select
        user_record.*
    into
        v_user
    from public.users
        user_record
    where user_record.id =
          p_user_id
    limit 1;


    if not found then
        raise exception
            'USER_NOT_FOUND';
    end if;


    if v_user.status is distinct from
       'active'::public."UserStatus"
    then
        raise exception
            'USER_NOT_ACTIVE';
    end if;


    if v_user.country_code is null
       or btrim(
           v_user.country_code
       ) = ''
    then
        raise exception
            'USER_COUNTRY_NOT_CONFIGURED';
    end if;


    /*
     * ==========================================================
     * PARSE REQUESTED AMOUNT
     * ==========================================================
     */
    v_stage :=
        'parse requested amount';


    begin
        v_requested_amount :=
            nullif(
                btrim(
                    p_requested_amount
                ),
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
       or v_requested_amount::text in ('NaN', 'Infinity', '-Infinity')
       or v_requested_amount <> trunc(v_requested_amount, 2)
       or v_requested_amount <= 0
    then
        raise exception
            'INVALID_LOAN_AMOUNT';
    end if;


    /*
     * ==========================================================
     * PARSE REFERENCE
     * ==========================================================
     */
    v_stage :=
        'parse reference';


    v_reference :=
        nullif(
            btrim(
                p_reference
            ),
            ''
        );


    if v_reference is null then
        raise exception
            'REFERENCE_REQUIRED';
    end if;


    /*
     * ==========================================================
     * PARSE CURRENCY
     * ==========================================================
     *
     * Loans are always USD.
     */
    v_stage :=
        'parse currency';


    v_currency :=
        lower(
            nullif(
                btrim(
                    p_currency_code
                ),
                ''
            )
        );


    if v_currency is null then
        raise exception
            'CURRENCY_MISSING';
    end if;


    if v_currency <> 'usd' then
        raise exception
            'UNSUPPORTED_LOAN_CURRENCY';
    end if;


    /*
     * ==========================================================
     * REPLAY PROTECTION
     * ==========================================================
     */
    v_stage :=
        'lock loan reference';


    perform
        pg_catalog.pg_advisory_xact_lock(
            pg_catalog.hashtextextended(
                v_reference,
                0
            )
        );


    perform 1
    from public.financial_transaction
        transaction_record
    where transaction_record.reference =
          v_reference;


    if found then
        raise exception using
            errcode =
                '23505',
            message =
                'TRANSACTION_REPLAY';
    end if;


    /*
     * ==========================================================
     * FETCH COUNTRY TREASURY
     * ==========================================================
     */
    -- Use the same per-user lock as liquidation detection/repayment.
    v_stage := 'lock loan position';
    perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended('loan-position:' || v_user.id, 0)
    );
    if exists (
        select 1 from public.liquidation_job as j
        where j.user_id = v_user.id
          and j.status::text not in ('completed', 'cancelled')
    ) then
        raise exception 'LOAN_POSITION_LIQUIDATION_IN_PROGRESS';
    end if;

    v_stage :=
        'fetch country treasury';


    v_treasury :=
        public.fetch_country_treasury(
            v_user.country_code
        );


    if v_treasury.id is null then
        raise exception
            'TREASURY_WALLET_NOT_CONFIGURED';
    end if;


    /*
     * ==========================================================
     * ENSURE COLLATERAL ROW EXISTS
     * ==========================================================
     */
    v_stage :=
        'create collateral row';


    insert into public.collateral (
        user_id,
        locked_tokens,
        country_code
    )
    values (
        v_user.id,
        0,
        v_user.country_code
    )
    on conflict (
        user_id
    )
    do nothing;


    /*
     * ==========================================================
     * LOCK COLLATERAL
     * ==========================================================
     */
    v_stage :=
        'lock collateral row';


    select
        collateral_record.*
    into
        v_collateral
    from public.collateral
        collateral_record
    where collateral_record.user_id =
          v_user.id
    for update;


    if not found then
        raise exception
            'COLLATERAL_NOT_FOUND';
    end if;


    if v_collateral.country_code
       is distinct from
       v_user.country_code
    then
        raise exception
            'COLLATERAL_COUNTRY_MISMATCH';
    end if;


    /*
     * ==========================================================
     * RECALCULATE LOAN PREVIEW
     * ==========================================================
     */
    v_stage :=
        'recalculate loan preview';


    v_preview :=
        public.preview_loan_for_user(
            p_user_id => p_user_id,
            p_requested_amount =>
                v_requested_amount::text,

            p_token_balance =>
                p_token_balance,

            p_currency_code =>
                v_currency
        );


    if v_preview is null
       or coalesce(
           (
               v_preview
               ->> 'success'
           )::boolean,
           false
       ) = false
    then
        raise exception
            'LOAN_PREVIEW_FAILED';
    end if;


    v_preview_data :=
        v_preview
        -> 'data';


    if v_preview_data is null then
        raise exception
            'LOAN_PREVIEW_DATA_NOT_FOUND';
    end if;


    begin
        v_required_collateral :=
            (
                v_preview_data
                ->> 'required_collateral_grams'
            )::numeric;


        v_initiation_fee :=
            (
                v_preview_data
                ->> 'initiation_fee'
            )::numeric;


        v_net_disbursed :=
            (
                v_preview_data
                ->> 'net_disbursed'
            )::numeric;


        v_liquidation_price :=
            (
                v_preview_data
                -> 'risk'
                ->> 'liquidationPrice'
            )::numeric;


        v_ltv_percent :=
            (
                v_preview_data
                ->> 'ltv_percent'
            )::numeric;


        v_liquidation_ltv_percent :=
            (
                v_preview_data
                ->> 'liquidation_ltv_percent'
            )::numeric;

    exception
        when invalid_text_representation
          or numeric_value_out_of_range
        then
            raise exception
                'INVALID_LOAN_PREVIEW_RESULT';
    end;


    if v_required_collateral is null
       or v_required_collateral::text in ('NaN', 'Infinity', '-Infinity')
       or v_required_collateral <= 0 then
        raise exception
            'INVALID_COLLATERAL_AMOUNT';
    end if;


    if v_initiation_fee is null
       or v_initiation_fee::text in ('NaN', 'Infinity', '-Infinity')
       or v_initiation_fee < 0 then
        raise exception
            'INVALID_INITIATION_FEE';
    end if;


    if v_net_disbursed is null
       or v_net_disbursed::text in ('NaN', 'Infinity', '-Infinity')
       or v_net_disbursed <= 0 then
        raise exception
            'INVALID_NET_DISBURSEMENT';
    end if;


    if v_liquidation_price is null
       or v_liquidation_price::text in ('NaN', 'Infinity', '-Infinity')
       or v_liquidation_price <= 0 then
        raise exception
            'INVALID_LIQUIDATION_PRICE';
    end if;


    /*
     * ==========================================================
     * FETCH LOAN INTEREST
     * ==========================================================
     */
    if v_required_collateral <> ceil(v_required_collateral * 1000000) / 1000000
       or v_initiation_fee <> trunc(v_initiation_fee, 2)
       or v_net_disbursed <> trunc(v_net_disbursed, 2)
       or v_net_disbursed + v_initiation_fee <> v_requested_amount
    then
        raise exception 'INVALID_LOAN_PREVIEW_RESULT';
    end if;

    -- Persist the configured borrowing LTV, not the display-rounded actual
    -- LTV from the risk summary (rounding collateral can slightly lower it).
    select c.rate into v_ltv_percent
    from public.loan_config as c
    where c.config_type = 'loan_ltv' and c.is_active = true
    limit 1;
    if not found or v_ltv_percent is null
       or v_ltv_percent::text in ('NaN', 'Infinity', '-Infinity')
       or v_ltv_percent <= 0 or v_ltv_percent >= 100
       or v_liquidation_ltv_percent is null
       or v_liquidation_ltv_percent::text in ('NaN', 'Infinity', '-Infinity')
       or v_liquidation_ltv_percent <= v_ltv_percent
       or v_liquidation_ltv_percent > 100
    then
        raise exception 'INVALID_LOAN_LTV_CONFIGURATION';
    end if;

    v_stage :=
        'fetch loan interest';


    select
        loan_config_record.rate
    into
        v_loan_interest
    from public.loan_config
        loan_config_record
    where loan_config_record.config_type =
          'loan_interest'
      and loan_config_record.is_active =
          true
    limit 1;


    v_loan_interest :=
        coalesce(
            v_loan_interest,
            12
        );


    if v_loan_interest is null
       or v_loan_interest::text in ('NaN', 'Infinity', '-Infinity')
       or v_loan_interest < 0 then
        raise exception
            'INVALID_LOAN_INTEREST_RATE';
    end if;


    /*
     * ==========================================================
     * FETCH FISCAL PERIOD
     * ==========================================================
     */
    v_stage :=
        'fetch fiscal period';


    select
        fiscal_period.fiscal_year,
        fiscal_period.period
    into
        v_fiscal_year,
        v_period
    from public.fetch_fiscal_period(
        v_user.country_code
    ) as fiscal_period;


    if not found then
        raise exception
            'FISCAL_PERIOD_NOT_FOUND';
    end if;


    /*
     * ==========================================================
     * FETCH GL MAPPINGS
     * ==========================================================
     */
    v_stage :=
        'fetch GL mappings';


    select
        array_agg(
            mapping_record
        )
    into
        v_mappings
    from public.fetch_gl_mappings(
        v_transaction_type
    ) as mapping_record;


    if v_mappings is null
       or cardinality(
           v_mappings
       ) = 0
    then
        raise exception
            'GL_MAPPINGS_NOT_FOUND';
    end if;


    /*
     * ==========================================================
     * BUILD POSTING COMPONENTS
     * ==========================================================
     */
    v_stage :=
        'build posting components';


    v_components :=
        public.build_posting_components(
            v_transaction_type,
            v_requested_amount,
            v_mappings,
            v_user.country_code,
            v_currency,
            false
        );


    if v_components is null
       or cardinality(
           v_components
       ) = 0
    then
        raise exception
            'POSTING_COMPONENTS_NOT_FOUND';
    end if;


    /*
     * ==========================================================
     * CUSTOMER NOTIFICATION
     * ==========================================================
     */
    v_stage :=
        'create customer notification';


    v_receiver_notification :=
        public.create_notification_message(
            v_user.country_code,
            v_transaction_type,
            'receiver'::public."NotificationAudience",
            v_requested_amount,
            upper(
                v_currency
            ),
            v_reference,
            0,
            coalesce(
                v_treasury.email,
                v_treasury.phone,
                v_treasury.id
            ),
            coalesce(
                v_user.email,
                v_user.phone,
                v_user.id
            )
        );


    v_device_tokens :=
        coalesce(
            public.fetch_device_tokens(
                v_user.country_code,
                v_user.id
            ),
            array[]::text[]
        );


    /*
     * ==========================================================
     * DOCUMENT NUMBER
     * ==========================================================
     */
    v_stage :=
        'fetch document prefix';


    v_document_prefix :=
        public.fetch_transaction_doc_num_prefix(
            v_transaction_type
        );


    if v_document_prefix is null
       or btrim(
           v_document_prefix
       ) = ''
    then
        raise exception
            'DOCUMENT_PREFIX_NOT_FOUND';
    end if;


    v_stage :=
        'generate document number';


    v_document_number :=
        public.generate_document_number(
            v_document_prefix,
            v_fiscal_year,
            v_period,
            v_user.country_code
        );


    /*
     * ==========================================================
     * CREATE FINANCIAL TRANSACTION
     * ==========================================================
     */
    v_stage :=
        'create financial transaction';


    insert into public.financial_transaction (
        document_number,
        fiscal_year,
        reference,
        period,
        transaction_type,
        description,
        created_by,
        gross_amount,
        currency_code,
        country_code
    )
    values (
        v_document_number,
        v_fiscal_year,
        v_reference,
        v_period,
        v_transaction_type,
        'Loan disbursement for user ' ||
            v_user.id,
        v_user.id,
        v_requested_amount,
        v_currency,
        v_user.country_code
    )
    returning
        id
    into
        v_financial_transaction_id;


    /*
     * ==========================================================
     * POST FINANCIAL ENTRIES
     * ==========================================================
     */
    v_stage :=
        'post financial entries';


    perform *
    from public.post_financial_entries(
        p_document_number =>
            v_document_number,

        p_country_code =>
            v_user.country_code,

        p_transaction_id =>
            v_financial_transaction_id,

        p_transaction_type =>
            v_transaction_type,

        p_created_by =>
            v_user.id,

        p_components =>
            v_components,

        p_mappings =>
            v_mappings,

        p_currency_code =>
            v_currency,

        p_fiscal_year =>
            v_fiscal_year,

        p_period =>
            v_period,

        p_reference =>
            v_reference,

        p_deposit_type =>
            null
    );


    /*
     * ==========================================================
     * POST WALLET ENTRIES
     * ==========================================================
     *
     * Only the net loan proceeds are credited to the customer.
     *
     * Example:
     *
     * loan principal  = 100
     * initiation fee  = 2
     * wallet credit   = 98
     */
    v_stage :=
        'post wallet entries';


    select
        posting_result.receiver_notification_id
    into
        v_receiver_notification_id
    from public.post_wallet_entries(
        p_fiscal_year =>
            v_fiscal_year,

        p_period =>
            v_period,

        p_document_number =>
            v_document_number,

        p_reference =>
            v_reference,

        p_receiver_id =>
            v_user.id,

        p_sender_id =>
            v_treasury.id,

        p_transaction_type =>
            v_transaction_type,

        p_credit_amount =>
            v_net_disbursed,

        p_debit_amount =>
            v_net_disbursed,

        p_sender_wallet_owner =>
            'treasury'::public."WalletOwnerType",

        p_receiver_wallet_owner =>
            'customer'::public."WalletOwnerType",

        p_currency_code =>
            v_currency,

        p_country_code =>
            v_user.country_code,

        p_audit_action_type =>
            'loan_issued'::public."AuditActionType",

        p_treasury_id =>
            null,

        p_fee_amount =>
            0,

        p_ip_address =>
            p_ip_address,

        p_receiver_notification =>
            v_receiver_notification,

        p_sender_notification =>
            null
    ) as posting_result;


    /*
     * ==========================================================
     * CREATE LOAN
     * ==========================================================
     *
     * Principal remains the full requested loan amount.
     */
    v_stage :=
        'create loan';


    insert into public.loan (
        document_number,
        reference,
        user_id,
        fiscal_year,
        period,
        principal,
        net_amount,
        initiation_fee,
        interest_rate,
        collateral,
        max_ltv_percent,
        liquidation_ltv,
        liquidation_price,
        status,
        currency_code,
        country_code
    )
    values (
        v_document_number,
        v_reference,
        v_user.id,
        v_fiscal_year,
        v_period,
        v_requested_amount,
        v_net_disbursed,
        v_initiation_fee,
        v_loan_interest,
        v_required_collateral,
        v_ltv_percent,
        v_liquidation_ltv_percent,
        v_liquidation_price,
        'active'::public."LoanStatus",
        v_currency,
        v_user.country_code
    )
    returning
        id::text
    into
        v_loan_id;


    /*
     * ==========================================================
     * CREATE LOAN PRINCIPAL ENTRY
     * ==========================================================
     */
    v_stage :=
        'create loan entry';


    insert into public.loan_entry (
        loan_id,
        fiscal_year,
        period,
        document_number,
        entry_type,
        debit_principal,
        credit_principal,
        debit_interest,
        credit_interest,
        currency_code,
        country_code
    )
    values (
        v_loan_id,
        v_fiscal_year,
        v_period,
        v_document_number,
        'disbursement'::public."LoanEntryType",
        v_requested_amount,
        0,
        0,
        0,
        v_currency,
        v_user.country_code
    );


    /*
     * ==========================================================
     * UPDATE COLLATERAL
     * ==========================================================
     */
    v_stage :=
        'update collateral';


    update public.collateral
    set
        locked_tokens =
            coalesce(
                locked_tokens,
                0
            ) +
            v_required_collateral
    where user_id =
          v_user.id;


    if not found then
        raise exception
            'COLLATERAL_UPDATE_FAILED';
    end if;


    /*
     * ==========================================================
     * CREATE COLLATERAL ENTRY
     * ==========================================================
     */
    v_stage :=
        'create collateral entry';


    insert into public.collateral_entry (
        loan_id,
        document_number,
        debit,
        credit,
        country_code
    )
    values (
        v_loan_id,
        v_document_number,
        v_required_collateral,
        0,
        v_user.country_code
    );


    /*
     * ==========================================================
     * UPDATE LOAN SNAPSHOT
     * ==========================================================
     *
     * Full loan principal increases the outstanding loan.
     */
    v_stage :=
        'update loan snapshot';


    perform public.update_loan_snapshot(
        v_loan_id,
        v_user.id,
        v_user.country_code,
        v_requested_amount,
        0::numeric,
        0::numeric,
        0::numeric,
        v_fiscal_year,
        v_period
    );


    /*
     * ==========================================================
     * UPDATE COLLATERAL SNAPSHOT
     * ==========================================================
     */
    v_stage :=
        'update collateral snapshot';


    perform public.update_collateral_snapshot(
        v_user.id,
        v_user.country_code,
        v_required_collateral,
        0::numeric,
        v_fiscal_year,
        v_period
    );


    /*
     * ==========================================================
     * RETURN COMMITTED RESULT
     * ==========================================================
     *
     * Financial Intelligence uses:
     *
     * principal_amount
     *     = loan / borrowing increase
     *
     * net_disbursed
     *     = customer deposit / savings inflow
     *
     * Example:
     *
     * principal_amount = 100
     * net_disbursed    = 98
     *
     * FI:
     *
     * loan increase    +100
     * savings inflow   +98
     */
    return query
    select
        true,

        v_document_number,

        v_loan_id,

        v_user.id,

        lower(
            btrim(
                v_user.country_code
            )
        ),

        v_currency,

        to_char(
            round(
                v_requested_amount,
                2
            ),
            'FM999999999999999999999999990.00'
        ),

        to_char(
            round(
                v_required_collateral,
                6
            ),
            'FM999999999999999999999999990.000000'
        ),

        to_char(
            round(
                v_initiation_fee,
                2
            ),
            'FM999999999999999999999999990.00'
        ),

        to_char(
            round(
                v_net_disbursed,
                2
            ),
            'FM999999999999999999999999990.00'
        ),

        v_receiver_notification_id,

        v_device_tokens,

        v_receiver_notification.title,

        v_receiver_notification.body,

        v_receiver_notification.payload
            ->> 'reference';


exception
    when others then
        get stacked diagnostics
            v_error_state =
                returned_sqlstate,

            v_error_message =
                message_text,

            v_error_detail =
                pg_exception_detail,

            v_error_hint =
                pg_exception_hint,

            v_error_context =
                pg_exception_context;


        raise exception using
            errcode =
                v_error_state,

            message =
                format(
                    'LOAN_DISBURSEMENT_FAILED at [%s]: %s',
                    v_stage,
                    v_error_message
                ),

            detail =
                coalesce(
                    nullif(
                        concat_ws(
                            E'\n',
                            nullif(
                                v_error_detail,
                                ''
                            ),
                            nullif(
                                v_error_context,
                                ''
                            )
                        ),
                        ''
                    ),
                    'No additional PostgreSQL context'
                ),

            hint =
                coalesce(
                    nullif(
                        v_error_hint,
                        ''
                    ),
                    'Check the Loan Disbursement stage reported in the error'
                );

end;
$function$;

REVOKE ALL ON FUNCTION public.preview_loan_for_user(text,text,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.preview_loan_for_user(text,text,text,text) TO service_role;
REVOKE ALL ON FUNCTION public.execute_loan_disbursement(text,text,text,text,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.execute_loan_disbursement(text,text,text,text,text,text) TO service_role;

-- Retire the old posting entry point. Keep its body only for rollback review.
REVOKE ALL ON FUNCTION public.execute_my_loan_disbursement(text,text,text,text,text)
FROM PUBLIC,anon,authenticated,service_role;
COMMIT;
