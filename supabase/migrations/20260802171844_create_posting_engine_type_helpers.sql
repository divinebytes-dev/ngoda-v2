/* =========================================================
 * POSTING ENGINE COMPOSITE TYPES
 * ========================================================= */

create type public.amount_config as (
    percentage numeric,
    fixed_amount numeric,
    min_amount numeric,
    max_amount numeric
);

create type public.pricing_result as (
    fee numeric,
    tax numeric,
    spread numeric,
    commission numeric,
    quantity numeric,
    fiat_received numeric
);

create type public.posting_component as (
    component_type public."ComponentType",
    debit_amount numeric,
    credit_amount numeric
);

create type public.component_totals as (
    principal_amount numeric,
    others_amount numeric
);


/* =========================================================
 * BASIC TYPE HELPERS
 * ========================================================= */

create or replace function public.is_self_balancing_component(
    p_component_type public."ComponentType"
)
returns boolean
language sql
immutable
as $$
    select p_component_type in (
        'agent_commission'::public."ComponentType",
        'merchant_commission'::public."ComponentType",
        'referral_commission'::public."ComponentType"
    );
$$;

create or replace function public.is_gold_transaction(
    p_transaction_type public."TransactionType"
)
returns boolean
language sql
immutable
as $$
    select p_transaction_type::text like 'gold_token%';
$$;

create or replace function public.is_gold_sub_transaction(
    p_transaction_type public."TransactionType"
)
returns boolean
language sql
immutable
as $$
    select p_transaction_type::text like '%sub_tx';
$$;

create or replace function public.round_down(
    p_value numeric
)
returns numeric
language sql
immutable
strict
parallel safe
as $$
    select trunc(p_value, 6);
$$;


/* =========================================================
 * BASE TRANSACTION TYPE
 * ========================================================= */

create or replace function public.get_base_transaction_type(
    p_transaction_type public."TransactionType"
)
returns public."TransactionType"
language plpgsql
immutable
strict
parallel safe
as $$
declare
    v_base_transaction_type text;
begin
    v_base_transaction_type :=
        case
            when p_transaction_type in (
                'external_funding',
                'external_funding_reversal'
            ) then 'external_funding'

            when p_transaction_type in (
                'agent_deposit',
                'agent_deposit_reversal'
            ) then 'agent_deposit'

            when p_transaction_type in (
                'agent_funding',
                'agent_funding_reversal'
            ) then 'agent_funding'

            when p_transaction_type in (
                'cash_withdrawal',
                'cash_withdrawal_reversal'
            ) then 'cash_withdrawal'

            when p_transaction_type in (
                'customer_direct_deposit',
                'customer_direct_deposit_reversal'
            ) then 'customer_direct_deposit'

            when p_transaction_type in (
                'gold_token_buy',
                'gold_token_buy_reversal'
            ) then 'gold_token_buy'

            when p_transaction_type in (
                'gold_inventory_sell',
                'gold_inventory_sell_reversal'
            ) then 'gold_inventory_sell'

            when p_transaction_type in (
                'loan_liquidation',
                'loan_liquidation_reversal'
            ) then 'loan_liquidation'

            when p_transaction_type in (
                'treasury_funding',
                'treasury_funding_reversal'
            ) then 'treasury_funding'

            when p_transaction_type in (
                'cash_deposit',
                'cash_deposit_reversal'
            ) then 'cash_deposit'

            when p_transaction_type in (
                'gold_inventory_purchase',
                'gold_inventory_purchase_reversal'
            ) then 'gold_inventory_purchase'

            when p_transaction_type in (
                'merchant_payment',
                'merchant_payment_reversal'
            ) then 'merchant_payment'

            when p_transaction_type in (
                'merchant_withdrawal',
                'merchant_withdrawal_reversal'
            ) then 'merchant_withdrawal'

            when p_transaction_type in (
                'gold_token_mint',
                'gold_token_mint_reversal'
            ) then 'gold_token_mint'

            when p_transaction_type in (
                'gold_token_burn',
                'gold_token_burn_reversal'
            ) then 'gold_token_burn'

            when p_transaction_type in (
                'agent_commission_settlement',
                'agent_commission_settlement_reversal'
            ) then 'agent_commission_settlement'

            when p_transaction_type in (
                'agent_settlement',
                'agent_settlement_reversal'
            ) then 'agent_settlement'

            when p_transaction_type in (
                'loan_liquidation_sub_tx',
                'loan_liquidation_sub_tx_reversal'
            ) then 'loan_liquidation_sub_tx'

            when p_transaction_type in (
                'gold_token_sell_sub_tx',
                'gold_token_sell_sub_tx_reversal'
            ) then 'gold_token_sell_sub_tx'

            when p_transaction_type in (
                'gold_token_buy_sub_tx',
                'gold_token_buy_sub_tx_reversal'
            ) then 'gold_token_buy_sub_tx'

            when p_transaction_type in (
                'gold_token_sell',
                'gold_token_sell_reversal'
            ) then 'gold_token_sell'

            when p_transaction_type in (
                'loan_disbursement',
                'loan_disbursement_reversal'
            ) then 'loan_disbursement'

            when p_transaction_type in (
                'loan_repayment',
                'loan_repayment_reversal'
            ) then 'loan_repayment'

            when p_transaction_type in (
                'gold_token_transfer',
                'gold_token_transfer_reversal'
            ) then 'gold_token_transfer'

            when p_transaction_type in (
                'cash_transfer',
                'cash_transfer_reversal'
            ) then 'cash_transfer'

            when p_transaction_type in (
                'loan_interest_accrual',
                'loan_interest_accrual_reversal'
            ) then 'loan_interest_accrual'

            when p_transaction_type in (
                'government_tax_clearing',
                'government_tax_clearing_reversal'
            ) then 'government_tax_clearing'

            else null
        end;

    if v_base_transaction_type is null then
        raise exception
            'BASE_MODE_TRANSACTION_NOT_FOUND_%',
            upper(p_transaction_type::text);
    end if;

    return v_base_transaction_type::public."TransactionType";
