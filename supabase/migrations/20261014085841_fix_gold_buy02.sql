DO $$
DECLARE
    v_function record;
BEGIN
    FOR v_function IN
        SELECT
            n.nspname AS schema_name,
            p.proname AS function_name,
            pg_catalog.pg_get_function_identity_arguments(p.oid)
                AS arguments
        FROM pg_catalog.pg_proc AS p
        JOIN pg_catalog.pg_namespace AS n
          ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.prokind = 'f'
          AND p.proname IN (
              'fetch_my_gold_buy_context',
              'create_my_gold_buy_state',
              'prepare_gold_buy',
              'record_gold_buy_blockchain_transaction',
              'complete_gold_buy'
          )
        ORDER BY CASE p.proname
            WHEN 'complete_gold_buy' THEN 1
            WHEN 'record_gold_buy_blockchain_transaction' THEN 2
            WHEN 'prepare_gold_buy' THEN 3
            WHEN 'create_my_gold_buy_state' THEN 4
            WHEN 'fetch_my_gold_buy_context' THEN 5
        END
    LOOP
        EXECUTE format(
            'DROP FUNCTION %I.%I(%s) RESTRICT',
            v_function.schema_name,
            v_function.function_name,
            v_function.arguments
        );
    END LOOP;
END;
$$;


begin;

