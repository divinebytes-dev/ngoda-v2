create or replace function public.execute_my_agent_funding(
    p_transaction_type public."TransactionType",
    p_agent_identifier text default null,
    p_currency_code text default null,
    p_amount numeric default null,
    p_reference text default null,
    p_document_number text default null,
    p_ip_address text default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
    v_executor public.users%rowtype;
    v_treasury public.users%rowtype;
    v_agent public.users%rowtype;

    v_original_funding
        public.financial_transaction%rowtype;

    v_original_deposit
        public.financial_transaction%rowtype;

    v_is_reversal boolean;

    v_identifier text;
    v_currency_code text;
    v_amount numeric;
    v_reference text;

    v_fiscal_year integer;
    v_period integer;

    v_funding_transaction_type
        public."TransactionType";

    v_deposit_transaction_type
        public."TransactionType";

    v_funding_mappings
        public.transaction_gl_mapping[];

    v_deposit_mappings
        public.transaction_gl_mapping[];

    v_funding_components
        public.posting_component[];

    v_deposit_components
        public.posting_component[];

    v_funding_prefix text;
    v_deposit_prefix text;

    v_funding_document_number text;
    v_deposit_document_number text;

    v_funding_transaction_id
        public.financial_transaction.id%type;

    v_deposit_transaction_id
        public.financial_transaction.id%type;

    v_sender_id text;
    v_receiver_id text;

    v_sender_wallet_owner
        public."WalletOwnerType";

    v_receiver_wallet_owner
        public."WalletOwnerType";

    v_audit_action
        public."AuditActionType";

    v_funding_description text;
    v_deposit_description text;

    v_receiver_notification
        public.notification_message;

    v_stage text := 'initialization';
    v_error_state text;
    v_error_message text;
    v_error_detail text;
    v_error_hint text;
    v_error_context text;
begin
    /*
     * Authenticate and authorize treasury.
     */
    v_stage := 'authorize treasury user';

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
     * Validate transaction type.
     */
    v_stage := 'validate transaction type';

    if p_transaction_type not in (
        'agent_funding'::public."TransactionType",
        'agent_funding_reversal'::public."TransactionType"
    ) then
        raise exception
            'INVALID_AGENT_FUNDING_TRANSACTION_TYPE';
    end if;

    v_is_reversal :=
        p_transaction_type =
        'agent_funding_reversal'::public."TransactionType";

    v_funding_transaction_type :=
        p_transaction_type;

    v_deposit_transaction_type :=
        case
            when v_is_reversal then
                'agent_deposit_reversal'::public."TransactionType"
            else
                'agent_deposit'::public."TransactionType"
        end;

    /*
     * Fetch authenticated user.
     */
    v_stage := 'fetch authenticated user';

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
     * Fetch country treasury.
     */
    v_stage := 'fetch country treasury';

    v_treasury :=
        public.fetch_country_treasury(
            v_executor.country_code
        );

    if v_treasury.id is null then
        raise exception
            'TREASURY_NOT_FOUND';
    end if;

    /*
     * Normal agent funding.
     */
    if not v_is_reversal then
        v_stage := 'validate funding input';

        v_identifier :=
            nullif(
                btrim(p_agent_identifier),
                ''
            );

        if v_identifier is null then
            raise exception
                'AGENT_IDENTIFIER_REQUIRED';
        end if;

        v_currency_code :=
            lower(
                nullif(
                    btrim(p_currency_code),
                    ''
                )
            );

        if v_currency_code is null then
            raise exception
                'CURRENCY_REQUIRED';
        end if;

        v_amount :=
            public.round_down(p_amount);

        if v_amount is null
           or v_amount <= 0
        then
            raise exception
                'INVALID_AMOUNT';
        end if;

        v_reference :=
            nullif(
                btrim(p_reference),
                ''
            );

        if v_reference is null then
            raise exception
                'REFERENCE_REQUIRED';
        end if;

        /*
         * An agent-operation recipient may have an agent,
         * vendor, or merchant account role.
         */
        v_stage := 'fetch funding recipient';

        select user_record.*
        into v_agent
        from public.users user_record
        join public.user_role role_record
          on role_record.id =
             user_record.role_id
        where user_record.country_code =
              v_executor.country_code

          and user_record.status =
              'active'::public."UserStatus"

          and lower(
              role_record.name::text
          ) in (
              'agent',
              'vendor',
              'merchant'
          )

          and (
              lower(
                  user_record.email
              ) =
                  lower(v_identifier)

              or user_record.phone =
                  v_identifier
          )
        limit 1;

        if not found then
            raise exception
                'AGENT_VENDOR_OR_MERCHANT_NOT_FOUND';
        end if;

        /*
         * Prevent duplicate request reference.
         */
        v_stage := 'check funding reference';

        perform 1
        from public.financial_transaction
            transaction_record
        where transaction_record.reference =
              v_reference
        limit 1;

        if found then
            raise exception
                'TRANSACTION_REPLAY';
        end if;

        v_sender_id :=
            v_treasury.id;

        v_receiver_id :=
            v_agent.id;

        /*
         * Vendor and merchant users are funded through their
         * agent-operation wallet.
         */
        v_sender_wallet_owner :=
            'treasury'::public."WalletOwnerType";

        v_receiver_wallet_owner :=
            'agent'::public."WalletOwnerType";

        v_audit_action :=
            'agent_funded'::public."AuditActionType";

        v_funding_description :=
            format(
                'Agent funding %s',
                coalesce(
                    v_agent.email,
                    v_agent.phone,
                    v_agent.id
                )
            );

        v_deposit_description :=
            format(
                'Agent deposit %s',
                coalesce(
                    v_agent.email,
                    v_agent.phone,
                    v_agent.id
                )
            );
    end if;

    /*
     * Agent funding reversal.
     */
    if v_is_reversal then
        v_stage := 'validate reversal document';

        if nullif(
            btrim(p_document_number),
            ''
        ) is null
        then
            raise exception
                'DOCUMENT_NUMBER_REQUIRED_FOR_REVERSAL';
        end if;

        /*
         * Lock original funding document.
         */
        v_stage := 'fetch original funding document';

        select transaction_record.*
        into v_original_funding
        from public.financial_transaction
            transaction_record
        where transaction_record.document_number =
              btrim(p_document_number)

          and transaction_record.country_code =
              v_executor.country_code
        for update;

        if not found then
            raise exception
                'DOCUMENT_NOT_FOUND';
        end if;

        if v_original_funding.transaction_type <>
           'agent_funding'::public."TransactionType"
        then
            raise exception
                'DOCUMENT_IS_NOT_AGENT_FUNDING';
        end if;

        /*
         * Prevent duplicate reversal.
         */
        v_stage := 'check duplicate reversal';

        perform 1
        from public.financial_transaction
            reversal_record
        where reversal_record.country_code =
              v_executor.country_code

          and reversal_record.transaction_type =
              'agent_funding_reversal'::public."TransactionType"

          and reversal_record.reversal_of =
              v_original_funding.document_number
        limit 1;

        if found then
            raise exception
                'DOCUMENT_ALREADY_REVERSED';
        end if;

        /*
         * Fetch paired original agent-deposit document.
         */
        v_stage := 'fetch original deposit document';

        select transaction_record.*
        into v_original_deposit
        from public.financial_transaction
            transaction_record
        where transaction_record.country_code =
              v_executor.country_code

          and transaction_record.transaction_type =
              'agent_deposit'::public."TransactionType"

          and transaction_record.reference =
              v_original_funding.document_number
        for update;

        if not found then
            raise exception
                'AGENT_DEPOSIT_DOCUMENT_NOT_FOUND';
        end if;

        /*
         * Resolve original recipient through the agent wallet.
         *
         * The user may have the agent, vendor, or merchant role,
         * while the funded wallet owner remains agent.
         */
        v_stage := 'fetch original funding recipient';

        select user_record.*
        into v_agent
        from public.wallet_entry wallet_entry_record
        join public.wallet wallet_record
          on wallet_record.id =
             wallet_entry_record.wallet_id
        join public.users user_record
          on user_record.id =
             wallet_record.user_id
        join public.user_role role_record
          on role_record.id =
             user_record.role_id
        where wallet_entry_record.document_number =
              v_original_funding.document_number

          and wallet_entry_record.country_code =
              v_executor.country_code

          and wallet_record.owner_type =
              'agent'::public."WalletOwnerType"

          and lower(
              role_record.name::text
          ) in (
              'agent',
              'vendor',
              'merchant'
          )
        limit 1;

        if not found then
            raise exception
                'ORIGINAL_FUNDING_RECIPIENT_NOT_FOUND';
        end if;

        v_currency_code :=
            lower(
                v_original_funding.currency_code
            );

        v_amount :=
            v_original_funding.gross_amount;

        if v_amount is null
           or v_amount <= 0
        then
            raise exception
                'INVALID_ORIGINAL_AMOUNT';
        end if;

        v_reference :=
            v_original_funding.reference;

        v_sender_id :=
            v_agent.id;

        v_receiver_id :=
            v_treasury.id;

        v_sender_wallet_owner :=
            'agent'::public."WalletOwnerType";

        v_receiver_wallet_owner :=
            'treasury'::public."WalletOwnerType";

        v_audit_action :=
            'agent_fund_reversed'::public."AuditActionType";

        v_funding_description :=
            format(
                'Agent funding reversal %s',
                coalesce(
                    v_agent.email,
                    v_agent.phone,
                    v_agent.id
                )
            );

        v_deposit_description :=
            format(
                'Agent deposit reversal %s',
                coalesce(
                    v_agent.email,
                    v_agent.phone,
                    v_agent.id
                )
            );
    end if;

    /*
     * Fetch mappings.
     */
    v_stage := 'fetch funding mappings';

    select array_agg(mapping_record)
    into v_funding_mappings
    from public.fetch_gl_mappings(
        v_funding_transaction_type
    ) as mapping_record;

    if v_funding_mappings is null
       or cardinality(v_funding_mappings) = 0
    then
        raise exception
            'AGENT_FUNDING_GL_MAPPINGS_NOT_FOUND';
    end if;

    v_stage := 'fetch deposit mappings';

    select array_agg(mapping_record)
    into v_deposit_mappings
    from public.fetch_gl_mappings(
        v_deposit_transaction_type
    ) as mapping_record;

    if v_deposit_mappings is null
       or cardinality(v_deposit_mappings) = 0
    then
        raise exception
            'AGENT_DEPOSIT_GL_MAPPINGS_NOT_FOUND';
    end if;

    /*
     * Build posting components.
     */
    v_stage := 'build funding components';

    v_funding_components :=
        public.build_posting_components(
            v_funding_transaction_type,
            v_amount,
            v_funding_mappings,
            v_executor.country_code,
            v_currency_code,
            false
        );

    v_stage := 'build deposit components';

    v_deposit_components :=
        public.build_posting_components(
            v_deposit_transaction_type,
            v_amount,
            v_deposit_mappings,
            v_executor.country_code,
            v_currency_code,
            false
        );

    /*
     * Fiscal period.
     */
    v_stage := 'fetch fiscal period';

    select
        fiscal_period.fiscal_year,
        fiscal_period.period
    into
        v_fiscal_year,
        v_period
    from public.fetch_fiscal_period(
        v_executor.country_code
    ) as fiscal_period;

    if not found then
        raise exception
            'FISCAL_PERIOD_NOT_FOUND';
    end if;

    /*
     * Document prefixes.
     */
    v_stage := 'fetch funding document prefix';

    v_funding_prefix :=
        public.fetch_transaction_doc_num_prefix(
            v_funding_transaction_type
        );

    if nullif(
        btrim(v_funding_prefix),
        ''
    ) is null
    then
        raise exception
            'AGENT_FUNDING_DOCUMENT_PREFIX_NOT_FOUND';
    end if;

    v_stage := 'fetch deposit document prefix';

    v_deposit_prefix :=
        public.fetch_transaction_doc_num_prefix(
            v_deposit_transaction_type
        );

    if nullif(
        btrim(v_deposit_prefix),
        ''
    ) is null
    then
        raise exception
            'AGENT_DEPOSIT_DOCUMENT_PREFIX_NOT_FOUND';
    end if;

    /*
     * Generate document numbers.
     */
    v_stage := 'generate funding document number';

    v_funding_document_number :=
        public.generate_document_number(
            v_funding_prefix,
            v_fiscal_year,
            v_period,
            v_executor.country_code
        );

    v_stage := 'generate deposit document number';

    v_deposit_document_number :=
        public.generate_document_number(
            v_deposit_prefix,
            v_fiscal_year,
            v_period,
            v_executor.country_code
        );

    /*
     * Receiver notification.
     */
    v_stage := 'create receiver notification';

    v_receiver_notification :=
        public.create_notification_message(
            p_country_code =>
                v_executor.country_code,

            p_transaction_type =>
                v_funding_transaction_type,

            p_audience =>
                'receiver'::public."NotificationAudience",

            p_amount =>
                v_amount,

            p_currency =>
                upper(v_currency_code),

            p_reference =>
                case
                    when v_is_reversal then
                        v_funding_document_number
                    else
                        v_reference
                end,

            p_quantity =>
                0,

            p_sender =>
                coalesce(
                    case
                        when v_is_reversal
                            then v_agent.email
                        else v_treasury.email
                    end,
                    'Ngoda'
                ),

            p_receiver =>
                coalesce(
                    case
                        when v_is_reversal
                            then v_treasury.email
                        else v_agent.email
                    end,
                    v_receiver_id
                )
        );

    /*
     * Create agent-deposit transaction.
     */
    v_stage := 'create agent deposit transaction';

    insert into public.financial_transaction (
        fiscal_year,
        period,
        country_code,
        document_number,
        reference,
        transaction_type,
        description,
        created_by,
        gross_amount,
        currency_code,
        reversal_of,
        reversed_by
    )
    values (
        v_fiscal_year,
        v_period,
        v_executor.country_code,
        v_deposit_document_number,
        v_funding_document_number,
        v_deposit_transaction_type,
        v_deposit_description,
        v_executor.id,
        v_amount,
        v_currency_code,
        case
            when v_is_reversal
                then v_original_deposit.document_number
            else null
        end,
        case
            when v_is_reversal
                then v_executor.id
            else null
        end
    )
    returning id
    into v_deposit_transaction_id;

    /*
     * Post agent-deposit entries.
     */
    v_stage := 'post agent deposit entries';

    perform *
    from public.post_financial_entries(
        p_document_number =>
            v_deposit_document_number,

        p_country_code =>
            v_executor.country_code,

        p_transaction_id =>
            v_deposit_transaction_id,

        p_transaction_type =>
            v_deposit_transaction_type,

        p_created_by =>
            v_executor.id,

        p_components =>
            v_deposit_components,

        p_mappings =>
            v_deposit_mappings,

        p_currency_code =>
            v_currency_code,

        p_fiscal_year =>
            v_fiscal_year,

        p_period =>
            v_period,

        p_reference =>
            case
                when v_is_reversal
                    then v_original_deposit.document_number
                else v_funding_document_number
            end,

        p_deposit_type =>
            null
    );

    /*
     * Create agent-funding transaction.
     */
    v_stage := 'create agent funding transaction';

    insert into public.financial_transaction (
        fiscal_year,
        period,
        country_code,
        document_number,
        reference,
        transaction_type,
        description,
        created_by,
        gross_amount,
        currency_code,
        reversal_of,
        reversed_by
    )
    values (
        v_fiscal_year,
        v_period,
        v_executor.country_code,
        v_funding_document_number,
        case
            when v_is_reversal
                then v_funding_document_number
            else v_reference
        end,
        v_funding_transaction_type,
        v_funding_description,
        v_executor.id,
        v_amount,
        v_currency_code,
        case
            when v_is_reversal
                then v_original_funding.document_number
            else null
        end,
        case
            when v_is_reversal
                then v_executor.id
            else null
        end
    )
    returning id
    into v_funding_transaction_id;

    /*
     * Post agent-funding entries.
     */
    v_stage := 'post agent funding entries';

    perform *
    from public.post_financial_entries(
        p_document_number =>
            v_funding_document_number,

        p_country_code =>
            v_executor.country_code,

        p_transaction_id =>
            v_funding_transaction_id,

        p_transaction_type =>
            v_funding_transaction_type,

        p_created_by =>
            v_executor.id,

        p_components =>
            v_funding_components,

        p_mappings =>
            v_funding_mappings,

        p_currency_code =>
            v_currency_code,

        p_fiscal_year =>
            v_fiscal_year,

        p_period =>
            v_period,

        p_reference =>
            case
                when v_is_reversal
                    then v_original_funding.document_number
                else v_reference
            end,

        p_deposit_type =>
            null
    );

    /*
     * Wallet movement:
     *
     * Funding: treasury -> agent-operation wallet
     * Reversal: agent-operation wallet -> treasury
     */
    v_stage := 'post wallet entries';

    perform *
    from public.post_wallet_entries(
        p_fiscal_year =>
            v_fiscal_year,

        p_period =>
            v_period,

        p_document_number =>
            v_funding_document_number,

        p_reference =>
            case
                when v_is_reversal
                    then v_original_funding.document_number
                else v_reference
            end,

        p_receiver_id =>
            v_receiver_id,

        p_sender_id =>
            v_sender_id,

        p_transaction_type =>
            v_funding_transaction_type,

        p_credit_amount =>
            v_amount,

        p_debit_amount =>
            v_amount,

        p_sender_wallet_owner =>
            v_sender_wallet_owner,

        p_receiver_wallet_owner =>
            v_receiver_wallet_owner,

        p_currency_code =>
            v_currency_code,

        p_country_code =>
            v_executor.country_code,

        p_audit_action_type =>
            v_audit_action,

        p_treasury_id =>
            v_treasury.id,

        p_fee_amount =>
            0,

        p_ip_address =>
            p_ip_address,

        p_receiver_notification =>
            v_receiver_notification,

        p_sender_notification =>
            null
    );

    return jsonb_build_object(
        'success',
        true,

        'transaction_type',
        v_funding_transaction_type,

        'document_number',
        v_funding_document_number,

        'deposit_document_number',
        v_deposit_document_number,

        'reference',
        case
            when v_is_reversal
                then v_funding_document_number
            else v_reference
        end,

        'reversal_of',
        case
            when v_is_reversal
                then v_original_funding.document_number
            else null
        end,

        'funded_amount',
        v_amount::text,

        'currency',
        v_currency_code,

        'agent_id',
        v_agent.id
    );

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

            message = format(
                'AGENT_FUNDING_FAILED at [%s]: %s',
                v_stage,
                v_error_message
            ),

            detail = concat_ws(
                E'\n',
                nullif(v_error_detail, ''),
                nullif(v_error_context, '')
            ),

            hint = coalesce(
                nullif(v_error_hint, ''),
                'Check the Agent Funding stage reported in the error'
            );
end;
$function$;


revoke all on function
    public.execute_my_agent_funding(
        public."TransactionType",
        text,
        text,
        numeric,
        text,
        text,
        text
    )
from public;

revoke all on function
    public.execute_my_agent_funding(
        public."TransactionType",
        text,
        text,
        numeric,
        text,
        text,
        text
    )
from anon;

grant execute on function
    public.execute_my_agent_funding(
        public."TransactionType",
        text,
        text,
        numeric,
        text,
        text,
        text
    )
to authenticated;