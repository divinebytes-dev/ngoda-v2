BEGIN;

-- Reusable writer: the caller supplies a complete, already calculated context.
-- No prices, fees, spreads or GL mappings are fetched/calculated here.
CREATE OR REPLACE FUNCTION public.save_gold_buy_execution_context(
 p_transaction_state_id text,p_context jsonb
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $function$
DECLARE
 v_s public.transaction_state%rowtype;
 v_p jsonb;
 v_fiat public.posting_component[];
 v_gold public.posting_component[];
 v_user public.users%rowtype;
 v_treasury public.users%rowtype;
 v_principal public.posting_component;
 v_map public.transaction_gl_mapping[];
 v_items jsonb;
BEGIN
 IF coalesce(auth.role(),'')<>'service_role' THEN
  RAISE EXCEPTION USING errcode='42501',message='SERVICE_ROLE_REQUIRED'; END IF;
 SELECT * INTO v_s FROM public.transaction_state WHERE id=p_transaction_state_id FOR UPDATE;
 IF NOT FOUND OR v_s.transaction_type IS DISTINCT FROM 'gold_token_buy'::public."TransactionType"
 OR v_s.status IS DISTINCT FROM 'processing'::public."TransactionStatus" THEN
  RAISE EXCEPTION 'PROCESSING_GOLD_BUY_STATE_REQUIRED'; END IF;
 IF v_s.gold_buy_preparation IS NOT NULL THEN
  IF v_s.gold_buy_preparation IS DISTINCT FROM p_context THEN
   RAISE EXCEPTION 'GOLD_BUY_PREPARATION_IS_IMMUTABLE'; END IF;
  RETURN;
 END IF;
 v_p:=p_context->'preparation';
 IF p_context IS NULL OR jsonb_typeof(p_context) IS DISTINCT FROM 'object'
 OR p_context->>'schema_version' IS DISTINCT FROM '1'
 OR p_context->>'transaction_state_id' IS DISTINCT FROM v_s.id
 OR p_context->'transaction_data' IS DISTINCT FROM v_s.transaction_data
 OR jsonb_typeof(v_p) IS DISTINCT FROM 'object'
 OR v_p->>'user_id' IS DISTINCT FROM v_s.user_id
 OR v_s.created_by IS DISTINCT FROM v_s.user_id
 OR v_p->>'country_code' IS DISTINCT FROM v_s.country_code
 OR v_p->>'blockchain_code' IS DISTINCT FROM v_s.blockchain_code
 OR v_p->>'input_currency' IS DISTINCT FROM lower(v_s.transaction_data->>'c')
 OR (v_p->>'input_amount')::numeric IS DISTINCT FROM (v_s.transaction_data->>'a')::numeric/100
 OR (v_p->>'fiscal_year')::integer IS NULL OR (v_p->>'period')::integer IS NULL
 OR (v_p->>'period')::integer NOT BETWEEN 1 AND 12
 OR nullif(btrim(v_p->>'document_prefix'),'') IS NULL THEN
  RAISE EXCEPTION 'INVALID_GOLD_BUY_EXECUTION_CONTEXT'; END IF;
 IF v_p->>'gold_price' IS NULL THEN
  IF p_context->>'origin' IS DISTINCT FROM 'historical_reconstruction' THEN
   RAISE EXCEPTION 'ORIGINAL_GOLD_PRICE_REQUIRED'; END IF;
 ELSIF (v_p->>'gold_price')::numeric<=0 OR (v_p->>'gold_price') IN ('NaN','Infinity','-Infinity') THEN
  RAISE EXCEPTION 'INVALID_GOLD_PRICE';
 END IF;
 IF coalesce((v_p->>'token_quantity')::numeric,0)<=0
 OR coalesce((v_p->>'gross_amount')::numeric,0)<=0
 OR coalesce((v_p->>'token_fee')::numeric,-1)<0
 OR coalesce((v_p->>'gross_token_quantity')::numeric,0)<(v_p->>'token_quantity')::numeric
 OR v_p->>'token_quantity' IN ('NaN','Infinity','-Infinity')
 OR v_p->>'gross_amount' IN ('NaN','Infinity','-Infinity')
 OR v_p->>'token_fee' IN ('NaN','Infinity','-Infinity')
 OR v_p->>'gross_token_quantity' IN ('NaN','Infinity','-Infinity') THEN
  RAISE EXCEPTION 'INVALID_SAVED_GOLD_BUY_AMOUNTS'; END IF;
 SELECT * INTO v_user FROM public.users WHERE id=v_s.user_id;
 SELECT * INTO v_treasury FROM public.users WHERE id=v_p->>'treasury_id';
 IF v_user.id IS NULL OR v_treasury.id IS NULL
 OR v_user.country_code IS DISTINCT FROM v_s.country_code
 OR v_treasury.country_code IS DISTINCT FROM v_s.country_code
 OR lower(v_user.wallet_address) IS DISTINCT FROM lower(v_p->>'user_wallet_address')
 OR lower(v_treasury.wallet_address) IS DISTINCT FROM lower(v_p->>'treasury_wallet_address')
 OR v_treasury.wallet_index IS DISTINCT FROM (v_p->>'treasury_wallet_index')::bigint THEN
  RAISE EXCEPTION 'SAVED_CONTEXT_PARTICIPANT_MISMATCH'; END IF;
 FOREACH v_items IN ARRAY ARRAY[p_context->'fiat_mappings',p_context->'token_mappings'] LOOP
  IF jsonb_typeof(v_items) IS DISTINCT FROM 'array' OR jsonb_array_length(v_items)=0 THEN
   RAISE EXCEPTION 'SAVED_GL_MAPPINGS_REQUIRED'; END IF;
  SELECT array_agg(jsonb_populate_record(null::public.transaction_gl_mapping,e.value)) INTO v_map
  FROM jsonb_array_elements(v_items) e;
  IF (SELECT count(*) FROM unnest(v_map) m WHERE m.component_type='principal'::public."ComponentType")<>1 THEN
   RAISE EXCEPTION 'ONE_PRINCIPAL_MAPPING_REQUIRED'; END IF;
 END LOOP;
 IF jsonb_typeof(p_context->'fiat_components') IS DISTINCT FROM 'array'
 OR jsonb_typeof(p_context->'token_components') IS DISTINCT FROM 'array'
 OR jsonb_array_length(p_context->'fiat_components')=0
 OR jsonb_array_length(p_context->'token_components')=0 THEN
  RAISE EXCEPTION 'SAVED_POSTING_COMPONENTS_REQUIRED'; END IF;
 SELECT array_agg(jsonb_populate_record(null::public.posting_component,e.value) ORDER BY e.ordinality)
 INTO v_fiat FROM jsonb_array_elements(p_context->'fiat_components') WITH ORDINALITY e(value,ordinality);
 SELECT array_agg(jsonb_populate_record(null::public.posting_component,e.value) ORDER BY e.ordinality)
 INTO v_gold FROM jsonb_array_elements(p_context->'token_components') WITH ORDINALITY e(value,ordinality);
 PERFORM public.validate_components(v_fiat);
 PERFORM public.validate_components(v_gold);
 IF (SELECT count(*) FROM unnest(v_fiat) c WHERE c.component_type='principal'::public."ComponentType")<>1
 OR (SELECT count(*) FROM unnest(v_gold) c WHERE c.component_type='principal'::public."ComponentType")<>1 THEN
  RAISE EXCEPTION 'ONE_PRINCIPAL_COMPONENT_REQUIRED'; END IF;
 SELECT c.* INTO v_principal FROM unnest(v_fiat) c WHERE c.component_type='principal'::public."ComponentType";
 IF v_principal.debit_amount IS DISTINCT FROM (v_p->>'gross_amount')::numeric THEN
  RAISE EXCEPTION 'SAVED_FIAT_PRINCIPAL_MISMATCH'; END IF;
 SELECT c.* INTO v_principal FROM unnest(v_gold) c WHERE c.component_type='principal'::public."ComponentType";
 IF v_principal.debit_amount IS DISTINCT FROM (v_p->>'token_quantity')::numeric
 OR v_principal.credit_amount IS DISTINCT FROM (v_p->>'gross_token_quantity')::numeric THEN
  RAISE EXCEPTION 'SAVED_TOKEN_PRINCIPAL_MISMATCH'; END IF;
 IF EXISTS(SELECT 1 FROM public.financial_transaction f
 WHERE f.reference IN (v_s.reference,v_s.reference||'-01'))
 OR EXISTS(SELECT 1 FROM public.wallet_entry w WHERE w.reference IN (v_s.reference,v_s.reference||'-01')) THEN
  RAISE EXCEPTION 'EXISTING_ACCOUNTING_REQUIRES_REVIEW'; END IF;
 UPDATE public.transaction_state SET gold_buy_preparation=p_context,updated_at=now()
 WHERE id=v_s.id AND gold_buy_preparation IS NULL;
END;
$function$;
ALTER FUNCTION public.save_gold_buy_execution_context(text,jsonb) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.save_gold_buy_execution_context(text,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.save_gold_buy_execution_context(text,jsonb) TO service_role;


CREATE OR REPLACE FUNCTION public.complete_gold_buy(p_user_id text, p_transaction jsonb, p_country_code text, p_transaction_state_id text, p_blockchain_transaction_id text, p_blockchain_code text, p_ip_address text DEFAULT NULL::text)
 RETURNS TABLE(success boolean, document_number text, quantity text, total_spent text, explorer_url text, receiver_notification_id text, device_tokens text[], push_title text, push_body text, push_reference text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
    v_blockchain_code text;
    v_saved jsonb;
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
    v_blockchain_code := lower(nullif(btrim(p_blockchain_code), ''));
    if v_blockchain_code is null then
        raise exception 'BLOCKCHAIN_CODE_REQUIRED';
    end if;
    perform 1 from public.supported_blockchain b
    where b.code = v_blockchain_code and b.is_active = true
      and exists (
        select 1 from public.supported_blockchain_network n
        where n.blockchain_id = b.id and n.is_active = true
      );
    if not found then
        raise exception 'BLOCKCHAIN_NOT_FOUND_OR_INACTIVE';
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
    if v_transaction_state.blockchain_code is distinct from v_blockchain_code then
        raise exception 'TRANSACTION_BLOCKCHAIN_MISMATCH';
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
     * Read the existing immutable preparation. Never calculate a new quote
     * after a blockchain row has been recorded.
     */
    v_saved := v_transaction_state.gold_buy_preparation;
    if v_saved is null then
        raise exception 'GOLD_BUY_PREPARATION_MISSING_RECONCILIATION_REQUIRED';
    end if;
    v_stage := 'read saved gold buy';
    select preparation.*
    into v_preparation
    from public.prepare_gold_buy(
        p_user_id,
        p_transaction,
        p_country_code,
        p_transaction_state_id,
        v_blockchain_code
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
    if v_preparation.gold_price is null then
        if v_saved ->> 'origin' is distinct from 'historical_reconstruction' then
            raise exception 'INVALID_GOLD_PRICE';
        end if;
    elsif v_preparation.gold_price::numeric <= 0
       or v_preparation.gold_price in ('NaN','Infinity','-Infinity') then
        raise exception 'INVALID_GOLD_PRICE';
    end if;
    /*
     * Confirm the blockchain row matches the trusted
     * preparation result.
     */
    v_stage :=
        'validate blockchain transaction values';
    if v_blockchain_transaction.chain::text is distinct from
       v_blockchain_code then
        raise exception 'BLOCKCHAIN_CHAIN_MISMATCH';
    end if;
    if v_blockchain_transaction.blockchain_code is distinct from v_blockchain_code then
        raise exception 'BLOCKCHAIN_CODE_MISMATCH';
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
        raise exception using message = 'BLOCKCHAIN_QUANTITY_MISMATCH',
            detail = format('Saved preparation quantity=%s; blockchain record quantity=%s',
                v_preparation.token_quantity, v_blockchain_transaction.quantity);
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
    /* Load the exact components and GL mappings saved before signing. */
    v_stage := 'load saved posting components and mappings';
    select array_agg(
        jsonb_populate_record(null::public.transaction_gl_mapping, e.value) order by e.ordinality
    ) into v_fiat_mappings
    from jsonb_array_elements(v_saved -> 'fiat_mappings') with ordinality e(value, ordinality);
    if v_fiat_mappings is null or cardinality(v_fiat_mappings) = 0 then
        raise exception 'SAVED_GOLD_BUY_FIAT_MAPPINGS_MISSING';
    end if;
    select array_agg(
        jsonb_populate_record(null::public.transaction_gl_mapping, e.value) order by e.ordinality
    ) into v_token_mappings
    from jsonb_array_elements(v_saved -> 'token_mappings') with ordinality e(value, ordinality);
    if v_token_mappings is null or cardinality(v_token_mappings) = 0 then
        raise exception 'SAVED_GOLD_BUY_TOKEN_MAPPINGS_MISSING';
    end if;
    select array_agg(
        jsonb_populate_record(null::public.posting_component, e.value) order by e.ordinality
    ) into v_fiat_components
    from jsonb_array_elements(v_saved -> 'fiat_components') with ordinality e(value, ordinality);
    if v_fiat_components is null or cardinality(v_fiat_components) = 0 then
        raise exception 'SAVED_GOLD_BUY_FIAT_COMPONENTS_MISSING';
    end if;
    select array_agg(
        jsonb_populate_record(null::public.posting_component, e.value) order by e.ordinality
    ) into v_token_components
    from jsonb_array_elements(v_saved -> 'token_components') with ordinality e(value, ordinality);
    if v_token_components is null or cardinality(v_token_components) = 0 then
        raise exception 'SAVED_GOLD_BUY_TOKEN_COMPONENTS_MISSING';
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
        'g Gold tokens' ||
        case when v_preparation.gold_price is not null
             then ' at USD ' || v_preparation.gold_price || '/g'
             else ' (historical context reconstruction)' end,
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
            null,
        p_blockchain_code => null
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
            null,
        p_blockchain_code => v_blockchain_code
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
      and chain = v_blockchain_code
      and blockchain_code = v_blockchain_code
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
      and blockchain_code = v_blockchain_code
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

ALTER FUNCTION public.complete_gold_buy(text,jsonb,text,text,text,text,text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.complete_gold_buy(text,jsonb,text,text,text,text,text) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.complete_gold_buy(text,jsonb,text,text,text,text,text) TO service_role;

-- Owner-only context builder. No prices or posting components are calculated.
CREATE OR REPLACE FUNCTION public.build_gold_buy_recovery_context(
 p_executor_id text, p_blockchain_transaction_id text
) RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path TO '' AS $function$
DECLARE
 v_executor public.users%rowtype;
 v_b public.blockchain_transaction%rowtype;
 v_s public.transaction_state%rowtype;
 v_network record;
 v_count integer;
 v_code text;
BEGIN
 SELECT * INTO v_executor FROM public.users WHERE id=p_executor_id
 AND status='active'::public."UserStatus";
 IF NOT FOUND THEN RAISE EXCEPTION USING errcode='42501',message='ACTIVE_TREASURY_USER_REQUIRED'; END IF;
 IF NOT public.user_has_role(p_executor_id,ARRAY['treasury'::public."Role"]::public."Role"[]) THEN
  RAISE EXCEPTION USING errcode='42501',message='FORBIDDEN'; END IF;
 SELECT * INTO v_b FROM public.blockchain_transaction WHERE id::text=p_blockchain_transaction_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'BLOCKCHAIN_TRANSACTION_NOT_FOUND'; END IF;
 IF v_b.country_code IS DISTINCT FROM v_executor.country_code THEN
  RAISE EXCEPTION USING errcode='42501',message='BLOCKCHAIN_TRANSACTION_COUNTRY_MISMATCH'; END IF;
 IF v_b.transaction_type <> 'gold_token_buy'::public."TransactionType" THEN
  RETURN jsonb_build_object('transaction_type',v_b.transaction_type);
 END IF;
 IF v_b.document_number IS NOT NULL OR v_b.status='completed'::public."BlockchainTxStatus" THEN
  RAISE EXCEPTION 'TRANSACTION_ALREADY_COMPLETED'; END IF;
 IF v_b.status IS DISTINCT FROM 'pending'::public."BlockchainTxStatus" THEN
  RAISE EXCEPTION 'PENDING_BLOCKCHAIN_TRANSACTION_REQUIRED'; END IF;
 IF v_b.tx_hash IS NULL OR v_b.tx_hash !~ '^0x[0-9a-fA-F]{64}$' THEN
  RAISE EXCEPTION 'VALID_TRANSACTION_HASH_REQUIRED'; END IF;
 SELECT count(*) INTO v_count FROM public.transaction_state s
 WHERE s.reference=v_b.reference AND s.created_by=v_b.created_by;
 IF v_count<>1 THEN RAISE EXCEPTION 'UNIQUE_TRANSACTION_STATE_REQUIRED'; END IF;
 SELECT * INTO v_s FROM public.transaction_state s
 WHERE s.reference=v_b.reference AND s.created_by=v_b.created_by;
 IF v_s.transaction_type IS DISTINCT FROM v_b.transaction_type
 OR v_s.country_code IS DISTINCT FROM v_b.country_code
 OR v_s.user_id IS DISTINCT FROM v_b.created_by
 OR v_s.status IS DISTINCT FROM 'processing'::public."TransactionStatus" THEN
  RAISE EXCEPTION 'INVALID_TRANSACTION_STATE'; END IF;
 IF v_s.gold_buy_preparation IS NULL THEN
  RAISE EXCEPTION 'GOLD_BUY_PREPARATION_MISSING_RECONCILIATION_REQUIRED'
  USING HINT='Historical purchase: recover the original pricing/components separately. Do not price it again using current rates.';
 END IF;
 v_code:=v_s.gold_buy_preparation->'preparation'->>'blockchain_code';
 IF v_code IS NULL OR v_code IS DISTINCT FROM v_s.blockchain_code
 OR v_code IS DISTINCT FROM v_b.blockchain_code OR v_code IS DISTINCT FROM v_b.chain::text THEN
  RAISE EXCEPTION 'BLOCKCHAIN_CODE_MISMATCH'; END IF;
 SELECT b.contract_address,n.chain_id,n.rpc_url INTO v_network
 FROM public.supported_blockchain b
 JOIN LATERAL (
  SELECT x.chain_id,x.rpc_url FROM public.supported_blockchain_network x
  WHERE x.blockchain_id=b.id AND x.is_active
  ORDER BY x.is_default DESC,x.created_at DESC,x.id LIMIT 1
 ) n ON true WHERE b.code=v_code AND b.is_active;
 IF NOT FOUND THEN RAISE EXCEPTION 'BLOCKCHAIN_NOT_FOUND_OR_INACTIVE'; END IF;
 -- If a context captured chain identity, never silently switch its contract/network.
 IF v_s.gold_buy_preparation->'blockchain' IS NOT NULL THEN
  IF v_s.gold_buy_preparation->'blockchain'->>'code' IS DISTINCT FROM v_code
  OR lower(v_s.gold_buy_preparation->'blockchain'->>'contract_address') IS DISTINCT FROM lower(v_network.contract_address)
  OR v_s.gold_buy_preparation->'blockchain'->>'chain_id' IS DISTINCT FROM v_network.chain_id::text THEN
   RAISE EXCEPTION 'SAVED_BLOCKCHAIN_CONFIGURATION_CHANGED_REVIEW_REQUIRED';
  END IF;
 END IF;
 RETURN jsonb_build_object(
 'transaction_type',v_b.transaction_type,'blockchain_transaction_id',v_b.id::text,
 'transaction_state_id',v_s.id,'user_id',v_s.user_id,'country_code',v_s.country_code,
 'reference',v_s.reference,'transaction_data',v_s.transaction_data,
 'snapshot',v_s.gold_buy_preparation,'tx_hash',v_b.tx_hash,
 'sender',v_b.sender,'receiver',v_b.receiver,'quantity',v_b.quantity::text,
 'fee_amount',v_b.fee_amount::text,'gross_amount',v_b.gross_amount::text,
 'currency_code',v_b.currency_code,'net_amount',v_b.net_amount::text,
 'blockchain_code',v_code,'contract_address',v_network.contract_address,
 'chain_id',v_network.chain_id::text,'rpc_url',v_network.rpc_url);
END;
$function$;
ALTER FUNCTION public.build_gold_buy_recovery_context(text,text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.build_gold_buy_recovery_context(text,text) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.fetch_my_blockchain_recovery_context(p_blockchain_transaction_id text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO '' AS $function$
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION USING errcode='42501',message='UNAUTHORIZED'; END IF;
 RETURN public.build_gold_buy_recovery_context(auth.uid()::text,btrim(p_blockchain_transaction_id));
END;
$function$;
ALTER FUNCTION public.fetch_my_blockchain_recovery_context(text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fetch_my_blockchain_recovery_context(text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fetch_my_blockchain_recovery_context(text) TO authenticated;

-- Only the backend may call this after verifying the chain receipt and transfer.
CREATE OR REPLACE FUNCTION public.complete_verified_gold_buy_recovery(
 p_executor_id text,p_blockchain_transaction_id text,p_verified_context jsonb,
 p_ip_address text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $function$
DECLARE v_context jsonb; v_state_id text; v_result jsonb;
BEGIN
 IF coalesce(auth.role(),'')<>'service_role' THEN
  RAISE EXCEPTION USING errcode='42501',message='SERVICE_ROLE_REQUIRED'; END IF;
 -- Follow the normal completion lock order: transaction state, then blockchain row.
 SELECT s.id INTO v_state_id FROM public.transaction_state s
 JOIN public.blockchain_transaction b ON b.reference=s.reference AND b.created_by=s.created_by
 WHERE b.id::text=p_blockchain_transaction_id;
 IF v_state_id IS NULL THEN RAISE EXCEPTION 'TRANSACTION_STATE_NOT_FOUND'; END IF;
 PERFORM 1 FROM public.transaction_state WHERE id=v_state_id FOR UPDATE;
 PERFORM 1 FROM public.blockchain_transaction WHERE id::text=p_blockchain_transaction_id FOR UPDATE;
 v_context:=public.build_gold_buy_recovery_context(p_executor_id,p_blockchain_transaction_id);
 IF v_context->>'transaction_type'<>'gold_token_buy' THEN RAISE EXCEPTION 'GOLD_BUY_REQUIRED'; END IF;
 IF v_context IS DISTINCT FROM p_verified_context THEN
  RAISE EXCEPTION 'RECOVERY_CONTEXT_CHANGED_RETRY_REQUIRED'; END IF;
 SELECT to_jsonb(r) INTO v_result FROM public.complete_gold_buy(
  p_user_id=>v_context->>'user_id',p_transaction=>v_context->'transaction_data',
  p_country_code=>v_context->>'country_code',p_transaction_state_id=>v_state_id,
  p_blockchain_transaction_id=>p_blockchain_transaction_id,
  p_blockchain_code=>v_context->>'blockchain_code',p_ip_address=>p_ip_address
 ) r;
 RETURN v_result;
END;
$function$;
ALTER FUNCTION public.complete_verified_gold_buy_recovery(text,text,jsonb,text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.complete_verified_gold_buy_recovery(text,text,jsonb,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.complete_verified_gold_buy_recovery(text,text,jsonb,text) TO service_role;

-- Existing other transaction paths retained verbatim.
CREATE OR REPLACE FUNCTION public.process_my_incomplete_blockchain_transaction(p_blockchain_transaction_id text, p_ip_address text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
    v_executor public.users%rowtype;
    v_initiating_user public.users%rowtype;
    v_receiving_user public.users%rowtype;
    v_treasury public.users%rowtype;

    v_blockchain_transaction
        public.blockchain_transaction%rowtype;

    v_wallet_owners
        public.transaction_type_wallet_owner%rowtype;

    v_transaction_type
        public."TransactionType";

    v_sub_transaction_type
        public."TransactionType";

    v_mappings
        public.transaction_gl_mapping[];

    v_token_mappings
        public.transaction_gl_mapping[];

    v_components
        public.posting_component[];

    v_token_components
        public.posting_component[];

    v_token_principal_component
        public.posting_component;

    v_fiat_principal_component
        public.posting_component;

    v_receiver_notification
        public.notification_message;

    v_is_transfer boolean := false;

    v_principal numeric;
    v_quantity numeric;
    v_gross_token_quantity numeric;
    v_gross_amount numeric := 0;
    v_fee numeric := 0;

    v_currency_code text;
    v_reference text;

    v_fiat_sender_id text;
    v_fiat_receiver_id text;

    v_token_sender_id text;
    v_token_receiver_id text;

    v_notification_sender text;
    v_notification_receiver text;

    v_document_prefix text;
    v_document_number text;
    v_token_document_number text;
    v_token_reference text;

    v_financial_transaction_id bigint;
    v_token_financial_transaction_id bigint;

    v_receiver_notification_id text;

    v_device_tokens text[] :=
        array[]::text[];

    v_result jsonb;

    v_stage text := 'initialization';
    v_error_state text;
    v_error_message text;
    v_error_detail text;
    v_error_hint text;
    v_error_context text;
begin
    /*
     * Authenticate.
     */
    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHENTICATED';
    end if;

    if not public.has_role(
        array[
            'treasury'
        ]::text[]
    ) then
        raise exception using
            errcode = '42501',
            message = 'FORBIDDEN';
    end if;

    /*
     * Validate input.
     */
    if nullif(
        btrim(p_blockchain_transaction_id),
        ''
    ) is null
    then
        raise exception
            'BLOCKCHAIN_TRANSACTION_ID_REQUIRED';
    end if;

    /*
     * Fetch treasury operator.
     */
    v_stage :=
        'fetch treasury operator';

    v_executor :=
        public.fetch_user_by_id(
            auth.uid()::text
        );

    if v_executor.id is null then
        raise exception
            'TREASURY_USER_NOT_FOUND';
    end if;

    if v_executor.country_code is null then
        raise exception
            'USER_COUNTRY_NOT_CONFIGURED';
    end if;

    /*
     * Lock incomplete blockchain transaction.
     */
    v_stage :=
        'lock blockchain transaction';

    select blockchain_record.*
    into v_blockchain_transaction
    from public.blockchain_transaction
        blockchain_record
    where blockchain_record.id::text =
          btrim(
              p_blockchain_transaction_id
          )

      and blockchain_record.document_number is null

      and (
          blockchain_record.status is null
          or blockchain_record.status <>
             'completed'::public."BlockchainTxStatus"
      )
    for update;

    if not found then
        raise exception
            'TRANSACTION_NOT_FOUND_OR_ALREADY_COMPLETED';
    end if;

    if v_blockchain_transaction.country_code is distinct from
       v_executor.country_code
    then
        raise exception
            'BLOCKCHAIN_TRANSACTION_COUNTRY_MISMATCH';
    end if;

    if v_blockchain_transaction.created_by is null then
        raise exception
            'TRANSACTION_CREATED_BY_NOT_FOUND';
    end if;

    v_transaction_type :=
        v_blockchain_transaction.transaction_type;

    -- Gold Buy must use the saved preparation and backend receipt verification.
    -- Block the old live-pricing path even when this RPC is called directly.
    if v_transaction_type = 'gold_token_buy'::public."TransactionType" then
        raise exception 'USE_VERIFIED_GOLD_BUY_RECOVERY';
    end if;

    /*
     * Mint and burn use their existing accounting completion
     * function.
     */
    if v_transaction_type in (
        'gold_token_mint'::public."TransactionType",
        'gold_token_burn'::public."TransactionType"
    )
    then
        v_stage :=
            'complete token adjustment';

        if nullif(
            btrim(
                v_blockchain_transaction.reference
            ),
            ''
        ) is null
        then
            raise exception
                'ADJUSTMENT_REQUEST_REFERENCE_NOT_FOUND';
        end if;

        return public.complete_my_token_adjustment_execution(
            v_blockchain_transaction.reference,
            v_blockchain_transaction.id::text,
            p_ip_address
        );
    end if;

    /*
     * Validate supported Gold transaction.
     */
    if v_transaction_type not in (
        'gold_token_buy'::public."TransactionType",
        'gold_token_sell'::public."TransactionType",
        'gold_token_transfer'::public."TransactionType"
    )
    then
        raise exception
            'UNSUPPORTED_BLOCKCHAIN_TRANSACTION_TYPE';
    end if;

    v_is_transfer :=
        v_transaction_type =
        'gold_token_transfer'::public."TransactionType";

    /*
     * Resolve currency and reference.
     */
    v_currency_code :=
        lower(
            nullif(
                btrim(
                    v_blockchain_transaction.currency_code
                ),
                ''
            )
        );

    if v_currency_code is null then
        raise exception
            'BLOCKCHAIN_TRANSACTION_CURRENCY_NOT_FOUND';
    end if;

    v_reference :=
        coalesce(
            nullif(
                btrim(
                    v_blockchain_transaction.reference
                ),
                ''
            ),
            v_blockchain_transaction.tx_hash
        );

    if nullif(
        btrim(v_reference),
        ''
    ) is null
    then
        raise exception
            'BLOCKCHAIN_TRANSACTION_REFERENCE_NOT_FOUND';
    end if;

    /*
     * Resolve original principal.
     */
    if v_is_transfer then
        v_principal :=
            v_blockchain_transaction.quantity;
    else
        v_principal :=
            v_blockchain_transaction.gross_amount;
    end if;

    if v_principal is null
       or v_principal <= 0
    then
        raise exception
            'INVALID_AMOUNT';
    end if;

    /*
     * Resolve token sub-transaction.
     */
    v_sub_transaction_type :=
        case v_transaction_type
            when 'gold_token_buy'::public."TransactionType"
            then
                'gold_token_buy_sub_tx'::public."TransactionType"

            when 'gold_token_sell'::public."TransactionType"
            then
                'gold_token_sell_sub_tx'::public."TransactionType"

            when 'gold_token_transfer'::public."TransactionType"
            then
                'gold_token_transfer'::public."TransactionType"
        end;

    /*
     * Fetch initiating user.
     */
    v_stage :=
        'fetch initiating user';

    v_initiating_user :=
        public.fetch_user_by_id(
            v_blockchain_transaction.created_by
        );

    if v_initiating_user.id is null then
        raise exception
            'INITIATING_USER_NOT_FOUND';
    end if;

    if v_initiating_user.status <>
       'active'::public."UserStatus"
    then
        raise exception
            'INITIATING_USER_NOT_ACTIVE';
    end if;

    /*
     * Fetch country treasury.
     */
    v_stage :=
        'fetch country treasury';

    v_treasury :=
        public.fetch_country_treasury(
            v_blockchain_transaction.country_code
        );

    if v_treasury.id is null then
        raise exception
            'TREASURY_USER_NOT_FOUND';
    end if;

    /*
     * Resolve transfer receiver using blockchain address.
     */
    if v_is_transfer then
        v_stage :=
            'fetch transfer receiver';

        select user_record.*
        into v_receiving_user
        from public.users
            user_record
        where lower(
            user_record.wallet_address
        ) =
            lower(
                v_blockchain_transaction.receiver
            )

          and user_record.country_code =
              v_blockchain_transaction.country_code
        limit 1;

        if not found then
            raise exception
                'RECEIVER_NOT_FOUND';
        end if;

        if v_receiving_user.status <>
           'active'::public."UserStatus"
        then
            raise exception
                'RECEIVER_NOT_ACTIVE';
        end if;

        if v_receiving_user.id =
           v_initiating_user.id
        then
            raise exception
                'OPERATION_NOT_ALLOWED';
        end if;
    end if;

    /*
     * Resolve transaction parties.
     */
    if v_transaction_type =
       'gold_token_buy'::public."TransactionType"
    then
        v_fiat_sender_id :=
            v_initiating_user.id;

        v_fiat_receiver_id :=
            v_treasury.id;

        v_token_sender_id :=
            v_treasury.id;

        v_token_receiver_id :=
            v_initiating_user.id;

        v_notification_sender :=
            coalesce(
                v_treasury.email,
                v_treasury.id
            );

        v_notification_receiver :=
            coalesce(
                v_initiating_user.email,
                v_initiating_user.phone,
                v_initiating_user.id
            );

    elsif v_transaction_type =
          'gold_token_sell'::public."TransactionType"
    then
        v_fiat_sender_id :=
            v_treasury.id;

        v_fiat_receiver_id :=
            v_initiating_user.id;

        v_token_sender_id :=
            v_initiating_user.id;

        v_token_receiver_id :=
            v_treasury.id;

        v_notification_sender :=
            coalesce(
                v_initiating_user.email,
                v_initiating_user.phone,
                v_initiating_user.id
            );

        v_notification_receiver :=
            coalesce(
                v_treasury.email,
                v_treasury.id
            );

    else
        v_token_sender_id :=
            v_initiating_user.id;

        v_token_receiver_id :=
            v_receiving_user.id;

        v_notification_sender :=
            coalesce(
                v_initiating_user.email,
                v_initiating_user.phone,
                v_initiating_user.id
            );

        v_notification_receiver :=
            coalesce(
                v_receiving_user.email,
                v_receiving_user.phone,
                v_receiving_user.id
            );
    end if;

    /*
     * Fetch wallet-owner configuration.
     */
    v_stage :=
        'fetch wallet-owner configuration';

    v_wallet_owners :=
        public.fetch_transaction_type_wallet_owner(
            v_transaction_type
        );

    /*
     * Fetch document prefix.
     */
    v_stage :=
        'fetch document prefix';

    v_document_prefix :=
        public.fetch_transaction_doc_num_prefix(
            v_transaction_type
        );

    if nullif(
        btrim(v_document_prefix),
        ''
    ) is null
    then
        raise exception
            'DOCUMENT_PREFIX_NOT_FOUND';
    end if;

    /*
     * Build fiat components for buy/sell.
     */
    if not v_is_transfer then
        v_stage :=
            'fetch fiat GL mappings';

        select array_agg(mapping_record)
        into v_mappings
        from public.fetch_gl_mappings(
            v_transaction_type
        ) as mapping_record;

        if v_mappings is null
           or cardinality(v_mappings) = 0
        then
            raise exception
                'GL_MAPPINGS_NOT_FOUND';
        end if;

        v_stage :=
            'build fiat posting components';

        v_components :=
            public.build_posting_components(
                v_transaction_type,
                v_principal,
                v_mappings,
                v_blockchain_transaction.country_code,
                v_currency_code,
                false
            );

        if v_components is null
           or cardinality(v_components) = 0
        then
            raise exception
                'POSTING_COMPONENTS_NOT_FOUND';
        end if;
    else
        v_mappings :=
            array[]::public.transaction_gl_mapping[];

        v_components :=
            array[]::public.posting_component[];
    end if;

    /*
     * Build token components.
     */
    v_stage :=
        'fetch token GL mappings';

    select array_agg(mapping_record)
    into v_token_mappings
    from public.fetch_gl_mappings(
        v_sub_transaction_type
    ) as mapping_record;

    if v_token_mappings is null
       or cardinality(v_token_mappings) = 0
    then
        raise exception
            'TOKEN_GL_MAPPINGS_NOT_FOUND';
    end if;

    v_stage :=
        'build token posting components';

    v_token_components :=
        public.build_posting_components(
            v_sub_transaction_type,
            v_principal,
            v_token_mappings,
            v_blockchain_transaction.country_code,
            v_currency_code,
            true
        );

    if v_token_components is null
       or cardinality(v_token_components) = 0
    then
        raise exception
            'TOKEN_POSTING_COMPONENTS_NOT_FOUND';
    end if;

    /*
     * Extract token principal.
     */
    v_stage :=
        'extract token principal component';

    select component_record.*
    into v_token_principal_component
    from unnest(
        v_token_components
    ) as component_record
    where component_record.component_type =
          'principal'::public."ComponentType"
    limit 1;

    if not found then
        raise exception
            'TOKEN_PRINCIPAL_COMPONENT_NOT_FOUND';
    end if;

    v_quantity :=
        public.round_down(
            case
                when v_token_principal_component.debit_amount > 0
                then
                    v_token_principal_component.debit_amount
                else
                    v_token_principal_component.credit_amount
            end
        );

    if v_quantity is null
       or v_quantity <= 0
    then
        raise exception
            'INVALID_QUANTITY';
    end if;

    v_gross_token_quantity :=
        case
            when v_token_principal_component.credit_amount > 0
            then
                v_token_principal_component.credit_amount
            else
                v_quantity
        end;

    /*
     * Extract transfer fee.
     */
    v_stage :=
        'extract token transaction fee';

    select coalesce(
        component_record.debit_amount,
        0
    )
    into v_fee
    from unnest(
        v_token_components
    ) as component_record
    where component_record.component_type =
          'transaction_fee'::public."ComponentType"
    limit 1;

    v_fee :=
        coalesce(
            v_fee,
            0
        );

    /*
     * Extract fiat principal.
     */
    if not v_is_transfer then
        v_stage :=
            'extract fiat principal component';

        select component_record.*
        into v_fiat_principal_component
        from unnest(
            v_components
        ) as component_record
        where component_record.component_type =
              'principal'::public."ComponentType"
        limit 1;

        if not found then
            raise exception
                'FIAT_PRINCIPAL_COMPONENT_NOT_FOUND';
        end if;

        v_gross_amount :=
            coalesce(
                v_fiat_principal_component.debit_amount,
                0
            );

        if v_gross_amount <= 0 then
            raise exception
                'INVALID_GROSS_AMOUNT';
        end if;
    else
        v_gross_amount :=
            0;
    end if;

    /*
     * Build receiver notification.
     */
    v_stage :=
        'create recovery notification';

    v_receiver_notification :=
        public.create_notification_message(
            p_country_code =>
                v_blockchain_transaction.country_code,

            p_transaction_type =>
                v_transaction_type,

            p_audience =>
                'receiver'::public."NotificationAudience",

            p_amount =>
                v_gross_amount,

            p_currency =>
                case
                    when v_is_transfer
                        then 'GOLD'
                    else upper(v_currency_code)
                end,

            p_reference =>
                v_reference,

            p_quantity =>
                v_quantity,

            p_sender =>
                v_notification_sender,

            p_receiver =>
                v_notification_receiver
        );

    v_device_tokens :=
        public.fetch_device_tokens(
            v_blockchain_transaction.country_code,
            v_token_receiver_id
        );

    /*
     * Generate document numbers.
     */
    v_stage :=
        'generate recovery document number';

    v_document_number :=
        public.generate_document_number(
            v_document_prefix,
            v_blockchain_transaction.fiscal_year,
            v_blockchain_transaction.period,
            v_blockchain_transaction.country_code
        );

    v_token_document_number :=
        case
            when v_is_transfer
                then v_document_number
            else v_document_number || '-01'
        end;

    v_token_reference :=
        case
            when v_is_transfer
                then v_reference
            else v_reference || '-01'
        end;

    /*
     * ========================================================
     * FIAT LEG
     * ========================================================
     */
    if not v_is_transfer then
        v_stage :=
            'create fiat financial transaction';

        insert into public.financial_transaction (
            document_number,
            fiscal_year,
            period,
            reference,
            transaction_type,
            description,
            created_by,
            gross_amount,
            currency_code,
            country_code
        )
        values (
            v_document_number,
            v_blockchain_transaction.fiscal_year,
            v_blockchain_transaction.period,
            v_reference,
            v_transaction_type,
            coalesce(
                v_blockchain_transaction.description,
                v_transaction_type::text
            ),
            v_blockchain_transaction.created_by,
            v_gross_amount,
            v_currency_code,
            v_blockchain_transaction.country_code
        )
        returning id
        into v_financial_transaction_id;

        v_stage :=
            'post fiat financial entries';

        perform *
        from public.post_financial_entries(
            p_document_number =>
                v_document_number,

            p_country_code =>
                v_blockchain_transaction.country_code,

            p_transaction_id =>
                v_financial_transaction_id,

            p_transaction_type =>
                v_transaction_type,

            p_created_by =>
                v_blockchain_transaction.created_by,

            p_components =>
                v_components,

            p_mappings =>
                v_mappings,

            p_currency_code =>
                v_currency_code,

            p_fiscal_year =>
                v_blockchain_transaction.fiscal_year,

            p_period =>
                v_blockchain_transaction.period,

            p_reference =>
                v_reference,

            p_deposit_type =>
                null
        );

        v_stage :=
            'post fiat wallet entries';

        perform *
        from public.post_wallet_entries(
            p_fiscal_year =>
                v_blockchain_transaction.fiscal_year,

            p_period =>
                v_blockchain_transaction.period,

            p_document_number =>
                v_document_number,

            p_reference =>
                v_reference,

            p_receiver_id =>
                v_fiat_receiver_id,

            p_sender_id =>
                v_fiat_sender_id,

            p_transaction_type =>
                v_transaction_type,

            p_credit_amount =>
                v_gross_amount,

            p_debit_amount =>
                v_gross_amount,

            p_sender_wallet_owner =>
                v_wallet_owners.sender_wallet_owner,

            p_receiver_wallet_owner =>
                v_wallet_owners.receiver_wallet_owner,

            p_currency_code =>
                v_currency_code,

            p_country_code =>
                v_blockchain_transaction.country_code,

            p_audit_action_type =>
                v_wallet_owners.audit_action_type,

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
    end if;

    /*
     * ========================================================
     * TOKEN LEG
     * ========================================================
     */
    v_stage :=
        'create token financial transaction';

    insert into public.financial_transaction (
        document_number,
        fiscal_year,
        period,
        reference,
        transaction_type,
        description,
        created_by,
        gross_amount,
        currency_code,
        country_code
    )
    values (
        v_token_document_number,
        v_blockchain_transaction.fiscal_year,
        v_blockchain_transaction.period,
        v_token_reference,
        v_sub_transaction_type,
        coalesce(
            v_blockchain_transaction.description,
            v_transaction_type::text
        ),
        v_blockchain_transaction.created_by,
        v_gross_token_quantity,
        'gold',
        v_blockchain_transaction.country_code
    )
    returning id
    into v_token_financial_transaction_id;

    v_stage :=
        'post token financial entries';

    perform *
    from public.post_financial_entries(
        p_document_number =>
            v_token_document_number,

        p_country_code =>
            v_blockchain_transaction.country_code,

        p_transaction_id =>
            v_token_financial_transaction_id,

        p_transaction_type =>
            v_sub_transaction_type,

        p_created_by =>
            v_blockchain_transaction.created_by,

        p_components =>
            v_token_components,

        p_mappings =>
            v_token_mappings,

        p_currency_code =>
            'gold',

        p_fiscal_year =>
            v_blockchain_transaction.fiscal_year,

        p_period =>
            v_blockchain_transaction.period,

        p_reference =>
            v_token_reference,

        p_deposit_type =>
            null
    );

    v_stage :=
        'post token wallet entries';

    select wallet_result.receiver_notification_id
    into v_receiver_notification_id
    from public.post_wallet_entries(
        p_fiscal_year =>
            v_blockchain_transaction.fiscal_year,

        p_period =>
            v_blockchain_transaction.period,

        p_document_number =>
            v_token_document_number,

        p_reference =>
            v_token_reference,

        p_receiver_id =>
            v_token_receiver_id,

        p_sender_id =>
            v_token_sender_id,

        p_transaction_type =>
            v_transaction_type,

        p_credit_amount =>
            case
                when v_is_transfer
                    then v_quantity
                else v_gross_token_quantity
            end,

        p_debit_amount =>
            v_gross_token_quantity,

        p_sender_wallet_owner =>
            v_wallet_owners.receiver_wallet_owner,

        p_receiver_wallet_owner =>
            v_wallet_owners.sender_wallet_owner,

        p_currency_code =>
            'gold',

        p_country_code =>
            v_blockchain_transaction.country_code,

        p_audit_action_type =>
            v_wallet_owners.audit_action_type,

        p_treasury_id =>
            v_treasury.id,

        p_fee_amount =>
            case
                when v_is_transfer
                    then v_fee
                else 0
            end,

        p_ip_address =>
            p_ip_address,

        p_receiver_notification =>
            v_receiver_notification,

        p_sender_notification =>
            null
    ) as wallet_result;

    /*
     * Complete blockchain transaction.
     */
    v_stage :=
        'complete blockchain transaction';

    update public.blockchain_transaction
    set
        document_number =
            v_token_document_number,

        status =
            'completed'::public."BlockchainTxStatus"
    where id =
          v_blockchain_transaction.id

      and document_number is null;

    if not found then
        raise exception
            'BLOCKCHAIN_TRANSACTION_COMPLETION_FAILED';
    end if;

    v_result :=
        jsonb_build_object(
            'success',
            true,

            'document_number',
            v_document_number,

            'token_document_number',
            v_token_document_number,

            'reference',
            v_reference,

            'transaction_type',
            v_transaction_type,

            'quantity',
            v_quantity::text,

            'total_spent',
            v_gross_amount::text,

            'fee',
            v_fee::text,

            'explorer_url',
            v_blockchain_transaction.explorer_url,

            'receiver_notification_id',
            v_receiver_notification_id,

            'device_tokens',
            to_jsonb(v_device_tokens),

            'notification',
            to_jsonb(
                v_receiver_notification
            )
        );

    return v_result;

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
                coalesce(
                    nullif(
                        v_error_state,
                        ''
                    ),
                    'P0001'
                ),

            message =
                format(
                    'INCOMPLETE_BLOCKCHAIN_POSTING_FAILED at [%s]: %s',
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
                    'Check the incomplete blockchain posting stage reported in the error'
                );
end;
$function$;

COMMIT;

CREATE OR REPLACE FUNCTION public.prepare_gold_buy(p_user_id text, p_transaction jsonb, p_country_code text, p_transaction_state_id text, p_blockchain_code text)
 RETURNS TABLE(user_id text, country_code text, user_wallet_address text, treasury_id text, treasury_wallet_address text, treasury_wallet_index bigint, fiscal_year integer, period integer, document_prefix text, input_amount text, input_currency text, gold_price text, token_quantity text, gross_token_quantity text, token_fee text, gross_amount text, spread text, blockchain_code text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
    v_blockchain_code text;
    v_execution_pricing jsonb;
    v_token_pricing public.pricing_result;
    v_saved jsonb;
    v_chain_config jsonb;
    v_preparation_json jsonb;
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
    v_blockchain_code := lower(nullif(btrim(p_blockchain_code), ''));
    if v_blockchain_code is null then
        raise exception 'BLOCKCHAIN_CODE_REQUIRED';
    end if;
    perform 1 from public.supported_blockchain b
    where b.code = v_blockchain_code and b.is_active = true
      and exists (
        select 1 from public.supported_blockchain_network n
        where n.blockchain_id = b.id and n.is_active = true
      );
    if not found then
        raise exception 'BLOCKCHAIN_NOT_FOUND_OR_INACTIVE';
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
    if v_transaction_state.blockchain_code is distinct from v_blockchain_code then
        raise exception 'TRANSACTION_BLOCKCHAIN_MISMATCH';
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
    if v_currency not in ('usd', 'gold') then
        raise exception 'UNSUPPORTED_GOLD_BUY_CURRENCY';
    end if;
    v_saved := v_transaction_state.gold_buy_preparation;
    if v_saved is not null then
        if v_saved ->> 'schema_version' is distinct from '1'
           or v_saved ->> 'transaction_state_id' is distinct from p_transaction_state_id
           or v_saved -> 'transaction_data' is distinct from p_transaction
           or jsonb_typeof(v_saved -> 'preparation') is distinct from 'object'
           or v_saved -> 'preparation' ->> 'blockchain_code' is distinct from v_blockchain_code
           or v_saved -> 'preparation' ->> 'user_id' is distinct from p_user_id
           or v_saved -> 'preparation' ->> 'country_code' is distinct from p_country_code
           or jsonb_typeof(v_saved -> 'fiat_components') is distinct from 'array'
           or jsonb_typeof(v_saved -> 'token_components') is distinct from 'array'
           or jsonb_typeof(v_saved -> 'fiat_mappings') is distinct from 'array'
           or jsonb_typeof(v_saved -> 'token_mappings') is distinct from 'array' then
            raise exception 'INVALID_SAVED_GOLD_BUY_PREPARATION';
        end if;
        return query
        select saved.* from jsonb_to_record(v_saved -> 'preparation') as saved(user_id text, country_code text, user_wallet_address text, treasury_id text, treasury_wallet_address text, treasury_wallet_index bigint, fiscal_year integer, period integer, document_prefix text, input_amount text, input_currency text, gold_price text, token_quantity text, gross_token_quantity text, token_fee text, gross_amount text, spread text, blockchain_code text);
        return;
    end if;

    -- A historical submitted purchase without a saved quote must be reconciled.
    -- Never invent a new quote after tokens may already have moved.
    if exists (select 1 from public.blockchain_transaction b
               where b.reference = p_transaction ->> 'r' and b.created_by = p_user_id)
       or exists (select 1 from public.financial_transaction f
                  where f.reference = p_transaction ->> 'r' and f.created_by = p_user_id) then
        raise exception 'GOLD_BUY_PREPARATION_MISSING_RECONCILIATION_REQUIRED';
    end if;

    v_stage := 'calculate exact gold-buy pricing';
    /*
     * Calculate the exact Gold Buy price used by this
     * transaction.
     *
     * Do not fetch the Gold market price independently.
     * calculate_gold_buy_execution_pricing is the pricing source of
     * truth and returns the Buy price in gold_price.
     */
    v_execution_pricing := public.calculate_gold_buy_execution_pricing(
        v_amount, p_country_code, v_currency
    );
    v_pricing := jsonb_populate_record(
        null::public.pricing_result, v_execution_pricing -> 'fiat_pricing'
    );
    v_token_pricing := jsonb_populate_record(
        null::public.pricing_result, v_execution_pricing -> 'token_pricing'
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
    v_fiat_components := public.build_gold_buy_components_from_pricing(
        'gold_token_buy'::public."TransactionType",
        case when v_currency = 'gold' then v_pricing.fiat_received else v_amount end,
        v_fiat_mappings, v_pricing, false
    );
    v_stage := 'Build reversed gold-token components';
    /*
     * Build reversed gold-token components.
     */
    v_token_components := public.build_gold_buy_components_from_pricing(
        v_sub_transaction_type, v_token_pricing.quantity,
        v_token_mappings, v_token_pricing, true
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
    v_stage := 'validate sender wallets';
    perform 1 from public.wallet w
    where w.user_id = p_user_id and w.country_code = p_country_code
      and w.currency_code = 'usd'
      and w.owner_type = 'customer'::public."WalletOwnerType"
      and w.blockchain_code is null and w.is_active = true
      and w.balance >= v_gross_amount;
    if not found then
        raise exception 'BUYER_USD_WALLET_UNAVAILABLE_OR_INSUFFICIENT';
    end if;
    perform 1 from public.wallet w
    where w.user_id = v_treasury.id and w.country_code = p_country_code
      and w.currency_code = 'gold'
      and w.owner_type = 'treasury'::public."WalletOwnerType"
      and w.blockchain_code = v_blockchain_code and w.is_active = true
      and w.balance >= v_token_quantity;
    if not found then
        raise exception 'TREASURY_GOLD_WALLET_UNAVAILABLE_OR_INSUFFICIENT';
    end if;
    v_preparation_json := jsonb_build_object(
        'user_id', v_user.id,
        'country_code', p_country_code,
        'user_wallet_address', v_user.wallet_address,
        'treasury_id', v_treasury.id,
        'treasury_wallet_address', v_treasury.wallet_address,
        'treasury_wallet_index', v_treasury.wallet_index,
        'fiscal_year', v_fiscal_year,
        'period', v_period,
        'document_prefix', v_document_prefix,
        'input_amount', v_amount::text,
        'input_currency', v_currency,
        'gold_price', v_gold_price::text,
        'token_quantity', v_token_quantity::text,
        'gross_token_quantity', v_gross_token_quantity::text,
        'token_fee', v_token_fee::text,
        'gross_amount', v_gross_amount::text,
        'spread', v_spread::text,
        'blockchain_code', v_blockchain_code
    );
    select jsonb_build_object('code',b.code,'contract_address',b.contract_address,
           'chain_id',n.chain_id::text,'rpc_url',n.rpc_url)
    into v_chain_config
    from public.supported_blockchain b
    join lateral (
        select x.chain_id,x.rpc_url from public.supported_blockchain_network x
        where x.blockchain_id=b.id and x.is_active
        order by x.is_default desc,x.created_at desc,x.id limit 1
    ) n on true where b.code=v_blockchain_code and b.is_active;
    if v_chain_config is null then raise exception 'BLOCKCHAIN_NOT_FOUND_OR_INACTIVE'; end if;
    v_saved := jsonb_build_object(
        'origin', 'execution_preparation',
        'blockchain', v_chain_config,
        'schema_version', 1,
        'transaction_state_id', p_transaction_state_id,
        'transaction_data', p_transaction,
        'prepared_at', clock_timestamp(),
        'preparation', v_preparation_json,
        'pricing', v_execution_pricing,
        'fiat_components', to_jsonb(v_fiat_components),
        'token_components', to_jsonb(v_token_components),
        'fiat_mappings', to_jsonb(v_fiat_mappings),
        'token_mappings', to_jsonb(v_token_mappings)
    );
    perform public.save_gold_buy_execution_context(p_transaction_state_id, v_saved);

    v_stage := 'return preparation';
    return query
    select
        v_user.id,
        p_country_code,
        v_user.wallet_address,
        v_treasury.id,
        v_treasury.wallet_address,
        v_treasury.wallet_index::bigint,
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
        v_blockchain_code;
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

ALTER FUNCTION public.prepare_gold_buy(text,jsonb,text,text,text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.prepare_gold_buy(text,jsonb,text,text,text) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.prepare_gold_buy(text,jsonb,text,text,text) TO service_role;

COMMIT;