end;
$$;


/* =========================================================
 * PRINCIPAL MODE
 * ========================================================= */

create or replace function public.resolve_principal_mode(
    p_transaction_type public."TransactionType"
)
returns public."PrincipalMode"
language plpgsql
immutable
strict
parallel safe
as $$
declare
    v_principal_mode text;
begin
    v_principal_mode :=
        case
            when p_transaction_type in (
                'cash_transfer',
                'cash_withdrawal',
                'merchant_payment',
                'gold_token_transfer',
                'gold_token_buy_sub_tx',
                'loan_liquidation'
            ) then 'gross'

            when p_transaction_type in (
                'external_funding',
                'treasury_funding',
                'agent_deposit',
                'agent_funding',
                'credit_agent_funding',
                'credit_agent_cash_deposit',
                'credit_agent_cash_withdrawal',
                'credit_agent_cash_settlement',
                'credit_agent_settlement',
                'cash_deposit',
                'customer_direct_deposit',
                'merchant_withdrawal',
                'gold_inventory_purchase',
                'gold_inventory_sell',
                'gold_token_mint',
                'gold_token_burn',
                'loan_liquidation_sub_tx',
                'agent_commission_settlement',
                'merchant_commission_settlement',
                'referral_commission_settlement',
                'government_tax_clearing',
                'agent_settlement',
                'agent_settlement_sub_tx'
            ) then 'neutral'

            when p_transaction_type in (
                'gold_token_buy',
                'gold_token_sell',
                'gold_token_sell_sub_tx',
                'loan_disbursement',
                'loan_repayment'
            ) then 'net'

            when p_transaction_type =
                'loan_interest_accrual'
            then 'charges'

            else null
        end;

    if v_principal_mode is null then
        raise exception
            'PRINCIPAL_MODE_NOT_DEFINED_%',
            p_transaction_type;
    end if;

    return v_principal_mode::public."PrincipalMode";
end;
$$;


/* =========================================================
 * CONFIGURATION LOOKUPS
 * ========================================================= */

create or replace function public.fetch_spread_by_direction(
    p_direction public."SpreadDirection",
    p_asset public."AssetType"
)
returns table (
    config_key text,
    currency_code text,
    percentage numeric,
    fixed_amount numeric,
    min_amount numeric,
    max_amount numeric
)
language sql
stable
as $$
    select
        'gold_spread_' || lower(s.direction::text),
        'gold'::text,
        coalesce(s.rate, 0)::numeric,
        null::numeric,
        null::numeric,
        null::numeric
    from public.spread_config s
    where s.direction = p_direction
      and s.asset = p_asset
      and s.is_active = true
    limit 1;
