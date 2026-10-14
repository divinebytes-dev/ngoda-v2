/*
 * ============================================================
 * GOLD TOKEN SELL PREPARATION
 *
 * Recalculates:
 *   - Gold quantity sent on-chain
 *   - Gross fiat sell value
 *   - Net fiat received by the seller
 *   - Fiat transaction fee
 *   - Trading spread
 *   - Government tax
 *   - Gold-equivalent fee for reporting
 *
 * The Gold-equivalent fee is not sent on-chain.
 * ============================================================
 */

create or replace function public.prepare_gold_sell(
    p_seller_id text,
    p_transaction jsonb,
    p_country_code text,
    p_transaction_state_id text
)
returns table (
    seller_id text,
    seller_wallet_address text,
    seller_wallet_index bigint,

    treasury_id text,
    treasury_wallet_address text,

    country_code text,
    fiscal_year integer,
    period integer,
    document_prefix text,

    input_amount text,
    input_currency text,

    token_quantity text,
    token_fee_equivalent text,

    gross_amount text,
    net_amount text,
    fiat_fee text,
    trading_spread text,
    government_tax text,

    sell_mappings
        public.transaction_gl_mapping[],

    sell_components
        public.posting_component[],

    token_mappings
        public.transaction_gl_mapping[],

    token_components
        public.posting_component[]
)
language plpgsql
security definer
set search_path to ''
as $function$
declare
    v_state
        public.transaction_state%rowtype;

    v_seller
        public.users%rowtype;

    v_treasury
        public.users%rowtype;

    v_reference text;
    v_input_currency text;

    v_raw_input_amount numeric;
    v_input_amount numeric;

    v_token_quantity numeric := 0;
    v_token_fee_equivalent numeric := 0;

    v_gross_amount numeric := 0;
    v_net_amount numeric := 0;
    v_fiat_fee numeric := 0;
    v_trading_spread numeric := 0;
    v_government_tax numeric := 0;

    v_fiscal_year integer;
    v_period integer;
    v_document_prefix text;

    v_sell_mappings
        public.transaction_gl_mapping[];

    v_sell_components
        public.posting_component[];

    v_token_mappings
        public.transaction_gl_mapping[];

    v_token_components
        public.posting_component[];
