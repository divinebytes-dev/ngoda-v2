CREATE OR REPLACE FUNCTION public.calculate_gold_buy_pricing(
    p_transaction_type public."TransactionType",
    p_amount numeric,
    p_country_code text,
    p_currency_code text
)
RETURNS public.pricing_result
LANGUAGE plpgsql
STABLE
AS $function$
declare
    v_transaction_key text :=
        lower(
            p_transaction_type::text
        );

    v_currency_key text :=
        lower(
            p_currency_code
        );

    v_tax_key text :=
        lower(
            p_transaction_type::text
        ) || '_tax';

    v_config record;

    v_fee_config
        public.amount_config := null;

    v_tax_config
        public.amount_config := null;

    v_spread_config
        public.amount_config := null;

    v_gold_market_price numeric := 0;
    v_spread_rate numeric := 0;
    v_buy_price numeric := 0;

    v_quantity numeric := 0;

    /*
     * USD pricing values.
     */
    v_fiat_paid numeric := 0;
    v_fiat_base numeric := 0;
    v_fee_fiat numeric := 0;

    /*
     * Gold-equivalent transaction fee used by the
     * gold-token sub-transaction.
     */
    v_fee_gold numeric := 0;

    v_treasury_cost numeric := 0;
    v_spread numeric := 0;
    v_tax numeric := 0;

    /*
     * Values exposed through pricing_result.
     *
     * Their units depend on whether we are building
     * the main USD transaction or the gold-token
     * sub-transaction.
     */
    v_result_fee numeric := 0;
    v_result_tax numeric := 0;
    v_result_spread numeric := 0;