$$;

create or replace function public.fetch_all_transaction_configs(
    p_country_code text,
    p_currency_code text
)
returns table (
    config_key text,
    currency_code text,
    percentage numeric,
    fixed_amount numeric,
    min_amount numeric,
    max_amount numeric
)
language plpgsql
stable
as $$
begin
    return query
    select
        lower(f.transaction_type::text),
        lower(f.currency_code),
        coalesce(f.rate, 0)::numeric,
        f.fixed_amount::numeric,
        f.min_amount::numeric,
        f.max_amount::numeric
    from public.transaction_type_fee_config f
    where f.country_code = p_country_code
      and lower(f.currency_code) =
          lower(p_currency_code)
      and f.is_active = true;

    return query
    select
        lower(t.transaction_type::text) || '_tax',
        lower(t.currency_code),
        coalesce(t.rate, 0)::numeric,
        t.fixed_amount::numeric,
        t.min_amount::numeric,
        t.max_amount::numeric
    from public.government_tax_config t
    where t.country_code = p_country_code
      and lower(t.currency_code) =
          lower(p_currency_code)
      and t.is_active = true;

    return query
    select *
    from public.fetch_spread_by_direction(
        'buy'::public."SpreadDirection",
        'gold'::public."AssetType"
    );

    return query
    select *
    from public.fetch_spread_by_direction(
        'sell'::public."SpreadDirection",
        'gold'::public."AssetType"
    );
end;
$$;

create or replace function public.calculate_configured_amount(
    p_amount numeric,
    p_config public.amount_config default null
)
returns numeric
language plpgsql
immutable
parallel safe
as $$
declare
    v_percentage numeric;
    v_fixed numeric;
    v_minimum numeric;
    v_maximum numeric;
    v_fee numeric;
begin
    if p_config is null then
        return 0;
    end if;

    v_percentage :=
        coalesce(p_config.percentage, 0);

    v_fixed :=
        coalesce(p_config.fixed_amount, 0);

    v_minimum :=
        p_config.min_amount;

    v_maximum :=
        p_config.max_amount;

    v_fee :=
        p_amount * v_percentage / 100;

    if v_fixed > 0 then
        v_fee := v_fee + v_fixed;
    end if;

    if v_minimum is not null
       and v_minimum > 0
       and v_fee < v_minimum
    then
        v_fee := v_minimum;
    end if;

    if v_maximum is not null
       and v_maximum > 0
       and v_fee > v_maximum
    then
        v_fee := v_maximum;
    end if;

    return v_fee;
end;
$$;

create or replace function public.fetch_agent_commission_rate(
    p_transaction_type public."TransactionType",
    p_currency_code text,
    p_country_code text
)
returns numeric
language sql
stable
as $$
    select coalesce(
        (
            select c.rate::numeric
            from public.agent_fee_splitting_config c
            where c.is_active = true
              and c.transaction_type =
                  p_transaction_type
              and lower(c.currency_code) =
                  lower(p_currency_code)
              and c.country_code =
                  p_country_code
            limit 1
        ),
        0
    );
$$;

create or replace function public.fetch_gold_price()
returns numeric
language sql
stable
as $$
    select coalesce(
        (
            select r.rate_to_usd::numeric
            from public.current_rates r
            where lower(r.code) = 'gold'
            limit 1
        ),
        0
    );
$$;


/* =========================================================
 * NORMAL TRANSACTION PRICING
 * ========================================================= */

create or replace function public.calculate_transaction_pricing(
    p_transaction_type public."TransactionType",
    p_principal numeric,
    p_country_code text,
    p_currency_code text
)
returns public.pricing_result
language plpgsql
stable
as $$
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
        0
    )::public.pricing_result;
end;
$$;


/* =========================================================
 * GOLD BUY PRICING
 * ========================================================= */