-- Ngoda Gold Buy: preserves the uploaded function parameter and result signatures.
CREATE OR REPLACE FUNCTION public.fetch_my_gold_buy_context(p_v text)
 RETURNS TABLE(user_id text, country_code text, wallet_address text, version_time integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
    v_stage text := 'initialization';
    v_error_state text;
    v_error_message text;
    v_error_detail text;
    v_error_hint text;
    v_error_context text;
begin
    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHORIZED';
    end if;
    v_stage := 'Gold buy remains on v7';
    /*
     * Gold buy remains on v7.
     */
    if p_v is distinct from 'v7' then
        raise exception
            'OPERATION_NOT_ALLOWED';
    end if;
    v_stage := 'Users with customer-owned wallets may buy gold';
    /*
     * Users with customer-owned wallets may buy gold.
     */
    if not public.has_role(
        array[
            'customer'::public."Role",
            'agent'::public."Role",
            'vendor'::public."Role"
        ]::public."Role"[]
    ) then
        raise exception using
            errcode = '42501',
            message = 'FORBIDDEN';
    end if;
    if not exists (
        select 1 from public.users u
        where u.id = auth.uid()::text
          and nullif(btrim(u.country_code), '') is not null
          and nullif(btrim(u.wallet_address), '') is not null
          and u.wallet_index is not null
    ) then
        raise exception 'USER_WALLET_NOT_CONFIGURED';
    end if;
    if coalesce(public.get_transaction_v(p_v), 0) <= 0 then
        raise exception 'INVALID_TRANSACTION_VERSION';
    end if;
    v_stage := 'return preparation';
    return query
    select
        user_record.id,
        user_record.country_code,
        user_record.wallet_address,
        public.get_transaction_v(p_v)
    from public.users user_record
    where user_record.id =
          auth.uid()::text
      and user_record.status =
          'active'::public."UserStatus"
    limit 1;
    if not found then
        raise exception
            'GOLD_BUY_CONTEXT_NOT_FOUND';
    end if;
exception
    when others then
        get stacked diagnostics
            v_error_state = returned_sqlstate,
            v_error_message = message_text,
            v_error_detail = pg_exception_detail,
            v_error_hint = pg_exception_hint,
            v_error_context = pg_exception_context;
        raise exception using
            errcode = v_error_state,
            message = format('GOLD_BUY_FAILED at [%s]: %s', v_stage, v_error_message),
            detail = concat_ws(E'\n', nullif(v_error_detail, ''), nullif(v_error_context, '')),
            hint = coalesce(nullif(v_error_hint, ''), 'Check the gold-buy stage reported in the error');
end;
$function$;
REVOKE ALL ON FUNCTION public.fetch_my_gold_buy_context(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fetch_my_gold_buy_context(text) TO authenticated;
-- Ngoda Gold Buy: preserves the uploaded function parameter and result signatures.
CREATE OR REPLACE FUNCTION public.create_my_gold_buy_state(p_transaction jsonb)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
    v_stage text := 'initialization';
    v_error_state text;
    v_error_message text;
    v_error_detail text;
    v_error_hint text;
    v_error_context text;
    v_user_id text;
    v_country_code text;
    v_reference text;
    v_version text;
    v_transaction_state_id text;
begin
    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHORIZED';
    end if;
    if not public.has_role(
        array[
            'customer'::public."Role",
            'agent'::public."Role",
            'vendor'::public."Role"
        ]::public."Role"[]
    ) then
        raise exception using
            errcode = '42501',
            message = 'FORBIDDEN';
    end if;
    if p_transaction is null
       or jsonb_typeof(p_transaction) <>
          'object'
    then
        raise exception
            'TRANSACTION_DATA_IS_MISSING';
    end if;
    v_version :=
        nullif(
            btrim(p_transaction ->> 'v'),
            ''
        );
    if v_version is distinct from 'v7' then
        raise exception
            'OPERATION_NOT_ALLOWED';
    end if;
    v_reference :=
        nullif(
            btrim(p_transaction ->> 'r'),
            ''
        );
    if v_reference is null then
        raise exception
            'REFERENCE_MISSING';
    end if;
    v_user_id :=
        auth.uid()::text;
    select user_record.country_code
    into v_country_code
    from public.users user_record
    where user_record.id =
          v_user_id
      and user_record.status =
          'active'::public."UserStatus"
    limit 1;
    if not found then
        raise exception
            'USER_NOT_AUTHORIZED';
    end if;
    if nullif(btrim(p_transaction ->> 'c'), '') is null then
        raise exception 'CURRENCY_MISSING';
    end if;
    if not exists (
        select 1 from public.users u where u.id = v_user_id
          and nullif(btrim(u.wallet_address), '') is not null
          and u.wallet_index is not null
    ) then
        raise exception 'USER_WALLET_NOT_CONFIGURED';
    end if;
    v_stage := 'The authenticated buyer is stored as the state';
    /*
     * The authenticated buyer is stored as the state
     * participant. transaction.s remains part of the
     * signed canonical transaction but is not trusted
     * as the authenticated user ID.
     */
    v_stage := 'insert database record';
    insert into public.transaction_state (
        reference,
        status,
        transaction_type,
        country_code,
        transaction_data,
        created_by,
        user_id
    )
    values (
        v_reference,
        'processing'::public."TransactionStatus",
        'gold_token_buy'::public."TransactionType",
        v_country_code,
        p_transaction,
        v_user_id,
        v_user_id
    )
    returning id::text
    into v_transaction_state_id;
    if v_transaction_state_id is null then
        raise exception 'TRANSACTION_STATE_CREATE_FAILED';
    end if;
    return v_transaction_state_id;
exception
    when unique_violation then
        raise exception using
            errcode = '23505',
            message = 'TRANSACTION_REPLAY';
    when others then
        get stacked diagnostics
            v_error_state = returned_sqlstate,
            v_error_message = message_text,
            v_error_detail = pg_exception_detail,
            v_error_hint = pg_exception_hint,
            v_error_context = pg_exception_context;
        raise exception using
            errcode = v_error_state,
            message = format('GOLD_BUY_FAILED at [%s]: %s', v_stage, v_error_message),
            detail = concat_ws(E'\n', nullif(v_error_detail, ''), nullif(v_error_context, '')),
            hint = coalesce(nullif(v_error_hint, ''), 'Check the gold-buy stage reported in the error');
end;
$function$;
REVOKE ALL ON FUNCTION public.create_my_gold_buy_state(jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_my_gold_buy_state(jsonb) TO authenticated;
-- Ngoda Gold Buy: preserves the uploaded function parameter and result signatures.
CREATE OR REPLACE FUNCTION public.prepare_gold_buy(p_user_id text, p_transaction jsonb, p_country_code text, p_transaction_state_id text)
 RETURNS TABLE(user_id text, country_code text, user_wallet_address text, treasury_id text, treasury_wallet_address text, treasury_wallet_index integer, fiscal_year integer, period integer, document_prefix text, input_amount text, input_currency text, gold_price text, token_quantity text, gross_token_quantity text, token_fee text, gross_amount text, spread text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
    v_stage text := 'initialization';
    v_error_state text;
    v_error_message text;
    v_error_detail text;
    v_error_hint text;
    v_error_context text;
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
    /*
     * Exact pricing result used for this Gold Buy.
     *
     * gold_price is the customer Buy price per gram,
     * including the configured Buy spread.
     */
    v_pricing public.pricing_result;
    v_gold_price numeric := 0;
    v_token_quantity numeric := 0;
    v_gross_token_quantity numeric := 0;
    v_token_fee numeric := 0;
    v_gross_amount numeric := 0;
    v_spread numeric := 0;
    v_document_prefix text;
    v_sub_transaction_type
        public."TransactionType" :=
            'gold_token_buy_sub_tx'::public."TransactionType";
begin
    if coalesce(auth.role(), '') <> 'service_role' then
        raise exception using errcode = '42501', message = 'SERVICE_ROLE_REQUIRED';
    end if;
    v_stage := 'Validate and read the processing transaction';
    /*
     * Validate and read the processing transaction.
     */
    select transaction_state_record.*
    into v_transaction_state
    from public.transaction_state
        transaction_state_record
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
    limit 1
    for update;
    if not found then
        raise exception
            'INVALID_TRANSACTION_STATE';
    end if;
    if v_transaction_state.transaction_data
       is distinct from p_transaction
    then
        raise exception
            'TRANSACTION_STATE_DATA_MISMATCH';
    end if;
    if p_transaction ->> 'v' is distinct from
       'v7'
    then
        raise exception
            'OPERATION_NOT_ALLOWED';
    end if;
    if v_transaction_state.reference is distinct from p_transaction ->> 'r'
       or nullif(btrim(p_transaction ->> 'r'), '') is null then
        raise exception 'TRANSACTION_REFERENCE_MISMATCH';
    end if;
    v_stage := 'Validate the buyer role';
    /*
     * Validate the buyer role.
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
    v_stage := 'Parse signed transaction fields';
    /*
     * Parse signed transaction fields.
     */
    v_amount :=
        (p_transaction ->> 'a')::numeric /
        100;
    if v_amount is null or v_amount::text in ('NaN', 'Infinity', '-Infinity') or v_amount <= 0 then
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
    v_stage := 'calculate exact gold-buy pricing';
    /*
     * Calculate the exact Gold Buy price used by this
     * transaction.
     *
     * Do not fetch the Gold market price independently.
     * calculate_gold_buy_pricing is the pricing source of
     * truth and returns the Buy price in gold_price.
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
    v_stage := 'Fetch buyer and treasury';
    /*
     * Fetch buyer and treasury.
     */
    v_user :=
        public.fetch_user_by_id(
            p_user_id
        );
    v_treasury :=
        public.fetch_country_treasury(
            p_country_code
        );
    if v_user.id is null or v_user.status is distinct from 'active'::public."UserStatus" then
        raise exception 'USER_NOT_AUTHORIZED';
    end if;
    if v_treasury.id is null or v_treasury.status is distinct from 'active'::public."UserStatus"
       or v_treasury.country_code is distinct from p_country_code then
        raise exception 'TREASURY_NOT_AUTHORIZED';
    end if;
    if v_treasury.wallet_index < 0 then
        raise exception 'INVALID_WALLET_INDEX';
    end if;
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
    v_stage := 'Fetch fiscal period';
    /*
     * Fetch fiscal period.
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
    v_stage := 'Fetch fiat mappings';
    /*
     * Fetch fiat mappings.
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
    v_stage := 'Fetch gold-token mappings';
    /*
     * Fetch gold-token mappings.
     */
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
    v_stage := 'Build fiat components';
    /*
     * Build fiat components.
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
    v_stage := 'Build reversed gold-token components';
    /*
     * Build reversed gold-token components.
     */
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
    v_stage := 'Extract net and gross token quantities';
    /*
     * Extract net and gross token quantities.
     */
    select
        coalesce(
            component.debit_amount,
            0
        ),
        coalesce(
            component.credit_amount,
            0
        )
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
            coalesce(
                v_token_quantity,
                0
            )
        );
    v_gross_token_quantity :=
        public.round_down(
            coalesce(
                v_gross_token_quantity,
                0
            )
        );
    if v_token_quantity <= 0 then
        raise exception
            'INVALID_QUANTITY';
    end if;
    v_stage := 'Extract the token-denominated transaction fee';
    /*
     * Extract the token-denominated transaction fee.
     */
    select coalesce(
        component.debit_amount,
        0
    )
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
            coalesce(
                v_token_fee,
                0
            )
        );
    v_stage := 'Extract the fiat gross amount';
    /*
     * Extract the fiat gross amount.
     */
    select coalesce(
        component.debit_amount,
        0
    )
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
        coalesce(
            v_gross_amount,
            0
        );
    if v_gross_amount <= 0 then
        raise exception
            'INVALID_GROSS_AMOUNT';
    end if;
    v_stage := 'Extract trading spread';
    /*
     * Extract trading spread.
     */
    select coalesce(
        component.credit_amount,
        0
    )
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
        coalesce(
            v_spread,
            0
        );
    v_fiat_components := public.validate_components(v_fiat_components);
    v_token_components := public.validate_components(v_token_components);
    if v_token_fee < 0 or v_spread < 0 then
        raise exception 'INVALID_POSTING_COMPONENT_AMOUNT';
    end if;
    v_document_prefix :=
        public.fetch_transaction_doc_num_prefix(
            'gold_token_buy'::public."TransactionType"
        );
    if nullif(btrim(v_document_prefix), '') is null then
        raise exception 'DOCUMENT_PREFIX_NOT_FOUND';
    end if;
    v_stage := 'return preparation';
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
        v_spread::text;
exception
    when others then
        get stacked diagnostics
            v_error_state = returned_sqlstate,
            v_error_message = message_text,
            v_error_detail = pg_exception_detail,
            v_error_hint = pg_exception_hint,
            v_error_context = pg_exception_context;
        raise exception using
            errcode = v_error_state,
            message = format('GOLD_BUY_FAILED at [%s]: %s', v_stage, v_error_message),
            detail = concat_ws(E'\n', nullif(v_error_detail, ''), nullif(v_error_context, '')),
            hint = coalesce(nullif(v_error_hint, ''), 'Check the gold-buy stage reported in the error');
end;
$function$;
REVOKE ALL ON FUNCTION public.prepare_gold_buy(text, jsonb, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.prepare_gold_buy(text, jsonb, text, text) TO service_role;
-- Ngoda Gold Buy: preserves the uploaded function parameter and result signatures.
-- Chain selection uses the signed transaction.chain, with the supplied v7 Chiado default.
-- The supplied sources contain no chain configuration schema; supported-chain selection
-- and receipt verification must be enforced by the service-role Edge Function.
CREATE OR REPLACE FUNCTION public.record_gold_buy_blockchain_transaction(p_user_id text, p_transaction jsonb, p_country_code text, p_transaction_state_id text, p_tx_hash text, p_explorer_url text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
    v_stage text := 'initialization';
    v_error_state text;
    v_error_message text;
    v_error_detail text;
    v_error_hint text;
    v_error_context text;
    v_preparation record;
    v_user public.users%rowtype;
    v_reference text;
    v_blockchain_transaction_id text;
begin
    if coalesce(auth.role(), '') <> 'service_role' then
        raise exception using errcode = '42501', message = 'SERVICE_ROLE_REQUIRED';
    end if;
    if p_tx_hash is null
       or p_tx_hash !~
          '^0x[0-9a-fA-F]{64}$'
    then
        raise exception
            'INVALID_BLOCKCHAIN_TRANSACTION_HASH';
    end if;
    if p_explorer_url is null
       or btrim(p_explorer_url) = ''
    then
        raise exception
            'BLOCKCHAIN_EXPLORER_URL_MISSING';
    end if;
    v_reference :=
        nullif(
            btrim(p_transaction ->> 'r'),
            ''
        );
    if v_reference is null then
        raise exception
            'REFERENCE_MISSING';
    end if;
    v_stage := 'Recalculate trusted gold-buy values from the';
    /*
     * Recalculate trusted gold-buy values from the
     * processing transaction.
     */
    select preparation.*
    into v_preparation
    from public.prepare_gold_buy(
        p_user_id,
        p_transaction,
        p_country_code,
        p_transaction_state_id
    ) as preparation;
    if not found then
        raise exception
            'GOLD_BUY_PREPARATION_NOT_FOUND';
    end if;
    v_user :=
        public.fetch_user_by_id(
            p_user_id
        );
    if p_transaction ? 'chain' and (
        jsonb_typeof(p_transaction -> 'chain') is distinct from 'string'
        or coalesce(p_transaction ->> 'chain', '') !~ '^[a-zA-Z][a-zA-Z0-9_-]{0,63}$'
    ) then
        raise exception 'INVALID_BLOCKCHAIN_CHAIN';
    end if;
    v_stage := 'insert database record';
    insert into public.blockchain_transaction (
        fiscal_year,
        period,
        country_code,
        tx_hash,
        document_number,
        reference,
        transaction_type,
        chain,
        sender,
        receiver,
        quantity,
        gross_amount,
        net_amount,
        fee_amount,
        currency_code,
        explorer_url,
        status,
        created_by,
        description
    )
    values (
        v_preparation.fiscal_year,
        v_preparation.period,
        p_country_code,
        lower(p_tx_hash),
        null,
        v_reference,
        'gold_token_buy'::public."TransactionType",
        coalesce(nullif(lower(btrim(p_transaction ->> 'chain')), ''), 'chiado'),
        v_preparation.treasury_wallet_address,
        v_preparation.user_wallet_address,
        v_preparation.token_quantity::numeric,
        v_preparation.input_amount::numeric,
        0,
        v_preparation.token_fee::numeric,
        v_preparation.input_currency,
        p_explorer_url,
        'pending'::public."BlockchainTxStatus",
        p_user_id,
        'User ' ||
        coalesce(
            v_user.email,
            v_user.phone,
            v_user.id
        ) ||
        ' purchased ' ||
        v_preparation.token_quantity ||
        'g Gold tokens'
    )
    returning id::text
    into v_blockchain_transaction_id;
    if v_blockchain_transaction_id is null then
        raise exception 'BLOCKCHAIN_TRANSACTION_RECORD_FAILED';
    end if;
    return v_blockchain_transaction_id;
exception
    when unique_violation then
        raise exception using
            errcode = '23505',
            message =
                'BLOCKCHAIN_TRANSACTION_REPLAY';
    when others then
        get stacked diagnostics
            v_error_state = returned_sqlstate,
            v_error_message = message_text,
            v_error_detail = pg_exception_detail,
            v_error_hint = pg_exception_hint,
            v_error_context = pg_exception_context;
        raise exception using
            errcode = v_error_state,
            message = format('GOLD_BUY_FAILED at [%s]: %s', v_stage, v_error_message),
            detail = concat_ws(E'\n', nullif(v_error_detail, ''), nullif(v_error_context, '')),
            hint = coalesce(nullif(v_error_hint, ''), 'Check the gold-buy stage reported in the error');
end;
$function$;
REVOKE ALL ON FUNCTION public.record_gold_buy_blockchain_transaction(text, jsonb, text, text, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_gold_buy_blockchain_transaction(text, jsonb, text, text, text, text) TO service_role;
-- Ngoda Gold Buy: preserves the uploaded function parameter and result signatures.
-- Chain selection uses the signed transaction.chain, with the supplied v7 Chiado default.
-- The supplied sources contain no chain configuration schema; supported-chain selection
-- and receipt verification must be enforced by the service-role Edge Function.
CREATE OR REPLACE FUNCTION public.complete_gold_buy(p_user_id text, p_transaction jsonb, p_country_code text, p_transaction_state_id text, p_blockchain_transaction_id text, p_ip_address text DEFAULT NULL::text)
 RETURNS TABLE(success boolean, document_number text, quantity text, total_spent text, explorer_url text, receiver_notification_id text, device_tokens text[], push_title text, push_body text, push_reference text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
    v_preparation record;
    v_transaction_state
        public.transaction_state%rowtype;
    v_blockchain_transaction
        public.blockchain_transaction%rowtype;
    v_user public.users%rowtype;
    v_treasury public.users%rowtype;
    v_fiat_mappings
        public.transaction_gl_mapping[];
    v_token_mappings
        public.transaction_gl_mapping[];
    v_fiat_components
        public.posting_component[];
    v_token_components
        public.posting_component[];
    v_receiver_notification
        public.notification_message;
    v_device_tokens text[] :=
        array[]::text[];
    v_document_number text;
    v_sub_document_number text;
    v_fiat_transaction_id bigint;
    v_token_transaction_id bigint;
    v_receiver_notification_id text;
    v_sub_transaction_type
        public."TransactionType" :=
            'gold_token_buy_sub_tx'::public."TransactionType";
    v_stage text := 'initialization';
    v_error_state text;
    v_error_message text;
    v_error_detail text;
    v_error_hint text;
    v_error_context text;
begin
    if coalesce(auth.role(), '') <> 'service_role' then
        raise exception using errcode = '42501', message = 'SERVICE_ROLE_REQUIRED';
    end if;
    /*
     * Lock the processing transaction state.
     */
    v_stage :=
        'validate and lock transaction state';
    select transaction_state_record.*
    into v_transaction_state
    from public.transaction_state
        transaction_state_record
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
    limit 1
    for update;
    if not found then
        raise exception
            'INVALID_TRANSACTION_STATE';
    end if;
    if v_transaction_state.transaction_data
       is distinct from p_transaction
    then
        raise exception
            'TRANSACTION_STATE_DATA_MISMATCH';
    end if;
    /*
     * Lock and validate the pending blockchain row.
     */
    v_stage :=
        'validate and lock blockchain transaction';
    select blockchain_record.*
    into v_blockchain_transaction
    from public.blockchain_transaction
        blockchain_record
    where blockchain_record.id::text =
          p_blockchain_transaction_id
      and blockchain_record.created_by =
          p_user_id
      and blockchain_record.country_code =
          p_country_code
      and blockchain_record.reference =
          p_transaction ->> 'r'
      and blockchain_record.transaction_type =
          'gold_token_buy'::public."TransactionType"
      and blockchain_record.status =
          'pending'::public."BlockchainTxStatus"
    limit 1
    for update;
    if not found then
        raise exception
            'PENDING_BLOCKCHAIN_TRANSACTION_NOT_FOUND';
    end if;
    /*
     * Recalculate trusted pricing and quantities.
     */
    v_stage := 'prepare gold buy';
    select preparation.*
    into v_preparation
    from public.prepare_gold_buy(
        p_user_id,
        p_transaction,
        p_country_code,
        p_transaction_state_id
    ) as preparation;
    if not found then
        raise exception
            'GOLD_BUY_PREPARATION_NOT_FOUND';
    end if;
    /*
     * Validate the transaction Gold price carried forward
     * from prepare_gold_buy.
     *
     * Do not fetch the current Gold market price again here.
     */
    if coalesce(
        v_preparation.gold_price::numeric,
        0
    ) <= 0
    then
        raise exception
            'INVALID_GOLD_PRICE';
    end if;
    /*
     * Confirm the blockchain row matches the trusted
     * preparation result.
     */
    v_stage :=
        'validate blockchain transaction values';
    if v_blockchain_transaction.chain::text is distinct from
       coalesce(nullif(lower(btrim(p_transaction ->> 'chain')), ''), 'chiado') then
        raise exception 'BLOCKCHAIN_CHAIN_MISMATCH';
    end if;
    if v_blockchain_transaction.currency_code is distinct from v_preparation.input_currency then
        raise exception 'BLOCKCHAIN_CURRENCY_MISMATCH';
    end if;
    if v_blockchain_transaction.net_amount is distinct from 0::numeric then
        raise exception 'BLOCKCHAIN_NET_AMOUNT_MISMATCH';
    end if;
    if v_blockchain_transaction.quantity
       is distinct from
       v_preparation.token_quantity::numeric
    then
        raise exception
            'BLOCKCHAIN_QUANTITY_MISMATCH';
    end if;
    if v_blockchain_transaction.gross_amount
       is distinct from
       v_preparation.input_amount::numeric
    then
        raise exception
            'BLOCKCHAIN_GROSS_AMOUNT_MISMATCH';
    end if;
    if v_blockchain_transaction.fee_amount
       is distinct from
       v_preparation.token_fee::numeric
    then
        raise exception
            'BLOCKCHAIN_FEE_MISMATCH';
    end if;
    if lower(
        v_blockchain_transaction.sender
    ) is distinct from lower(
        v_preparation.treasury_wallet_address
    ) then
        raise exception
            'BLOCKCHAIN_SENDER_MISMATCH';
    end if;
    if lower(
        v_blockchain_transaction.receiver
    ) is distinct from lower(
        v_preparation.user_wallet_address
    ) then
        raise exception
            'BLOCKCHAIN_RECEIVER_MISMATCH';
    end if;
    /*
     * Fetch participants.
     */
    v_stage := 'fetch participants';
    v_user :=
        public.fetch_user_by_id(
            p_user_id
        );
    v_treasury :=
        public.fetch_country_treasury(
            p_country_code
        );
    /*
     * Rebuild fiat and token components for posting.
     */
    v_stage := 'fetch fiat mappings';
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
    v_stage := 'fetch token mappings';
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
    v_stage := 'build fiat components';
    v_fiat_components :=
        public.build_posting_components(
            'gold_token_buy'::public."TransactionType",
            v_preparation.input_amount::numeric,
            v_fiat_mappings,
            p_country_code,
            v_preparation.input_currency,
            false
        );
    v_stage := 'build token components';
    v_token_components :=
        public.build_posting_components(
            v_sub_transaction_type,
            v_preparation.input_amount::numeric,
            v_token_mappings,
            p_country_code,
            v_preparation.input_currency,
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
     * Build buyer notification.
     */
    v_stage := 'validate posting components';
    v_fiat_components := public.validate_components(v_fiat_components);
    v_token_components := public.validate_components(v_token_components);
    if not exists (
        select 1 from unnest(v_fiat_components) c
        where c.component_type = 'principal'::public."ComponentType"
          and c.debit_amount = v_preparation.gross_amount::numeric
    ) or not exists (
        select 1 from unnest(v_token_components) c
        where c.component_type = 'principal'::public."ComponentType"
          and public.round_down(c.debit_amount) = v_preparation.token_quantity::numeric
          and public.round_down(c.credit_amount) = v_preparation.gross_token_quantity::numeric
    ) then
        raise exception 'POSTING_PREPARATION_MISMATCH';
    end if;
    v_stage := 'create receiver notification';
    v_receiver_notification :=
        public.create_notification_message(
            p_country_code,
            'gold_token_buy'::public."TransactionType",
            'receiver'::public."NotificationAudience",
            v_preparation.gross_amount::numeric,
            'USD',
            p_transaction ->> 'r',
            v_preparation.token_quantity::numeric,
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
    v_stage := 'fetch receiver device tokens';
    v_device_tokens :=
        coalesce(
            public.fetch_device_tokens(
                p_country_code,
                v_user.id
            ),
            array[]::text[]
        );
    /*
     * Generate the main accounting document.
     */
    v_stage := 'generate document number';
    v_document_number :=
        public.generate_document_number(
            v_preparation.document_prefix,
            v_preparation.fiscal_year,
            v_preparation.period,
            p_country_code
        );
    /*
     * Fiat financial transaction.
     */
    v_stage :=
        'insert fiat financial transaction';
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
        v_preparation.fiscal_year,
        p_transaction ->> 'r',
        v_preparation.period,
        'gold_token_buy'::public."TransactionType",
        'User ' ||
        coalesce(
            v_user.email,
            v_user.phone,
            v_user.id
        ) ||
        ' purchased ' ||
        v_preparation.token_quantity ||
        'g Gold tokens at USD ' ||
        v_preparation.gold_price ||
        '/g',
        p_user_id,
        v_preparation.gross_amount::numeric,
        'usd',
        p_country_code
    )
    returning id
    into v_fiat_transaction_id;
    v_stage := 'post fiat financial entries';
    perform *
    from public.post_financial_entries(
        p_document_number =>
            v_document_number,
        p_country_code =>
            p_country_code,
        p_transaction_id =>
            v_fiat_transaction_id,
        p_transaction_type =>
            'gold_token_buy'::public."TransactionType",
        p_created_by =>
            p_user_id,
        p_components =>
            v_fiat_components,
        p_mappings =>
            v_fiat_mappings,
        p_currency_code =>
            'usd',
        p_fiscal_year =>
            v_preparation.fiscal_year,
        p_period =>
            v_preparation.period,
        p_reference =>
            p_transaction ->> 'r',
        p_deposit_type =>
            null
    );
    /*
     * Move fiat from the buyer's customer wallet to
     * the treasury USD wallet.
     */
    v_stage := 'post fiat wallet entries';
    perform *
    from public.post_wallet_entries(
        p_fiscal_year =>
            v_preparation.fiscal_year,
        p_period =>
            v_preparation.period,
        p_document_number =>
            v_document_number,
        p_reference =>
            p_transaction ->> 'r',
        p_receiver_id =>
            v_treasury.id,
        p_sender_id =>
            v_user.id,
        p_transaction_type =>
            'gold_token_buy'::public."TransactionType",
        p_credit_amount =>
            v_preparation.gross_amount::numeric,
        p_debit_amount =>
            v_preparation.gross_amount::numeric,
        p_sender_wallet_owner =>
            'customer'::public."WalletOwnerType",
        p_receiver_wallet_owner =>
            'treasury'::public."WalletOwnerType",
        p_currency_code =>
            'usd',
        p_country_code =>
            p_country_code,
        p_audit_action_type =>
            'token_bought'::public."AuditActionType",
        p_treasury_id =>
            null,
        p_fee_amount =>
            0,
        p_ip_address =>
            p_ip_address,
        p_receiver_notification =>
            null,
        p_sender_notification =>
            null
    );
    /*
     * Gold-token sub-document.
     */
    v_sub_document_number :=
        v_document_number || '-01';
    v_stage :=
        'insert token financial transaction';
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
        v_sub_document_number,
        v_preparation.fiscal_year,
        (p_transaction ->> 'r') || '-01',
        v_preparation.period,
        v_sub_transaction_type,
        'User ' ||
        coalesce(
            v_user.email,
            v_user.phone,
            v_user.id
        ) ||
        ' purchased ' ||
        v_preparation.gross_amount ||
        ' USD Gold tokens',
        p_user_id,
        v_preparation.gross_token_quantity::numeric,
        'gold',
        p_country_code
    )
    returning id
    into v_token_transaction_id;
    v_stage := 'post token financial entries';
    perform *
    from public.post_financial_entries(
        p_document_number =>
            v_sub_document_number,
        p_country_code =>
            p_country_code,
        p_transaction_id =>
            v_token_transaction_id,
        p_transaction_type =>
            v_sub_transaction_type,
        p_created_by =>
            p_user_id,
        p_components =>
            v_token_components,
        p_mappings =>
            v_token_mappings,
        p_currency_code =>
            'gold',
        p_fiscal_year =>
            v_preparation.fiscal_year,
        p_period =>
            v_preparation.period,
        p_reference =>
            (p_transaction ->> 'r') || '-01',
        p_deposit_type =>
            null
    );
    /*
     * Move the net token quantity from treasury to buyer.
     */
    v_stage := 'post token wallet entries';
    select result.receiver_notification_id
    into v_receiver_notification_id
    from public.post_wallet_entries(
        p_fiscal_year =>
            v_preparation.fiscal_year,
        p_period =>
            v_preparation.period,
        p_document_number =>
            v_sub_document_number,
        p_reference =>
            (p_transaction ->> 'r') || '-01',
        p_receiver_id =>
            v_user.id,
        p_sender_id =>
            v_treasury.id,
        p_transaction_type =>
            'gold_token_buy'::public."TransactionType",
        p_credit_amount =>
            v_preparation.token_quantity::numeric,
        p_debit_amount =>
            v_preparation.token_quantity::numeric,
        p_sender_wallet_owner =>
            'treasury'::public."WalletOwnerType",
        p_receiver_wallet_owner =>
            'customer'::public."WalletOwnerType",
        p_currency_code =>
            'gold',
        p_country_code =>
            p_country_code,
        p_audit_action_type =>
            'token_bought'::public."AuditActionType",
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
    ) as result;
    /*
     * Complete the blockchain row.
     */
    v_stage :=
        'complete blockchain transaction';
    update public.blockchain_transaction
    set
        document_number =
            v_sub_document_number,
        status =
            'completed'::public."BlockchainTxStatus"
    where id::text =
          p_blockchain_transaction_id
      and status =
          'pending'::public."BlockchainTxStatus";
    if not found then
        raise exception
            'BLOCKCHAIN_TRANSACTION_UPDATE_FAILED';
    end if;
    /*
     * Mark transaction state successful.
     */
    v_stage := 'update transaction state';
    update public.transaction_state
    set
        user_id =
            v_user.id,
        status =
            'success'::public."TransactionStatus",
        message =
            null,
        updated_at =
            now()
    where id =
          p_transaction_state_id
      and created_by =
          p_user_id
      and transaction_type =
          'gold_token_buy'::public."TransactionType"
      and status =
          'processing'::public."TransactionStatus";
    if not found then
        raise exception
            'TRANSACTION_STATE_UPDATE_FAILED';
    end if;
    return query
    select
        true,
        v_document_number,
        v_preparation.token_quantity,
        v_preparation.gross_amount,
        v_blockchain_transaction.explorer_url,
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
                    'GOLD_BUY_FAILED at [%s]: %s',
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
                    'Check the gold-buy stage reported in the error'
                );
end;
$function$;
REVOKE ALL ON FUNCTION public.complete_gold_buy(text, jsonb, text, text, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.complete_gold_buy(text, jsonb, text, text, text, text) TO service_role;

commit;
