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
    v_sell_price numeric := 0;

    v_quantity numeric := 0;

    v_fiat_received numeric := 0;
    v_fiat_base numeric := 0;

    v_fee_fiat numeric := 0;
    v_fee_gold numeric := 0;

    v_market_fiat numeric := 0;
    v_spread numeric := 0;
    v_tax numeric := 0;

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
     * FETCH CONFIGURATION
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
         * Government tax.
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
         * Gold sell spread.
         */
        if lower(
            v_config.config_key
        ) = 'gold_spread_sell'
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
     * SELL PRICE
     * ==========================================================
     *
     * sellPrice =
     *
     *     goldMarketPrice *
     *     (1 - spreadRate)
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
     * SELL BY GOLD QUANTITY
     * ==========================================================
     *
     * User enters the exact Gold quantity to sell.
     *
     * quantity =
     *     entered Gold
     *
     * fiatBase =
     *     quantity * sellPrice
     *
     * feeFiat =
     *     fee(fiatBase)
     *
     * fiatReceived =
     *     fiatBase - feeFiat
     */
    if v_currency_key = 'gold' then
        v_quantity :=
            p_amount;


        v_fiat_base :=
            v_quantity *
            v_sell_price;


        v_fee_fiat :=
            public.calculate_configured_amount(
                v_fiat_base,
                v_fee_config
            );


        v_fiat_received :=
            v_fiat_base -
            v_fee_fiat;


        if v_sell_price > 0 then
            v_fee_gold :=
                v_fee_fiat /
                v_sell_price;
        else
            v_fee_gold :=
                0;
        end if;


        v_market_fiat :=
            v_quantity *
            v_gold_market_price;


        v_spread :=
            v_market_fiat -
            v_fiat_base;


        v_tax :=
            public.calculate_configured_amount(
                v_fiat_received,
                v_tax_config
            );


    /*
     * ==========================================================
     * SELL TO RECEIVE FIAT
     * ==========================================================
     *
     * User enters the exact fiat amount they want credited.
     *
     * Example:
     *
     *     user wants $10
     *
     * feeFiat =
     *     fee($10)
     *
     * fiatBase =
     *     $10 + fee
     *
     * quantity =
     *     fiatBase / sellPrice
     *
     * Therefore the Gold sold covers both:
     *
     *     requested fiat amount
     *     +
     *     transaction fee
     */
    else
        v_fiat_received :=
            p_amount;


        /*
         * Fee is calculated directly from the amount the
         * customer wants to receive.
         *
         * This keeps PostgreSQL aligned with Flutter and also
         * supports percentage, fixed, minimum and maximum fees.
         */
        v_fee_fiat :=
            public.calculate_configured_amount(
                v_fiat_received,
                v_fee_config
            );


        /*
         * Total fiat value that the Gold sale must cover.
         */
        v_fiat_base :=
            v_fiat_received +
            v_fee_fiat;


        if v_sell_price > 0 then
            v_quantity :=
                v_fiat_base /
                v_sell_price;


            v_fee_gold :=
                v_fee_fiat /
                v_sell_price;
        else
            v_quantity :=
                0;


            v_fee_gold :=
                0;
        end if;


        v_market_fiat :=
            v_quantity *
            v_gold_market_price;


        v_spread :=
            v_market_fiat -
            v_fiat_base;


        v_tax :=
            public.calculate_configured_amount(
                v_fiat_received,
                v_tax_config
            );
    end if;


    /*
     * ==========================================================
     * VALIDATE CALCULATED VALUES
     * ==========================================================
     */
    if v_quantity <= 0 then
        raise exception
            'INVALID_GOLD_SELL_QUANTITY';
    end if;


    if v_fiat_base <= 0 then
        raise exception
            'INVALID_GOLD_SELL_FIAT_BASE';
    end if;


    if v_fiat_received <= 0 then
        raise exception
            'INVALID_GOLD_SELL_FIAT_RECEIVED';
    end if;


    /*
     * ==========================================================
     * RESOLVE RESULT UNITS
     * ==========================================================
     *
     * Main Gold Sell transaction:
     *
     *     principal = USD
     *     fee       = USD
     *     tax       = USD
     *     spread    = USD
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
     * Gold Sell sub-transaction:
     *
     *     principal = Gold
     *     fee       = Gold equivalent
     *
     * Fiat tax and spread are not posted into the
     * Gold-denominated sub-transaction.
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
     *     fee
     *     tax
     *     spread
     *     commission
     *     quantity
     *     fiat_received
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