create or replace function public.calculate_gold_buy_pricing(
    p_transaction_type public."TransactionType",
    p_amount numeric,
    p_country_code text,
    p_currency_code text
)
returns public.pricing_result
language plpgsql
stable
as $$
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
    v_spread_config public.amount_config := null;

    v_gold_market_price numeric := 0;
    v_spread_rate numeric := 0;
    v_buy_price numeric := 0;

    v_quantity numeric := 0;
    v_fiat_paid numeric := 0;
    v_fiat_base numeric := 0;
    v_fee_fiat numeric := 0;
    v_fee_gold numeric := 0;
    v_treasury_cost numeric := 0;
    v_spread numeric := 0;
    v_tax numeric := 0;
begin
    if p_transaction_type not in (
        'gold_token_buy',
        'gold_token_buy_sub_tx'
    ) then
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

        if lower(v_config.config_key) =
               'gold_spread_buy'
           and lower(v_config.currency_code) = 'gold'
        then
            v_spread_config := row(
                v_config.percentage,
                v_config.fixed_amount,
                v_config.min_amount,
                v_config.max_amount
            )::public.amount_config;
        end if;
    end loop;

    v_gold_market_price :=
        public.fetch_gold_price();

    v_spread_rate :=
        coalesce(v_spread_config.percentage, 0) / 100;

    v_buy_price :=
        v_gold_market_price * (1 + v_spread_rate);

    if v_currency_key = 'gold' then
        v_quantity := p_amount;

        v_fiat_base :=
            v_quantity * v_buy_price;

        v_fee_fiat :=
            public.calculate_configured_amount(
                v_fiat_base,
                v_fee_config
            );

        v_fiat_paid :=
            v_fiat_base + v_fee_fiat;

        if v_buy_price > 0 then
            v_fee_gold :=
                v_fee_fiat / v_buy_price;
        else
            v_fee_gold := 0;
        end if;

        v_treasury_cost :=
            v_quantity * v_gold_market_price;

        v_spread :=
            v_fiat_base - v_treasury_cost;

        v_tax :=
            public.calculate_configured_amount(
                v_fiat_paid,
                v_tax_config
            );
    else
        v_fiat_paid := p_amount;

        v_fee_fiat :=
            public.calculate_configured_amount(
                v_fiat_paid,
                v_fee_config
            );

        v_fiat_base :=
            v_fiat_paid - v_fee_fiat;

        if v_buy_price > 0 then
            v_quantity :=
                v_fiat_base / v_buy_price;

            v_fee_gold :=
                v_fee_fiat / v_buy_price;
        else
            v_quantity := 0;
            v_fee_gold := 0;
        end if;

        v_treasury_cost :=
            v_quantity * v_gold_market_price;

        v_spread :=
            v_fiat_base - v_treasury_cost;

        v_tax :=
            public.calculate_configured_amount(
                v_fiat_paid,
                v_tax_config
            );
    end if;

    return row(
        v_fee_gold,
        v_tax,
        v_spread,
        0,
        v_quantity,
        0
    )::public.pricing_result;
end;
$$;


/* =========================================================
 * GOLD TRANSFER PRICING
 * ========================================================= */

create or replace function public.calculate_gold_transfer_pricing(
    p_transaction_type public."TransactionType",
    p_amount numeric,
    p_country_code text,
    p_currency_code text
)
returns public.pricing_result
language plpgsql
stable
as $$
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
        0
    )::public.pricing_result;
end;
$$;


/* =========================================================
 * GOLD SELL PRICING
 * ========================================================= */

create or replace function public.calculate_gold_sell_pricing(
    p_transaction_type public."TransactionType",
    p_amount numeric,
    p_country_code text,
    p_currency_code text
)
returns public.pricing_result
language plpgsql
stable
as $$
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
    v_spread_config public.amount_config := null;

    v_gold_market_price numeric := 0;
    v_spread_rate numeric := 0;
    v_sell_price numeric := 0;

    v_quantity numeric := 0;
    v_fiat_received numeric := 0;
    v_fiat_base numeric := 0;
    v_fee_fiat numeric := 0;
    v_fee_gold numeric := 0;
    v_fee_rate numeric := 0;
    v_market_fiat numeric := 0;
    v_spread numeric := 0;
    v_tax numeric := 0;
