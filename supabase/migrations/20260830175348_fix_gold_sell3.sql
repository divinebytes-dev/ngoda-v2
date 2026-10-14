CREATE OR REPLACE FUNCTION public.calculate_gold_sell_pricing(
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
    /*
     * ==========================================================
     * NORMALIZED INPUT
     * ==========================================================
     */
    v_currency_key text :=
        lower(
            nullif(
                btrim(
                    p_currency_code
                ),
                ''
            )
        );


    /*
     * ==========================================================
     * CONFIGURATION KEYS
     * ==========================================================
     *
     * Both:
     *
     *     gold_token_sell
     *     gold_token_sell_sub_tx
     *
     * belong to the same Gold Sell business transaction.
     *
     * The sub-transaction must therefore NOT look for:
     *
     *     gold_token_sell_sub_tx
     *
     * as a fee configuration.
     *
     * Both calculations use the main Gold Sell configuration.
     */
    v_fee_key text :=
        'gold_token_sell';

    v_tax_key text :=
        'gold_token_sell_tax';

    v_spread_key text :=
        'gold_spread_sell';


    /*
     * ==========================================================
     * CONFIGURATION
     * ==========================================================
     */
    v_config record;

    v_fee_config
        public.amount_config := null;

    v_tax_config
        public.amount_config := null;

    v_spread_config
        public.amount_config := null;


    /*
     * ==========================================================
     * PRICING VALUES
     * ==========================================================
     */
    v_gold_market_price numeric := 0;

    v_spread_rate numeric := 0;

    v_sell_price numeric := 0;

    v_quantity numeric := 0;

    /*
     * Fiat value represented by the Gold being sold at
     * the customer sell price.
     */
    v_fiat_base numeric := 0;

    /*
     * Amount the customer receives in fiat.
     */
    v_fiat_received numeric := 0;

    /*
     * Transaction fee represented in fiat.
     */
    v_fee_fiat numeric := 0;

    /*
     * Same transaction fee represented in Gold.
     */
    v_fee_gold numeric := 0;

    /*
     * Value of the same Gold quantity at market price.
     */
    v_market_fiat numeric := 0;

    /*
     * Difference between market value and sell-price value.
     */
    v_spread numeric := 0;

    /*
     * Government tax.
     */
    v_tax numeric := 0;


    /*
     * ==========================================================
     * RETURN VALUES
     * ==========================================================
     *
     * Main transaction returns fiat components.
     *
     * Sub-transaction returns Gold components.
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
        'gold_token_sell'::public."TransactionType",
        'gold_token_sell_sub_tx'::public."TransactionType"
    ) then
        raise exception
            'INVALID_GOLD_SELL_TRANSACTION_%',
            p_transaction_type;
    end if;


    /*
     * ==========================================================
     * VALIDATE AMOUNT
     * ==========================================================
     */
    if p_amount is null
       or p_amount <= 0
    then
        raise exception
            'INVALID_AMOUNT';
    end if;


    /*
     * ==========================================================
     * VALIDATE INPUT CURRENCY
     * ==========================================================
     *
     * Supported business modes:
     *
     *     gold
     *         User enters Gold quantity.
     *
     *     fiat currency
     *         User enters fiat amount they want to receive.
     */
    if v_currency_key is null then
        raise exception
            'CURRENCY_MISSING';
    end if;


    /*
     * ==========================================================
     * FETCH GOLD MARKET PRICE
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
     * FETCH TRANSACTION CONFIGURATION
     * ==========================================================
     *
     * IMPORTANT:
     *
     * We deliberately use the Gold Sell base configuration for
     * BOTH transaction types.
     *
     * Therefore:
     *
     * gold_token_sell
     *     uses gold_token_sell fee
     *
     * gold_token_sell_sub_tx
     *     also uses gold_token_sell fee
     *
     * This guarantees that both sides calculate the exact same
     * underlying Gold quantity.
     */
    for v_config in
        select *
        from public.fetch_all_transaction_configs(
            p_country_code,
            p_currency_code
        )
    loop
        /*
         * ------------------------------------------------------
         * TRANSACTION FEE
         * ------------------------------------------------------
         */
        if lower(
            v_config.config_key
        ) = v_fee_key
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
         * ------------------------------------------------------
         * GOVERNMENT TAX
         * ------------------------------------------------------
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
         * ------------------------------------------------------
         * GOLD SELL SPREAD
         * ------------------------------------------------------
         *
         * Spread is a Gold pricing configuration.
         */
        if lower(
            v_config.config_key
        ) = v_spread_key
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
     * CALCULATE CUSTOMER SELL PRICE
     * ==========================================================
     *
     * spreadRate =
     *
     *     configured percentage / 100
     *
     *
     * sellPrice =
     *
     *     marketPrice × (1 - spreadRate)
     */
    v_spread_rate :=
        coalesce(
            v_spread_config.percentage,
            0
        ) / 100;


    v_sell_price :=
        v_gold_market_price *
        (
            1 -
            v_spread_rate
        );


    if v_sell_price <= 0 then
        raise exception
            'INVALID_GOLD_SELL_PRICE';
    end if;


    /*
     * ==========================================================
     * MODE 1: USER ENTERS GOLD
     * ==========================================================
     *
     * Example:
     *
     *     Sell 0.100000 Gold
     *
     *
     * quantity =
     *
     *     0.100000
     *
     *
     * fiatBase =
     *
     *     quantity × sellPrice
     *
     *
     * feeFiat =
     *
     *     fee(fiatBase)
     *
     *
     * fiatReceived =
     *
     *     fiatBase - feeFiat
     *
     *
     * The entered Gold quantity is authoritative.
     */
    if v_currency_key = 'gold' then
        /*
         * Exact quantity requested by the customer.
         */
        v_quantity :=
            p_amount;


        /*
         * Fiat value of the Gold at the customer sell price.
         */
        v_fiat_base :=
            v_quantity *
            v_sell_price;


        /*
         * Calculate fee against the fiat value being sold.
         *
         * calculate_configured_amount supports:
         *
         *     percentage
         *     fixed amount
         *     minimum
         *     maximum
         */
        v_fee_fiat :=
            public.calculate_configured_amount(
                v_fiat_base,
                v_fee_config
            );


        /*
         * Customer receives the sale proceeds after fee.
         */
        v_fiat_received :=
            v_fiat_base -
            v_fee_fiat;


        /*
         * Gold-equivalent representation of the fiat fee.
         */
        v_fee_gold :=
            v_fee_fiat /
            v_sell_price;


        /*
         * Market value of the Gold sold.
         */
        v_market_fiat :=
            v_quantity *
            v_gold_market_price;


        /*
         * Trading spread earned through the difference between
         * market price and customer sell price.
         */
        v_spread :=
            v_market_fiat -
            v_fiat_base;


        /*
         * Government tax is based on the fiat proceeds.
         */
        v_tax :=
            public.calculate_configured_amount(
                v_fiat_received,
                v_tax_config
            );


    /*
     * ==========================================================
     * MODE 2: USER ENTERS FIAT TO RECEIVE
     * ==========================================================
     *
     * Example:
     *
     *     Receive exactly $10
     *
     *
     * fiatReceived =
     *
     *     10
     *
     *
     * feeFiat =
     *
     *     fee(10)
     *
     *
     * fiatBase =
     *
     *     10 + fee
     *
     *
     * quantity =
     *
     *     fiatBase / sellPrice
     *
     *
     * Therefore the Gold sold pays for:
     *
     *     customer's requested fiat
     *     +
     *     transaction fee
     *
     * There is NO reverse-percentage / gross-up calculation.
     */
    else
        /*
         * Exact fiat amount requested by customer.
         */
        v_fiat_received :=
            p_amount;


        /*
         * Fee is calculated against the entered amount.
         */
        v_fee_fiat :=
            public.calculate_configured_amount(
                v_fiat_received,
                v_fee_config
            );


        /*
         * Gold must cover:
         *
         *     requested fiat
         *     +
         *     transaction fee
         */
        v_fiat_base :=
            v_fiat_received +
            v_fee_fiat;


        /*
         * Total Gold quantity that must be sold.
         *
         * IMPORTANT:
         *
         * This quantity already represents the total Gold needed
         * to fund both the requested fiat and the transaction fee.
         */
        v_quantity :=
            v_fiat_base /
            v_sell_price;


        /*
         * Gold-equivalent representation of the fee.
         */
        v_fee_gold :=
            v_fee_fiat /
            v_sell_price;


        /*
         * Market value of the total Gold quantity sold.
         */
        v_market_fiat :=
            v_quantity *
            v_gold_market_price;


        /*
         * Trading spread.
         */
        v_spread :=
            v_market_fiat -
            v_fiat_base;


        /*
         * Government tax is calculated from the requested
         * fiat proceeds.
         */
        v_tax :=
            public.calculate_configured_amount(
                v_fiat_received,
                v_tax_config
            );
    end if;


    /*
     * ==========================================================
     * VALIDATE CALCULATED RESULT
     * ==========================================================
     */
    if v_quantity is null
       or v_quantity <= 0
    then
        raise exception
            'INVALID_GOLD_SELL_QUANTITY';
    end if;


    if v_fiat_base is null
       or v_fiat_base <= 0
    then
        raise exception
            'INVALID_GOLD_SELL_FIAT_BASE';
    end if;


    if v_fiat_received is null
       or v_fiat_received <= 0
    then
        raise exception
            'INVALID_GOLD_SELL_FIAT_RECEIVED';
    end if;


    if v_fee_fiat < 0 then
        raise exception
            'INVALID_GOLD_SELL_FEE';
    end if;


    if v_fee_gold < 0 then
        raise exception
            'INVALID_GOLD_SELL_GOLD_FEE';
    end if;


    if v_spread < 0 then
        raise exception
            'INVALID_GOLD_SELL_SPREAD';
    end if;


    if v_tax < 0 then
        raise exception
            'INVALID_GOLD_SELL_TAX';
    end if;


    /*
     * ==========================================================
     * MAIN GOLD SELL
     * ==========================================================
     *
     * Fiat-side transaction.
     *
     * All charge components returned here are FIAT.
     */
    if p_transaction_type =
       'gold_token_sell'::public."TransactionType"
    then
        v_result_fee :=
            v_fee_fiat;


        v_result_tax :=
            v_tax;


        v_result_spread :=
            v_spread;


    /*
     * ==========================================================
     * GOLD SELL SUB-TRANSACTION
     * ==========================================================
     *
     * Gold-side transaction.
     *
     * The SAME pricing calculation has already produced the
     * SAME v_quantity as the main transaction.
     *
     * Only the fee representation changes from fiat to Gold.
     *
     * Tax and trading spread remain fiat-side accounting
     * components and are therefore not returned here.
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
     * RETURN
     * ==========================================================
     *
     * pricing_result:
     *
     *     fee
     *     tax
     *     spread
     *     commission
     *     quantity
     *     fiat_received
     *
     *
     * Main:
     *
     *     fee          = fiat fee
     *     tax          = fiat tax
     *     spread       = fiat spread
     *     quantity     = total Gold sold
     *     fiat_received= customer fiat proceeds
     *
     *
     * Sub transaction:
     *
     *     fee          = Gold-equivalent fee
     *     tax          = 0
     *     spread       = 0
     *     quantity     = SAME total Gold sold
     *     fiat_received= same fiat proceeds
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
            v_fiat_received
        )
    )::public.pricing_result;

end;
$function$;