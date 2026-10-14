DROP FUNCTION IF EXISTS public.prepare_gold_buy(
    text,
    jsonb,
    text,
    text
);

CREATE OR REPLACE FUNCTION public.prepare_gold_buy(
    p_user_id text,
    p_transaction jsonb,
    p_country_code text,
    p_transaction_state_id text,
    p_blockchain_code text
)
RETURNS TABLE(
    user_id text,
    country_code text,
    user_wallet_address text,
    treasury_id text,
    treasury_wallet_address text,
    treasury_wallet_index integer,
    fiscal_year integer,
    period integer,
    document_prefix text,
    input_amount text,
    input_currency text,
    gold_price text,
    token_quantity text,
    gross_token_quantity text,
    token_fee text,
    gross_amount text,
    spread text,
    blockchain_code text,
    chain_id bigint,
    rpc_url text,
    explorer_url text,
    contract_address text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
declare
    v_amount numeric;
    v_currency text;

    v_user public.users%rowtype;
    v_treasury public.users%rowtype;

    v_fiscal_year integer;
    v_period integer;

    v_transaction_state
        public.transaction_state%rowtype;

    v_fiat_mappings
        public.transaction_gl_mapping[];

    v_token_mappings
        public.transaction_gl_mapping[];

    v_fiat_components
        public.posting_component[];

    v_token_components
        public.posting_component[];

    v_pricing public.pricing_result;
    v_gold_price numeric := 0;

    v_token_quantity numeric := 0;
    v_gross_token_quantity numeric := 0;
    v_token_fee numeric := 0;

    v_gross_amount numeric := 0;
    v_spread numeric := 0;

    v_document_prefix text;

    v_blockchain_code text;
    v_chain_id bigint;
    v_rpc_url text;
    v_explorer_url text;
    v_contract_address text;

    v_sub_transaction_type
        public."TransactionType" :=
            'gold_token_buy_sub_tx'::public."TransactionType";
begin
    /*
     * =====================================================
     * VALIDATE PROCESSING TRANSACTION
     * =====================================================
     */

    select transaction_state_record.*
    into v_transaction_state
    from public.transaction_state transaction_state_record
    where transaction_state_record.id =
          p_transaction_state_id
      and transaction_state_record.created_by =
          p_user_id
      and transaction_state_record.user_id =
          p_user_id
      and transaction_state_record.country_code =
          p_country_code
      and transaction_state_record.transaction_type =
          'gold_token_buy'::public."TransactionType"
      and transaction_state_record.status =
          'processing'::public."TransactionStatus"
    limit 1;

    if not found then
        raise exception
            'INVALID_TRANSACTION_STATE';
    end if;

    /*
     * Compare the signed transaction without
     * the blockchain metadata.
     */
    if (
        v_transaction_state.transaction_data
            - 'blockchain_code'
    ) is distinct from p_transaction
    then
        raise exception
            'TRANSACTION_STATE_DATA_MISMATCH';
    end if;

    if p_transaction ->> 'v' is distinct from 'v7' then
        raise exception
            'OPERATION_NOT_ALLOWED';
    end if;

    /*
     * =====================================================
     * VALIDATE BLOCKCHAIN
     * =====================================================
     */

    v_blockchain_code :=
        lower(
            nullif(
                btrim(p_blockchain_code),
                ''
            )
        );

    if v_blockchain_code is null then
        raise exception
            'BLOCKCHAIN_CODE_REQUIRED';
    end if;

    if v_transaction_state.transaction_data
           ->> 'blockchain_code'
       is distinct from v_blockchain_code
    then
        raise exception
            'BLOCKCHAIN_CODE_MISMATCH';
    end if;

    select
        b.code,
        n.chain_id,
        n.rpc_url,
        n.explorer_url,
        b.contract_address
    into
        v_blockchain_code,
        v_chain_id,
        v_rpc_url,
        v_explorer_url,
        v_contract_address
    from public.supported_blockchain b
    join public.supported_blockchain_network n
      on n.blockchain_id = b.id
    where b.code = v_blockchain_code
      and b.is_active = true
      and n.is_active = true
      and n.is_default = true
    limit 1;

    if not found then
        raise exception
            'BLOCKCHAIN_NETWORK_NOT_CONFIGURED';
    end if;

    if v_rpc_url is null
       or btrim(v_rpc_url) = ''
       or v_contract_address is null
       or btrim(v_contract_address) = ''
    then
        raise exception
            'BLOCKCHAIN_CONFIGURATION_INCOMPLETE';
    end if;

    /*
     * =====================================================
     * VALIDATE BUYER ROLE
     * =====================================================
     */

    if not public.user_has_role(
        p_user_id,
        array[
            'customer'::public."Role",
            'agent'::public."Role",
            'vendor'::public."Role"
        ]::public."Role"[]
    ) then
        raise exception using
            errcode = '42501',
            message = 'USER_NOT_AUTHORIZED';
    end if;

    /*
     * =====================================================
     * PARSE SIGNED TRANSACTION
     * =====================================================
     */

    v_amount :=
        (p_transaction ->> 'a')::numeric / 100;

    if v_amount <= 0 then
        raise exception
            'INVALID_AMOUNT';
    end if;

    v_currency :=
        lower(
            nullif(
                btrim(p_transaction ->> 'c'),
                ''
            )
        );

    if v_currency is null then
        raise exception
            'CURRENCY_MISSING';
    end if;

    /*
     * =====================================================
     * GOLD BUY PRICING
     * =====================================================
     */

    v_pricing :=
        public.calculate_gold_buy_pricing(
            'gold_token_buy'::public."TransactionType",
            v_amount,
            p_country_code,
            v_currency
        );

    v_gold_price :=
        coalesce(
            v_pricing.gold_price,
            0
        );

    if v_gold_price <= 0 then
        raise exception
            'INVALID_GOLD_PRICE';
    end if;

    /*
     * =====================================================
     * FETCH BUYER AND TREASURY
     * =====================================================
     */

    v_user :=
        public.fetch_user_by_id(
            p_user_id
        );

    v_treasury :=
        public.fetch_country_treasury(
            p_country_code
        );

    if v_user.wallet_address is null
       or btrim(v_user.wallet_address) = ''
    then
        raise exception
            'USER_WALLET_NOT_CONFIGURED';
    end if;

    if v_treasury.wallet_address is null
       or btrim(v_treasury.wallet_address) = ''
       or v_treasury.wallet_index is null
    then
        raise exception
            'TREASURY_WALLET_NOT_CONFIGURED';
    end if;

    if v_user.country_code is distinct from
       p_country_code
    then
        raise exception
            'OPERATION_NOT_ALLOWED';
    end if;

    /*
     * =====================================================
     * FETCH FISCAL PERIOD
     * =====================================================
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
     * =====================================================
     * FETCH GL MAPPINGS
     * =====================================================
     */

    select array_agg(mapping_record)
    into v_fiat_mappings
    from public.fetch_gl_mappings(
        'gold_token_buy'::public."TransactionType"
    ) as mapping_record;

    if v_fiat_mappings is null
       or cardinality(v_fiat_mappings) = 0
    then
        raise exception
            'GOLD_BUY_GL_MAPPINGS_NOT_FOUND';
    end if;

    select array_agg(mapping_record)
    into v_token_mappings
    from public.fetch_gl_mappings(
        v_sub_transaction_type
    ) as mapping_record;

    if v_token_mappings is null
       or cardinality(v_token_mappings) = 0
    then
        raise exception
            'GOLD_BUY_TOKEN_GL_MAPPINGS_NOT_FOUND';
    end if;

    /*
     * =====================================================
     * BUILD POSTING COMPONENTS
     * =====================================================
     */

    v_fiat_components :=
        public.build_posting_components(
            'gold_token_buy'::public."TransactionType",
            v_amount,
            v_fiat_mappings,
            p_country_code,
            v_currency,
            false
        );

    v_token_components :=
        public.build_posting_components(
            v_sub_transaction_type,
            v_amount,
            v_token_mappings,
            p_country_code,
            v_currency,
            true
        );

    if v_fiat_components is null
       or cardinality(v_fiat_components) = 0
    then
        raise exception
            'GOLD_BUY_COMPONENTS_NOT_FOUND';
    end if;

    if v_token_components is null
       or cardinality(v_token_components) = 0
    then
        raise exception
            'GOLD_BUY_TOKEN_COMPONENTS_NOT_FOUND';
    end if;

    /*
     * =====================================================
     * EXTRACT TOKEN QUANTITIES
     * =====================================================
     */

    select
        coalesce(component.debit_amount, 0),
        coalesce(component.credit_amount, 0)
    into
        v_token_quantity,
        v_gross_token_quantity
    from unnest(v_token_components) as component(
        component_type,
        debit_amount,
        credit_amount
    )
    where component.component_type =
          'principal'::public."ComponentType"
    limit 1;

    v_token_quantity :=
        public.round_down(
            coalesce(v_token_quantity, 0)
        );

    v_gross_token_quantity :=
        public.round_down(
            coalesce(v_gross_token_quantity, 0)
        );

    if v_token_quantity <= 0 then
        raise exception
            'INVALID_QUANTITY';
    end if;

    /*
     * =====================================================
     * EXTRACT TOKEN FEE
     * =====================================================
     */

    select coalesce(component.debit_amount, 0)
    into v_token_fee
    from unnest(v_token_components) as component(
        component_type,
        debit_amount,
        credit_amount
    )
    where component.component_type =
          'transaction_fee'::public."ComponentType"
    limit 1;

    v_token_fee :=
        public.round_down(
            coalesce(v_token_fee, 0)
        );

    /*
     * =====================================================
     * EXTRACT FIAT GROSS AMOUNT
     * =====================================================
     */

    select coalesce(component.debit_amount, 0)
    into v_gross_amount
    from unnest(v_fiat_components) as component(
        component_type,
        debit_amount,
        credit_amount
    )
    where component.component_type =
          'principal'::public."ComponentType"
    limit 1;

    v_gross_amount :=
        coalesce(v_gross_amount, 0);

    if v_gross_amount <= 0 then
        raise exception
            'INVALID_GROSS_AMOUNT';
    end if;

    /*
     * =====================================================
     * EXTRACT TRADING SPREAD
     * =====================================================
     */

    select coalesce(component.credit_amount, 0)
    into v_spread
    from unnest(v_fiat_components) as component(
        component_type,
        debit_amount,
        credit_amount
    )
    where component.component_type =
          'trading_spread'::public."ComponentType"
    limit 1;

    v_spread :=
        coalesce(v_spread, 0);

    /*
     * =====================================================
     * DOCUMENT PREFIX
     * =====================================================
     */

    v_document_prefix :=
        public.fetch_transaction_doc_num_prefix(
            'gold_token_buy'::public."TransactionType"
        );

    /*
     * =====================================================
     * RETURN PREPARATION
     * =====================================================
     */

    return query
    select
        v_user.id,
        p_country_code,
        v_user.wallet_address,

        v_treasury.id,
        v_treasury.wallet_address,
        v_treasury.wallet_index::integer,

        v_fiscal_year,
        v_period,
        v_document_prefix,

        v_amount::text,
        v_currency,
        v_gold_price::text,

        v_token_quantity::text,
        v_gross_token_quantity::text,
        v_token_fee::text,

        v_gross_amount::text,
        v_spread::text,

        v_blockchain_code,
        v_chain_id,
        v_rpc_url,
        v_explorer_url,
        v_contract_address;
end;
$function$;