begin
    if p_transaction_type not in (
        'gold_token_sell',
        'gold_token_sell_sub_tx'
    ) then
        raise exception
            'INVALID_GOLD_SELL_TRANSACTION_%',
            p_transaction_type;
    end if;

    v_gold_market_price :=
        public.fetch_gold_price();

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

        if lower(v_config.config_key) =
               'gold_spread_sell'
           and lower(v_config.currency_code) = 'gold'
        then
            v_spread_config := row(
                v_config.percentage,
                v_config.fixed_amount,
                v_config.min_amount,
                v_config.max_amount
            )::public.amount_config;
        end if;
    end loop;

    v_spread_rate :=
        coalesce(v_spread_config.percentage, 0) / 100;

    v_sell_price :=
        v_gold_market_price * (1 - v_spread_rate);

    if v_currency_key = 'gold' then
        v_quantity := p_amount;

        v_fiat_base :=
            v_quantity * v_sell_price;

        v_fee_fiat :=
            public.calculate_configured_amount(
                v_fiat_base,
                v_fee_config
            );

        v_fiat_received :=
            v_fiat_base - v_fee_fiat;

        if v_sell_price > 0 then
            v_fee_gold :=
                v_fee_fiat / v_sell_price;
        else
            v_fee_gold := 0;
        end if;

        v_market_fiat :=
            v_quantity * v_gold_market_price;

        v_spread :=
            v_market_fiat - v_fiat_base;

        v_tax :=
            public.calculate_configured_amount(
                v_fiat_received,
                v_tax_config
            );
    else
        v_fiat_received := p_amount;

        v_fee_rate :=
            coalesce(v_fee_config.percentage, 0) / 100;

        if (1 - v_fee_rate) > 0 then
            v_fiat_base :=
                v_fiat_received / (1 - v_fee_rate);
        else
            v_fiat_base :=
                v_fiat_received;
        end if;

        v_fee_fiat :=
            v_fiat_base - v_fiat_received;

        if v_sell_price > 0 then
            v_quantity :=
                v_fiat_base / v_sell_price;

            v_fee_gold :=
                v_fee_fiat / v_sell_price;
        else
            v_quantity := 0;
            v_fee_gold := 0;
        end if;

        v_market_fiat :=
            v_quantity * v_gold_market_price;

        v_spread :=
            v_market_fiat - v_fiat_base;

        v_tax :=
            public.calculate_configured_amount(
                v_fiat_received,
                v_tax_config
            );
    end if;

    return row(
        v_fee_gold,
        v_tax,
        v_spread,
        0,
        v_quantity,
        v_fiat_received
    )::public.pricing_result;
end;
$$;


/* =========================================================
 * RESOLVE COMPONENT AMOUNT
 * ========================================================= */

create or replace function public.resolve_component_amount(
    p_component_type public."ComponentType",
    p_pricing public.pricing_result
)
returns numeric
language plpgsql
immutable
strict
parallel safe
as $$
begin
    case p_component_type
        when 'transfer_fee' then
            return p_pricing.fee;

        when 'withdrawal_fee' then
            return p_pricing.fee;

        when 'transaction_fee' then
            return p_pricing.fee;

        when 'payment_fee' then
            return p_pricing.fee;

        when 'deposit_fee' then
            return p_pricing.fee;

        when 'loan_fee' then
            return p_pricing.fee;

        when 'liquidation_fee' then
            return p_pricing.fee;

        when 'government_tax' then
            return p_pricing.tax;

        when 'trading_spread' then
            return p_pricing.spread;

        when 'agent_commission' then
            return p_pricing.commission;

        when 'merchant_commission' then
            return p_pricing.commission;

        when 'referral_commission' then
            return p_pricing.commission;

        when 'loan_interest' then
            return p_pricing.fee;

        when 'rounding_adjustment' then
            return 0;

        else
            raise exception
                'COMPONENT_NOT_FOUND_%',
                upper(p_component_type::text);
    end case;
end;
$$;


/* =========================================================
 * BUILD PRINCIPAL COMPONENT
 * ========================================================= */

create or replace function public.build_principal_component(
    p_principal numeric,
    p_charges numeric,
    p_principal_mode public."PrincipalMode",
    p_reverse boolean default false
)
returns public.posting_component
language plpgsql
immutable
strict
parallel safe
as $$
declare
    v_debit numeric := p_principal;
    v_credit numeric := p_principal;