begin
    /*
     * ==========================================================
     * VALIDATE TRANSACTION TYPE
     * ==========================================================
     */
    if p_transaction_type not in (
        'gold_token_buy'::public."TransactionType",
        'gold_token_buy_sub_tx'::public."TransactionType"
    ) then
        raise exception
            'INVALID_TRANSACTION_TYPE';
    end if;


    if p_amount is null
       or p_amount <= 0
    then
        raise exception
            'INVALID_AMOUNT';
    end if;


    if v_currency_key is null
       or btrim(v_currency_key) = ''
    then
        raise exception
            'CURRENCY_MISSING';
    end if;


    /*
     * ==========================================================
     * FETCH TRANSACTION CONFIGURATION
     * ==========================================================
     */
    for v_config in
        select *
        from public.fetch_all_transaction_configs(
            p_country_code,
            p_currency_code
        )
    loop
        /*
         * Transaction fee.
         */
        if lower(
            v_config.config_key
        ) = v_transaction_key
           and lower(
               v_config.currency_code
           ) = v_currency_key
        then
            v_fee_config :=
                row(
                    v_config.percentage,
                    v_config.fixed_amount,
                    v_config.min_amount,
                    v_config.max_amount
                )::public.amount_config;
        end if;


        /*
         * Transaction tax.
         */
        if lower(
            v_config.config_key
        ) = v_tax_key
           and lower(
               v_config.currency_code
           ) = v_currency_key
        then
            v_tax_config :=
                row(
                    v_config.percentage,
                    v_config.fixed_amount,
                    v_config.min_amount,
                    v_config.max_amount
                )::public.amount_config;
        end if;


        /*
         * Gold buy spread is configured against gold.
         */
        if lower(
            v_config.config_key
        ) = 'gold_spread_buy'
           and lower(
               v_config.currency_code
           ) = 'gold'
        then
            v_spread_config :=
                row(
                    v_config.percentage,
                    v_config.fixed_amount,
                    v_config.min_amount,
                    v_config.max_amount
                )::public.amount_config;
        end if;
    end loop;


    /*
     * ==========================================================
     * GOLD MARKET PRICE
     * ==========================================================
     */
    v_gold_market_price :=
        public.fetch_gold_price();


    if v_gold_market_price is null
       or v_gold_market_price <= 0
    then
        raise exception
            'GOLD_MARKET_PRICE_NOT_FOUND';
    end if;


    /*
     * ==========================================================
     * BUY PRICE
     * ==========================================================
     *
     * Flutter:
     *
     * buyPrice =
     *     goldMarketPrice * (1 + spread)
     */
    v_spread_rate :=
        coalesce(
            v_spread_config.percentage,
            0
        ) / 100;


    v_buy_price :=
        v_gold_market_price *
        (
            1 +
            v_spread_rate
        );


    if v_buy_price <= 0 then
        raise exception
            'INVALID_GOLD_BUY_PRICE';
    end if;


    /*
     * ==========================================================
     * BUY BY GOLD QUANTITY
     * ==========================================================
     *
     * Example:
     *
     *     amount   = 0.1
     *     currency = gold
     *
     *
     * Flutter formula:
     *
     * quantity =
     *     principal
     *
     * fiatBase =
     *     quantity * buyPrice
     *
     * feeFiat =
     *     fiatBase * fee
     *
     * fiatPaid =
     *     fiatBase + feeFiat
     *
     * feeGold =
     *     feeFiat / buyPrice
     *
     * treasuryCost =
     *     quantity * goldMarketPrice
     *
     * spread =
     *     fiatBase - treasuryCost
     */
    if v_currency_key = 'gold' then
        v_quantity :=
            p_amount;


        v_fiat_base :=
            v_quantity *
            v_buy_price;


        v_fee_fiat :=
            public.calculate_configured_amount(
                v_fiat_base,
                v_fee_config
            );


        v_fiat_paid :=
            v_fiat_base +
            v_fee_fiat;


        if v_buy_price > 0 then
            v_fee_gold :=
                v_fee_fiat /
                v_buy_price;
        else
            v_fee_gold :=
                0;
        end if;


        v_treasury_cost :=
            v_quantity *
            v_gold_market_price;


        v_spread :=
            v_fiat_base -
            v_treasury_cost;


        v_tax :=
            public.calculate_configured_amount(
                v_fiat_paid,
                v_tax_config
            );


    /*
     * ==========================================================
     * BUY BY USD AMOUNT
     * ==========================================================
     *
     * Flutter formula:
     *
     * fiatPaid =
     *     principal
     *
     * feeFiat =
     *     fiatPaid * fee
     *
     * fiatBase =
     *     fiatPaid - feeFiat
     *
     * quantity =
     *     fiatBase / buyPrice
     *
     * feeGold =
     *     feeFiat / buyPrice
     *
     * treasuryCost =
     *     quantity * goldMarketPrice
     *
     * spread =
     *     fiatBase - treasuryCost
     */
    else
        v_fiat_paid :=
            p_amount;


        v_fee_fiat :=
            public.calculate_configured_amount(
                v_fiat_paid,
                v_fee_config
            );


        v_fiat_base :=
            v_fiat_paid -
            v_fee_fiat;


        if v_fiat_base <= 0 then
            raise exception
                'INVALID_GOLD_BUY_FIAT_BASE';
        end if;


        v_quantity :=
            v_fiat_base /
            v_buy_price;


        v_fee_gold :=
            v_fee_fiat /
            v_buy_price;


        v_treasury_cost :=
            v_quantity *
            v_gold_market_price;


        v_spread :=
            v_fiat_base -
            v_treasury_cost;


        v_tax :=
            public.calculate_configured_amount(
                v_fiat_paid,
                v_tax_config
            );
    end if;


    /*
     * ==========================================================
     * VALIDATE CALCULATED PRICING
     * ==========================================================
     */
    if v_quantity <= 0 then
        raise exception
            'INVALID_GOLD_BUY_QUANTITY';
    end if;


    if v_fiat_paid <= 0 then
        raise exception
            'INVALID_GOLD_BUY_FIAT_AMOUNT';
    end if;


    if v_fiat_base <= 0 then
        raise exception
            'INVALID_GOLD_BUY_FIAT_BASE';
    end if;


    /*
     * ==========================================================
     * RESOLVE RESULT UNITS
     * ==========================================================
     *
     * The main gold_token_buy transaction is the USD
     * financial transaction.
     *
     * Therefore its component amounts must all be USD.
     */
    if p_transaction_type =
       'gold_token_buy'::public."TransactionType"
    then
        v_result_fee :=
            v_fee_fiat;

        v_result_tax :=
            v_tax;

        v_result_spread :=
            v_spread;


    /*
     * The gold_token_buy_sub_tx transaction represents
     * the token movement.
     *
     * Its fee therefore uses the gold-equivalent fee.
     *
     * Tax and trading spread belong to the USD financial
     * transaction and must not be mixed into the gold
     * token posting.
     */
    else
        v_result_fee :=
            v_fee_gold;

        v_result_tax :=
            0;

        v_result_spread :=
            0;
    end if;


    /*
     * ==========================================================
     * RETURN PRICING
     * ==========================================================
     *
     * pricing_result:
     *
     * fee
     * tax
     * spread
     * commission
     * quantity
     * fiat_received
     *
     *
     * fiat_received is intentionally populated with
     * v_fiat_paid for gold BUY.
     *
     * Despite the historical field name, for the buy flow
     * this gives build_posting_components the calculated
     * USD financial principal when the user entered a gold
     * quantity.
     */
    return row(
        public.round_down(
            v_result_fee
        ),

        public.round_down(
            v_result_tax
        ),

        public.round_down(
            v_result_spread
        ),

        0,

        public.round_down(
            v_quantity
        ),

        public.round_down(
            v_fiat_paid
        )
    )::public.pricing_result;

end;
$function$;