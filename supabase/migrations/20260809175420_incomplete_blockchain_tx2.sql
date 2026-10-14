create or replace function public.process_my_incomplete_blockchain_transaction(
    p_blockchain_transaction_id text,
    p_ip_address text default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
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

    /*
     * Preserve the existing treasury-role requirement.
     */
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
     * Fetch the authenticated treasury operator.
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
     * Lock the incomplete blockchain transaction.
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

    /*
     * Mint and burn already have a dedicated recovery-safe
     * accounting completion function.
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
     * Resolve transaction currency and reference.
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
     * Resolve the principal used by the original process.
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
     * Resolve token sub-transaction type.
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
     *
     * Treasury receives or provides the Gold for buy/sell and
     * receives the transfer fee when applicable.
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
     * A Gold transfer receiver is identified using the wallet
     * address saved in blockchain_transaction.receiver.
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
     * Resolve parties.
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
     * Fetch configured wallet-owner direction.
     */
    v_stage :=
        'fetch wallet-owner configuration';

    v_wallet_owners :=
        public.fetch_transaction_type_wallet_owner(
            v_transaction_type
        );

    /*
     * Fetch configured document prefix.
     */
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
     * Build fiat components for Gold buy/sell.
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
     * Build Gold/token components.
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
    select component_record
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
     * Extract transfer fee from token components.
     */
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
     * Extract fiat gross amount.
     */
    if not v_is_transfer then
        select component_record
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
     * Build notification outside the wallet posting section.
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
     * Generate base document number.
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
     *
     * blockchain_transaction does not have updated_at.
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

            /*
             * Edge Function consumes these values for push
             * delivery and must remove them before responding.
             */
            'device_tokens',
            to_jsonb(v_device_tokens),

            'notification',
            to_jsonb(v_receiver_notification)
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


revoke all on function
    public.process_my_incomplete_blockchain_transaction(
        text,
        text
    )
from public;

revoke all on function
    public.process_my_incomplete_blockchain_transaction(
        text,
        text
    )
from anon;

grant execute on function
    public.process_my_incomplete_blockchain_transaction(
        text,
        text
    )
to authenticated;

notify pgrst, 'reload schema';