begin
    case p_principal_mode
        when 'gross' then
            if p_reverse then
                v_credit :=
                    p_principal + p_charges;
            else
                v_debit :=
                    p_principal + p_charges;
            end if;

        when 'net' then
            if p_reverse then
                v_debit :=
                    p_principal - p_charges;
            else
                v_credit :=
                    p_principal - p_charges;
            end if;

        when 'neutral' then
            v_debit := p_principal;
            v_credit := p_principal;

        when 'charges' then
            v_debit := p_charges;
            v_credit := 0;

        else
            raise exception
                'INVALID_PRINCIPAL_MODE_%',
                p_principal_mode;
    end case;

    if v_debit < 0 or v_credit < 0 then
        raise exception
            'PRINCIPAL_COMPONENT_NEGATIVE_AMOUNT';
    end if;

    return row(
        'principal'::public."ComponentType",
        v_debit,
        v_credit
    )::public.posting_component;
end;
$$;


/* =========================================================
 * VALIDATE COMPONENTS
 * ========================================================= */

create or replace function public.validate_components(
    p_components public.posting_component[]
)
returns public.posting_component[]
language plpgsql
immutable
strict
parallel safe
as $$
declare
    v_total_debit numeric;
    v_total_credit numeric;
    v_difference numeric;

    v_adjustment public.posting_component;
    v_adjusted public.posting_component[];
begin
    select
        coalesce(sum(c.debit_amount), 0),
        coalesce(sum(c.credit_amount), 0)
    into
        v_total_debit,
        v_total_credit
    from unnest(p_components) as c;

    v_difference :=
        v_total_debit - v_total_credit;

    if v_difference = 0 then
        return p_components;
    end if;

    if abs(v_difference) > 0.000001 then
        raise exception
            'UNBALANCED_COMPONENTS_DEBIT_%_CREDIT_%',
            v_total_debit,
            v_total_credit;
    end if;

    v_adjustment := row(
        'rounding_adjustment'::public."ComponentType",

        case
            when v_difference < 0
                then abs(v_difference)
            else 0
        end,

        case
            when v_difference > 0
                then v_difference
            else 0
        end
    )::public.posting_component;

    v_adjusted :=
        array_append(
            p_components,
            v_adjustment
        );

    select
        coalesce(sum(c.debit_amount), 0),
        coalesce(sum(c.credit_amount), 0)
    into
        v_total_debit,
        v_total_credit
    from unnest(v_adjusted) as c;

    if v_total_debit <> v_total_credit then
        raise exception
            'ROUNDING_ADJUSTMENT_FAILED';
    end if;

    return v_adjusted;
end;
$$;


/* =========================================================
 * EXTRACT COMPONENT TOTALS
 * ========================================================= */

create or replace function public.extract_component_totals(
    p_components public.posting_component[],
    p_reverse boolean default false
)
returns public.component_totals
language plpgsql
immutable
parallel safe
as $$
declare
    v_reverse boolean :=
        coalesce(p_reverse, false);

    v_principal_amount numeric := 0;
    v_others_amount numeric := 0;
begin
    if p_components is null then
        return row(
            0,
            0
        )::public.component_totals;
    end if;

    if v_reverse then
        select coalesce(
            c.credit_amount,
            0
        )
        into v_principal_amount
        from unnest(p_components)
            with ordinality as c(
                component_type,
                debit_amount,
                credit_amount,
                position
            )
        where c.component_type = 'principal'
        order by c.position
        limit 1;

        v_principal_amount :=
            coalesce(v_principal_amount, 0);

        select coalesce(
            sum(c.debit_amount),
            0
        )
        into v_others_amount
        from unnest(p_components) as c
        where c.component_type <> 'principal';
    else
        select coalesce(
            c.debit_amount,
            0
        )
        into v_principal_amount
        from unnest(p_components)
            with ordinality as c(
                component_type,
                debit_amount,
                credit_amount,
                position
            )
        where c.component_type = 'principal'
        order by c.position
        limit 1;

        v_principal_amount :=
            coalesce(v_principal_amount, 0);

        select coalesce(
            sum(c.credit_amount),
            0
        )
        into v_others_amount
        from unnest(p_components) as c
        where c.component_type <> 'principal';
    end if;

    return row(
        v_principal_amount,
        v_others_amount
    )::public.component_totals;
