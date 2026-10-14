BEGIN;


/*
 * ============================================================
 * 1. EXTEND PRICING RESULT
 * ============================================================
 *
 * Existing:
 *
 * fee
 * tax
 * spread
 * commission
 * quantity
 * fiat_received
 *
 * New:
 *
 * gold_price
 *
 * gold_price means the actual transaction Gold price per gram:
 *
 * Gold Buy  -> buy price including buy spread
 * Gold Sell -> sell price including sell spread
 * Other     -> 0
 */



/*
 * ============================================================
 * 2. GOLD BUY PRICING
 * ============================================================
 */
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
     * BUY BY FIAT AMOUNT
     * ==========================================================
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
     * gold_price
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
        ),

        public.round_down(
            v_buy_price
        )
    )::public.pricing_result;

end;
$function$;


/*
 * ============================================================
 * 3. GOLD SELL PRICING
 * ============================================================
 */
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

    v_fiat_base numeric := 0;

    v_fiat_received numeric := 0;

    v_fee_fiat numeric := 0;

    v_fee_gold numeric := 0;

    v_market_fiat numeric := 0;

    v_spread numeric := 0;

    v_tax numeric := 0;


    /*
     * ==========================================================
     * RETURN VALUES
     * ==========================================================
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
     */
    for v_config in
        select *
        from public.fetch_all_transaction_configs(
            p_country_code,
            p_currency_code
        )
    loop
        /*
         * TRANSACTION FEE
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
         * GOVERNMENT TAX
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
         * GOLD SELL SPREAD
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


        v_fee_gold :=
            v_fee_fiat /
            v_sell_price;


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
     * MODE 2: USER ENTERS FIAT TO RECEIVE
     * ==========================================================
     */
    else
        v_fiat_received :=
            p_amount;


        v_fee_fiat :=
            public.calculate_configured_amount(
                v_fiat_received,
                v_fee_config
            );


        v_fiat_base :=
            v_fiat_received +
            v_fee_fiat;


        v_quantity :=
            v_fiat_base /
            v_sell_price;


        v_fee_gold :=
            v_fee_fiat /
            v_sell_price;


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
     * fee
     * tax
     * spread
     * commission
     * quantity
     * fiat_received
     * gold_price
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
        ),

        public.round_down(
            v_sell_price
        )
    )::public.pricing_result;

end;
$function$;


/*
 * ============================================================
 * 4. GOLD TRANSFER PRICING
 * ============================================================
 *
 * Gold Transfer does not use a buy/sell transaction price,
 * therefore gold_price = 0.
 */
CREATE OR REPLACE FUNCTION public.calculate_gold_transfer_pricing(
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
        lower(p_transaction_type::text);

    v_currency_key text :=
        lower(p_currency_code);

    v_tax_key text :=
        lower(p_transaction_type::text) || '_tax';

    v_config record;

    v_fee_config public.amount_config := null;
    v_tax_config public.amount_config := null;

    v_fee numeric := 0;
    v_tax numeric := 0;
begin
    if p_transaction_type <>
       'gold_token_transfer'::public."TransactionType"
    then
        raise exception 'INVALID_TRANSACTION_TYPE';
    end if;

    for v_config in
        select *
        from public.fetch_all_transaction_configs(
            p_country_code,
            p_currency_code
        )
    loop
        if lower(v_config.config_key) =
               v_transaction_key
           and lower(v_config.currency_code) =
               v_currency_key
        then
            v_fee_config := row(
                v_config.percentage,
                v_config.fixed_amount,
                v_config.min_amount,
                v_config.max_amount
            )::public.amount_config;
        end if;

        if lower(v_config.config_key) =
               v_tax_key
           and lower(v_config.currency_code) =
               v_currency_key
        then
            v_tax_config := row(
                v_config.percentage,
                v_config.fixed_amount,
                v_config.min_amount,
                v_config.max_amount
            )::public.amount_config;
        end if;
    end loop;

    v_fee :=
        public.calculate_configured_amount(
            p_amount,
            v_fee_config
        );

    v_tax :=
        public.calculate_configured_amount(
            p_amount,
            v_tax_config
        );

    return row(
        v_fee,
        v_tax,
        0,
        0,
        p_amount,
        0,
        0
    )::public.pricing_result;
end;
$function$;


/*
 * ============================================================
 * 5. GENERIC TRANSACTION PRICING
 * ============================================================
 *
 * Non-Gold Buy/Sell transactions have no transaction Gold
 * price, therefore gold_price = 0.
 */
CREATE OR REPLACE FUNCTION public.calculate_transaction_pricing(
    p_transaction_type public."TransactionType",
    p_principal numeric,
    p_country_code text,
    p_currency_code text
)
RETURNS public.pricing_result
LANGUAGE plpgsql
STABLE
AS $function$
declare
    v_transaction_key text :=
        lower(p_transaction_type::text);

    v_currency_key text :=
        lower(p_currency_code);

    v_tax_key text :=
        lower(p_transaction_type::text) || '_tax';

    v_config record;

    v_fee_config public.amount_config := null;
    v_tax_config public.amount_config := null;

    v_fee numeric := 0;
    v_tax numeric := 0;
    v_commission_rate numeric := 0;
    v_commission numeric := 0;
begin
    for v_config in
        select *
        from public.fetch_all_transaction_configs(
            p_country_code,
            p_currency_code
        )
    loop
        if lower(v_config.config_key) =
               v_transaction_key
           and lower(v_config.currency_code) =
               v_currency_key
        then
            v_fee_config := row(
                v_config.percentage,
                v_config.fixed_amount,
                v_config.min_amount,
                v_config.max_amount
            )::public.amount_config;
        end if;

        if lower(v_config.config_key) =
               v_tax_key
           and lower(v_config.currency_code) =
               v_currency_key
        then
            v_tax_config := row(
                v_config.percentage,
                v_config.fixed_amount,
                v_config.min_amount,
                v_config.max_amount
            )::public.amount_config;
        end if;
    end loop;

    v_fee :=
        public.calculate_configured_amount(
            p_principal,
            v_fee_config
        );

    v_tax :=
        public.calculate_configured_amount(
            p_principal,
            v_tax_config
        );

    v_commission_rate :=
        public.fetch_agent_commission_rate(
            p_transaction_type,
            p_currency_code,
            p_country_code
        );

    v_commission :=
        v_commission_rate / 100 * v_fee;

    return row(
        v_fee,
        v_tax,
        0,
        v_commission,
        0,
        0,
        0
    )::public.pricing_result;
end;
$function$;


COMMIT;