begin
    /*
     * Called only by the Edge Function's service-role client.
     */
    if coalesce(
        auth.role(),
        ''
    ) <> 'service_role'
    then
        raise exception using
            errcode = '42501',
            message = 'SERVICE_ROLE_REQUIRED';
    end if;

    if p_transaction is null then
        raise exception
            'TRANSACTION_DATA_IS_MISSING';
    end if;

    /*
     * Lock and validate the authenticated processing state.
     */
    select state_record.*
    into v_state
    from public.transaction_state state_record
    where state_record.id =
          p_transaction_state_id
      and state_record.created_by =
          p_seller_id
      and state_record.user_id =
          p_seller_id
      and state_record.transaction_type =
          'gold_token_sell'::public."TransactionType"
      and state_record.status =
          'processing'::public."TransactionStatus"
    for update;

    if not found then
        raise exception
            'INVALID_TRANSACTION_STATE';
    end if;

    if v_state.transaction_data
       is distinct from p_transaction
    then
        raise exception
            'TRANSACTION_DATA_MISMATCH';
    end if;

    if p_transaction ->> 'v'
       is distinct from 'v7'
    then
        raise exception
            'OPERATION_NOT_ALLOWED';
    end if;

    v_reference :=
        nullif(
            btrim(
                p_transaction ->> 'r'
            ),
            ''
        );

    if v_reference is null then
        raise exception
            'REFERENCE_IS_REQUIRED';
    end if;

    if v_state.reference is distinct from
       v_reference
    then
        raise exception
            'TRANSACTION_REFERENCE_MISMATCH';
    end if;

    v_input_currency :=
        lower(
            nullif(
                btrim(
                    p_transaction ->> 'c'
                ),
                ''
            )
        );

    if v_input_currency is null then
        raise exception
            'CURRENCY_IS_REQUIRED';
    end if;

    /*
     * Preserve the signed serialization rule:
     * transaction.a is divided by 100.
     */
    begin
        v_raw_input_amount :=
            (
                p_transaction ->> 'a'
            )::numeric / 100;
    exception
        when invalid_text_representation then
            raise exception
                'INVALID_AMOUNT';
    end;

    if v_raw_input_amount <= 0 then
        raise exception
            'INVALID_AMOUNT';
    end if;

    v_input_amount :=
        v_raw_input_amount;

    /*
     * Fetch trusted seller and country treasury.
     */
    v_seller :=
        public.fetch_user_by_id(
            p_seller_id
        );

    v_treasury :=
        public.fetch_country_treasury(
            p_country_code
        );

    if v_seller.id is null then
        raise exception
            'SELLER_NOT_FOUND';
    end if;

    if v_treasury.id is null then
        raise exception
            'TREASURY_NOT_FOUND';
    end if;

    if v_seller.status <>
       'active'::public."UserStatus"
    then
        raise exception
            'SELLER_NOT_ACTIVE';
    end if;

    if v_treasury.status <>
       'active'::public."UserStatus"
    then
        raise exception
            'TREASURY_NOT_ACTIVE';
    end if;

    if lower(
        btrim(
            v_seller.country_code
        )
    ) is distinct from lower(
        btrim(
            p_country_code
        )
    ) then
        raise exception
            'SELLER_COUNTRY_MISMATCH';
    end if;

    if lower(
        btrim(
            v_treasury.country_code
        )
    ) is distinct from lower(
        btrim(
            p_country_code
        )
    ) then
        raise exception
            'TREASURY_COUNTRY_MISMATCH';
    end if;

    if v_seller.wallet_address is null
       or btrim(
           v_seller.wallet_address
       ) = ''
    then
        raise exception
            'SELLER_WALLET_NOT_CONFIGURED';
    end if;

    /*
     * Wallet index zero is valid.
     */
    if v_seller.wallet_index is null then
        raise exception
            'SELLER_WALLET_INDEX_NOT_CONFIGURED';
    end if;

    if v_treasury.wallet_address is null
       or btrim(
           v_treasury.wallet_address
       ) = ''
    then
        raise exception
            'TREASURY_WALLET_NOT_CONFIGURED';
    end if;

    /*
     * Fetch the fiscal period.
     */
    select
        fiscal_period.fiscal_year,
        fiscal_period.period
    into
        v_fiscal_year,
        v_period
    from public.fetch_fiscal_period(
        p_country_code
    ) as fiscal_period;

    if not found then
        raise exception
            'FISCAL_PERIOD_NOT_FOUND';
    end if;

    /*
     * Main Gold Sell mappings.
     *
     * These components calculate the fiat side:
     * gross value, net value, fee, spread and tax.
     */
    select array_agg(
        mapping_record
        order by
            mapping_record.component_type
    )
    into v_sell_mappings
    from public.fetch_gl_mappings(
        'gold_token_sell'::public."TransactionType"
    ) as mapping_record;

    if v_sell_mappings is null
       or cardinality(
           v_sell_mappings
       ) = 0
    then
        raise exception
            'GOLD_SELL_GL_MAPPINGS_NOT_FOUND';
    end if;

    /*
     * Gold Sell sub-transaction mappings.
     *
     * These components calculate the Gold token side.
     */
    select array_agg(
        mapping_record
        order by
            mapping_record.component_type
    )
    into v_token_mappings
    from public.fetch_gl_mappings(
        'gold_token_sell_sub_tx'::public."TransactionType"
    ) as mapping_record;

    if v_token_mappings is null
       or cardinality(
           v_token_mappings
       ) = 0
    then
        raise exception
            'GOLD_SELL_SUB_TX_GL_MAPPINGS_NOT_FOUND';
    end if;

    /*
     * Build the fiat-side components.
     */
    v_sell_components :=
        public.build_posting_components(
            'gold_token_sell'::public."TransactionType",
            v_input_amount,
            v_sell_mappings,
            p_country_code,
            v_input_currency,
            false
        );

    if v_sell_components is null
       or cardinality(
           v_sell_components
       ) = 0
    then
        raise exception
            'GOLD_SELL_COMPONENTS_NOT_FOUND';
    end if;

    /*
     * Build the Gold token components.
     *
     * Reverse remains true because Gold tokens are treated
     * as assets.
     */
    v_token_components :=
        public.build_posting_components(
            'gold_token_sell_sub_tx'::public."TransactionType",
            v_input_amount,
            v_token_mappings,
            p_country_code,
            v_input_currency,
            true
        );

    if v_token_components is null
       or cardinality(
           v_token_components
       ) = 0
    then
        raise exception
            'GOLD_SELL_TOKEN_COMPONENTS_NOT_FOUND';
    end if;

    /*
     * Extract the actual token quantity transferred from
     * the seller to treasury.
     */
    select coalesce(
        component_record.credit_amount,
        0
    )
    into v_token_quantity
    from unnest(
        v_token_components
    ) as component_record(
        component_type,
        debit_amount,
        credit_amount
    )
    where component_record.component_type =
          'principal'::public."ComponentType"
    limit 1;

    /*
     * Gold is always rounded down to six decimal places.
     */
    v_token_quantity :=
        trunc(
            coalesce(
                v_token_quantity,
                0
            ),
            6
        );

    if v_token_quantity <= 0 then
        raise exception
            'INVALID_TOKEN_QUANTITY';
    end if;

    /*
     * Extract the Gold-equivalent fee.
     *
     * This is reporting/calculation data. It is not added
     * to the on-chain transfer quantity.
     */
    select greatest(
        coalesce(
            component_record.debit_amount,
            0
        ),
        coalesce(
            component_record.credit_amount,
            0
        )
    )
    into v_token_fee_equivalent
    from unnest(
        v_token_components
    ) as component_record(
        component_type,
        debit_amount,
        credit_amount
    )
    where component_record.component_type =
          'transaction_fee'::public."ComponentType"
    limit 1;

    v_token_fee_equivalent :=
        trunc(
            coalesce(
                v_token_fee_equivalent,
                0
            ),
            6
        );

    /*
     * Extract gross and net fiat values from the principal.
     */
    select
        coalesce(
            component_record.debit_amount,
            0
        ),
        coalesce(
            component_record.credit_amount,
            0
        )
    into
        v_gross_amount,
        v_net_amount
    from unnest(
        v_sell_components
    ) as component_record(
        component_type,
        debit_amount,
        credit_amount
    )
    where component_record.component_type =
          'principal'::public."ComponentType"
    limit 1;

    v_gross_amount :=
        coalesce(
            v_gross_amount,
            0
        );

    v_net_amount :=
        coalesce(
            v_net_amount,
            0
        );

    if v_gross_amount <= 0 then
        raise exception
            'INVALID_GROSS_AMOUNT';
    end if;

    if v_net_amount <= 0 then
        raise exception
            'INVALID_NET_AMOUNT';
    end if;

    if v_net_amount >
       v_gross_amount
    then
        raise exception
            'NET_AMOUNT_EXCEEDS_GROSS_AMOUNT';
    end if;

    /*
     * Extract the fiat transaction fee.
     */
    select greatest(
        coalesce(
            component_record.debit_amount,
            0
        ),
        coalesce(
            component_record.credit_amount,
            0
        )
    )
    into v_fiat_fee
    from unnest(
        v_sell_components
    ) as component_record(
        component_type,
        debit_amount,
        credit_amount
    )
    where component_record.component_type =
          'transaction_fee'::public."ComponentType"
    limit 1;

    v_fiat_fee :=
        coalesce(
            v_fiat_fee,
            0
        );

    if v_fiat_fee < 0 then
        raise exception
            'INVALID_FIAT_FEE';
    end if;

    /*
     * Extract trading spread.
     */
    select greatest(
        coalesce(
            component_record.debit_amount,
            0
        ),
        coalesce(
            component_record.credit_amount,
            0
        )
    )
    into v_trading_spread
    from unnest(
        v_sell_components
    ) as component_record(
        component_type,
        debit_amount,
        credit_amount
    )
    where component_record.component_type =
          'trading_spread'::public."ComponentType"
    limit 1;

    v_trading_spread :=
        coalesce(
            v_trading_spread,
            0
        );

    if v_trading_spread < 0 then
        raise exception
            'INVALID_TRADING_SPREAD';
    end if;

    /*
     * Extract government tax when configured.
     */
    select greatest(
        coalesce(
            component_record.debit_amount,
            0
        ),
        coalesce(
            component_record.credit_amount,
            0
        )
    )
    into v_government_tax
    from unnest(
        v_sell_components
    ) as component_record(
        component_type,
        debit_amount,
        credit_amount
    )
    where component_record.component_type =
          'government_tax'::public."ComponentType"
    limit 1;

    v_government_tax :=
        coalesce(
            v_government_tax,
            0
        );

    if v_government_tax < 0 then
        raise exception
            'INVALID_GOVERNMENT_TAX';
    end if;

    /*
     * Ensure both sets remain balanced.
     */
    v_sell_components :=
        public.validate_components(
            v_sell_components
        );

    v_token_components :=
        public.validate_components(
            v_token_components
        );

    /*
     * Fetch the main Gold Sell document prefix.
     */
    v_document_prefix :=
        public.fetch_transaction_doc_num_prefix(
            'gold_token_sell'::public."TransactionType"
        );

    if v_document_prefix is null
       or btrim(
           v_document_prefix
       ) = ''
    then
        raise exception
            'DOCUMENT_PREFIX_NOT_FOUND';
    end if;

    return query
    select
        v_seller.id,
        v_seller.wallet_address,
        v_seller.wallet_index::bigint,

        v_treasury.id,
        v_treasury.wallet_address,

        lower(
            btrim(
                p_country_code
            )
        ),

        v_fiscal_year,
        v_period,
        v_document_prefix,

        v_input_amount::text,
        v_input_currency,

        v_token_quantity::text,
        v_token_fee_equivalent::text,

        v_gross_amount::text,
        v_net_amount::text,
        v_fiat_fee::text,
        v_trading_spread::text,
        v_government_tax::text,

        v_sell_mappings,
        v_sell_components,
        v_token_mappings,
        v_token_components;
end;
$function$;


/*
 * ============================================================
 * OWNERSHIP AND PERMISSIONS
 * ============================================================
 */

alter function public.prepare_gold_sell(
    text,
    jsonb,
    text,
    text
)
owner to postgres;

revoke all
on function public.prepare_gold_sell(
    text,
    jsonb,
    text,
    text
)
from public, anon, authenticated, service_role;

grant execute
on function public.prepare_gold_sell(
    text,
    jsonb,
    text,
    text
)
to service_role;