end;
$$;


/* =========================================================
 * BUILD POSTING COMPONENTS
 * ========================================================= */

create or replace function public.build_posting_components(
    p_transaction_type public."TransactionType",
    p_principal numeric,
    p_mappings public.transaction_gl_mapping[],
    p_country_code text,
    p_currency_code text,
    p_reverse boolean default false
)
returns public.posting_component[]
language plpgsql
stable
as $$
declare
    v_components public.posting_component[] :=
        array[]::public.posting_component[];

    v_pricing public.pricing_result :=
        row(
            0,
            0,
            0,
            0,
            0,
            0
        )::public.pricing_result;

    v_transaction_type public."TransactionType";
    v_principal_mode public."PrincipalMode";

    v_mapping public.transaction_gl_mapping%rowtype;

    v_new_principal numeric;
    v_charges numeric := 0;
    v_raw_amount numeric;
    v_amount numeric;

    v_component public.posting_component;
    v_principal_component public.posting_component;

    v_reverse boolean :=
        coalesce(p_reverse, false);
begin
    v_new_principal :=
        public.round_down(p_principal);

    v_transaction_type :=
        public.get_base_transaction_type(
            p_transaction_type
        );

    if not public.is_gold_transaction(
        v_transaction_type
    ) then
        v_pricing :=
            public.calculate_transaction_pricing(
                p_transaction_type,
                p_principal,
                p_country_code,
                p_currency_code
            );
    else
        if v_transaction_type in (
            'gold_token_buy',
            'gold_token_buy_sub_tx'
        ) then
            v_pricing :=
                public.calculate_gold_buy_pricing(
                    v_transaction_type,
                    p_principal,
                    p_country_code,
                    p_currency_code
                );

        elsif v_transaction_type =
              'gold_token_transfer'
        then
            v_pricing :=
                public.calculate_gold_transfer_pricing(
                    v_transaction_type,
                    p_principal,
                    p_country_code,
                    p_currency_code
                );

        elsif v_transaction_type in (
            'gold_token_sell',
            'gold_token_sell_sub_tx'
        ) then
            v_pricing :=
                public.calculate_gold_sell_pricing(
                    v_transaction_type,
                    p_principal,
                    p_country_code,
                    p_currency_code
                );

            v_new_principal :=
                public.round_down(
                    v_pricing.fiat_received
                );
        end if;

        if public.is_gold_sub_transaction(
            v_transaction_type
        ) then
            v_new_principal :=
                public.round_down(
                    v_pricing.quantity
                );
        end if;
    end if;

    v_principal_mode :=
        public.resolve_principal_mode(
            v_transaction_type
        );

    foreach v_mapping in array p_mappings
    loop
        if v_mapping.component_type =
           'principal'::public."ComponentType"
        then
            continue;
        end if;

        v_raw_amount :=
            public.resolve_component_amount(
                v_mapping.component_type,
                v_pricing
            );

        v_amount :=
            public.round_down(v_raw_amount);

        if v_amount <= 0 then
            continue;
        end if;

        if public.is_self_balancing_component(
            v_mapping.component_type
        ) then
            v_component := row(
                v_mapping.component_type,
                v_amount,
                v_amount
            )::public.posting_component;

            v_components :=
                array_append(
                    v_components,
                    v_component
                );

            continue;
        end if;

        v_charges :=
            v_charges + v_amount;

        if v_reverse then
            v_component := row(
                v_mapping.component_type,
                v_amount,
                0
            )::public.posting_component;
        else
            v_component := row(
                v_mapping.component_type,
                0,
                v_amount
            )::public.posting_component;
        end if;

        v_components :=
            array_append(
                v_components,
                v_component
            );
    end loop;

    v_principal_component :=
        public.build_principal_component(
            v_new_principal,
            v_charges,
            v_principal_mode,
            v_reverse
        );

    v_components :=
        array_prepend(
            v_principal_component,
            v_components
        );

    return public.validate_components(
        v_components
    );
end;
$$;