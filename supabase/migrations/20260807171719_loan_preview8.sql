create or replace function public.execute_my_loan_disbursement(
    p_requested_amount text,
    p_token_balance text,
    p_reference text,
    p_currency_code text default 'usd',
    p_ip_address text default null
)
returns table (
    success boolean,
    document_number text,
    loan_id text,
    collateral_locked text,
    initiation_fee text,
    net_disbursed text,
    notification_id text,
    device_tokens text[],
    push_title text,
    push_body text,
    push_reference text
)
language plpgsql
security definer
set search_path to ''
as $function$
declare
    v_transaction_type
        public."TransactionType" :=
            'loan_disbursement'::public."TransactionType";

    v_stage text := 'initialization';

    v_user public.users%rowtype;
    v_treasury public.users%rowtype;
    v_collateral public.collateral%rowtype;

    v_reference text;
    v_currency text;
    v_requested_amount numeric;

    v_preview jsonb;
    v_preview_data jsonb;

    v_required_collateral numeric;
    v_initiation_fee numeric;
    v_net_disbursed numeric;
    v_liquidation_price numeric;
    v_ltv_percent numeric;
    v_liquidation_ltv_percent numeric;
    v_loan_interest numeric := 12;

    v_fiscal_year integer;
    v_period integer;

    v_mappings
        public.transaction_gl_mapping[];

    v_components
        public.posting_component[];

    v_document_prefix text;
    v_document_number text;

    v_financial_transaction_id bigint;
    v_loan_id text;

    v_receiver_notification
        public.notification_message;

    v_receiver_notification_id text;

    v_device_tokens text[] :=
        array[]::text[];

    v_error_state text;
    v_error_message text;
    v_error_detail text;
    v_error_hint text;
    v_error_context text;
begin
    /*
     * Authenticate and authorize customer.
     */
    v_stage := 'authorize customer';

    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHORIZED';
    end if;

    if not public.has_role(
        array[
            'customer'
        ]::text[]
    ) then
        raise exception using
            errcode = '42501',
            message = 'FORBIDDEN';
    end if;

    select user_record.*
    into v_user
    from public.users user_record
    where user_record.id =
          auth.uid()::text
    limit 1;

    if not found then
        raise exception
            'USER_NOT_FOUND';
    end if;

    if v_user.status <>
       'active'::public."UserStatus"
    then
        raise exception
            'USER_NOT_ACTIVE';
    end if;

    if v_user.country_code is null
       or btrim(v_user.country_code) = ''
    then
        raise exception
            'USER_COUNTRY_NOT_CONFIGURED';
    end if;

    /*
     * Parse amount.
     */
    v_stage := 'parse requested amount';

    begin
        v_requested_amount :=
            nullif(
                btrim(p_requested_amount),
                ''
            )::numeric;
    exception
        when invalid_text_representation
          or numeric_value_out_of_range
        then
            raise exception
                'INVALID_LOAN_AMOUNT';
    end;

    if v_requested_amount is null
       or v_requested_amount <= 0
    then
        raise exception
            'INVALID_LOAN_AMOUNT';
    end if;

    /*
     * Parse reference.
     */
    v_stage := 'parse reference';

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
     * Parse currency.
     */
    v_stage := 'parse currency';

    v_currency :=
        lower(
            nullif(
                btrim(p_currency_code),
                ''
            )
        );

    if v_currency is null then
        raise exception
            'CURRENCY_MISSING';
    end if;

    if v_currency <> 'usd' then
        raise exception
            'UNSUPPORTED_LOAN_CURRENCY';
    end if;

    /*
     * Prevent duplicate reference processing.
     */
    v_stage := 'lock loan reference';

    perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(
            v_reference,
            0
        )
    );

    perform 1
    from public.financial_transaction
        transaction_record
    where transaction_record.reference =
          v_reference;

    if found then
        raise exception using
            errcode = '23505',
            message = 'TRANSACTION_REPLAY';
    end if;

    /*
     * Fetch country treasury.
     */
    v_stage := 'fetch country treasury';

    v_treasury :=
        public.fetch_country_treasury(
            v_user.country_code
        );

    if v_treasury.id is null then
        raise exception
            'TREASURY_WALLET_NOT_CONFIGURED';
    end if;

    /*
     * Ensure collateral row exists.
     */
    v_stage := 'create collateral row';

    insert into public.collateral (
        user_id,
        locked_tokens,
        country_code
    )
    values (
        v_user.id,
        0,
        v_user.country_code
    )
    on conflict (
        user_id
    )
    do nothing;

    /*
     * Lock collateral before recalculating the loan.
     */
    v_stage := 'lock collateral row';

    select collateral_record.*
    into v_collateral
    from public.collateral
        collateral_record
    where collateral_record.user_id =
          v_user.id
    for update;

    if not found then
        raise exception
            'COLLATERAL_NOT_FOUND';
    end if;

    if v_collateral.country_code is distinct from
       v_user.country_code
    then
        raise exception
            'COLLATERAL_COUNTRY_MISMATCH';
    end if;

    /*
     * Recalculate using the same preview function.
     */
    v_stage := 'recalculate loan preview';

    v_preview :=
        public.preview_my_loan(
            p_requested_amount =>
                v_requested_amount::text,

            p_token_balance =>
                p_token_balance,

            p_currency_code =>
                v_currency
        );

    if v_preview is null
       or coalesce(
           (v_preview ->> 'success')::boolean,
           false
       ) = false
    then
        raise exception
            'LOAN_PREVIEW_FAILED';
    end if;

    v_preview_data :=
        v_preview -> 'data';

    if v_preview_data is null then
        raise exception
            'LOAN_PREVIEW_DATA_NOT_FOUND';
    end if;

    begin
        v_required_collateral :=
            (
                v_preview_data
                ->> 'required_collateral_grams'
            )::numeric;

        v_initiation_fee :=
            (
                v_preview_data
                ->> 'initiation_fee'
            )::numeric;

        v_net_disbursed :=
            (
                v_preview_data
                ->> 'net_disbursed'
            )::numeric;

        v_liquidation_price :=
            (
                v_preview_data
                -> 'risk'
                ->> 'liquidationPrice'
            )::numeric;

        v_ltv_percent :=
            (
                v_preview_data
                ->> 'ltv_percent'
            )::numeric;

        v_liquidation_ltv_percent :=
            (
                v_preview_data
                ->> 'liquidation_ltv_percent'
            )::numeric;
    exception
        when invalid_text_representation
          or numeric_value_out_of_range
        then
            raise exception
                'INVALID_LOAN_PREVIEW_RESULT';
    end;

    if v_required_collateral <= 0 then
        raise exception
            'INVALID_COLLATERAL_AMOUNT';
    end if;

    if v_initiation_fee < 0 then
        raise exception
            'INVALID_INITIATION_FEE';
    end if;

    if v_net_disbursed <= 0 then
        raise exception
            'INVALID_NET_DISBURSEMENT';
    end if;

    if v_liquidation_price <= 0 then
        raise exception
            'INVALID_LIQUIDATION_PRICE';
    end if;

    /*
     * Fetch loan interest configuration.
     */
    v_stage := 'fetch loan interest';

    select loan_config_record.rate
    into v_loan_interest
    from public.loan_config
        loan_config_record
    where loan_config_record.config_type =
          'loan_interest'
      and loan_config_record.is_active =
          true
    limit 1;

    v_loan_interest :=
        coalesce(
            v_loan_interest,
            12
        );

    if v_loan_interest < 0 then
        raise exception
            'INVALID_LOAN_INTEREST_RATE';
    end if;

    /*
     * Fetch fiscal period.
     */
    v_stage := 'fetch fiscal period';

    select
        fiscal_period.fiscal_year,
        fiscal_period.period
    into
        v_fiscal_year,
        v_period
    from public.fetch_fiscal_period(
        v_user.country_code
    ) as fiscal_period;

    if not found then
        raise exception
            'FISCAL_PERIOD_NOT_FOUND';
    end if;

    /*
     * Fetch GL mappings.
     */
    v_stage := 'fetch GL mappings';

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

    /*
     * Build posting components.
     */
    v_stage := 'build posting components';

    v_components :=
        public.build_posting_components(
            v_transaction_type,
            v_requested_amount,
            v_mappings,
            v_user.country_code,
            v_currency,
            false
        );

    if v_components is null
       or cardinality(v_components) = 0
    then
        raise exception
            'POSTING_COMPONENTS_NOT_FOUND';
    end if;

    /*
     * Build customer notification.
     */
    v_stage := 'create customer notification';

    v_receiver_notification :=
        public.create_notification_message(
            v_user.country_code,
            v_transaction_type,
            'receiver'::public."NotificationAudience",
            v_requested_amount,
            upper(v_currency),
            v_reference,
            0,
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

    v_device_tokens :=
        coalesce(
            public.fetch_device_tokens(
                v_user.country_code,
                v_user.id
            ),
            array[]::text[]
        );

    /*
     * Generate document number.
     */
    v_stage := 'fetch document prefix';

    v_document_prefix :=
        public.fetch_transaction_doc_num_prefix(
            v_transaction_type
        );

    if v_document_prefix is null
       or btrim(v_document_prefix) = ''
    then
        raise exception
            'DOCUMENT_PREFIX_NOT_FOUND';
    end if;

    v_stage := 'generate document number';

    v_document_number :=
        public.generate_document_number(
            v_document_prefix,
            v_fiscal_year,
            v_period,
            v_user.country_code
        );

    /*
     * Create financial transaction.
     */
    v_stage := 'create financial transaction';

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
        v_fiscal_year,
        v_reference,
        v_period,
        v_transaction_type,
        'Loan disbursement for user ' ||
            v_user.id,
        v_user.id,
        v_requested_amount,
        v_currency,
        v_user.country_code
    )
    returning id
    into v_financial_transaction_id;

    /*
     * Post financial entries.
     */
    v_stage := 'post financial entries';

    perform *
    from public.post_financial_entries(
        p_document_number =>
            v_document_number,

        p_country_code =>
            v_user.country_code,

        p_transaction_id =>
            v_financial_transaction_id,

        p_transaction_type =>
            v_transaction_type,

        p_created_by =>
            v_user.id,

        p_components =>
            v_components,

        p_mappings =>
            v_mappings,

        p_currency_code =>
            v_currency,

        p_fiscal_year =>
            v_fiscal_year,

        p_period =>
            v_period,

        p_reference =>
            v_reference,

        p_deposit_type =>
            null
    );

    /*
     * Transfer net loan proceeds from treasury to customer.
     */
    v_stage := 'post wallet entries';

    select posting_result.receiver_notification_id
    into v_receiver_notification_id
    from public.post_wallet_entries(
        p_fiscal_year =>
            v_fiscal_year,

        p_period =>
            v_period,

        p_document_number =>
            v_document_number,

        p_reference =>
            v_reference,

        p_receiver_id =>
            v_user.id,

        p_sender_id =>
            v_treasury.id,

        p_transaction_type =>
            v_transaction_type,

        p_credit_amount =>
            v_net_disbursed,

        p_debit_amount =>
            v_net_disbursed,

        p_sender_wallet_owner =>
            'treasury'::public."WalletOwnerType",

        p_receiver_wallet_owner =>
            'customer'::public."WalletOwnerType",

        p_currency_code =>
            v_currency,

        p_country_code =>
            v_user.country_code,

        p_audit_action_type =>
            'loan_issued'::public."AuditActionType",

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
    ) as posting_result;

    /*
     * Create loan.
     */
    v_stage := 'create loan';

    insert into public.loan (
        document_number,
        reference,
        user_id,
        fiscal_year,
        period,
        principal,
        net_amount,
        initiation_fee,
        interest_rate,
        collateral,
        max_ltv_percent,
        liquidation_ltv,
        liquidation_price,
        status,
        currency_code,
        country_code
    )
    values (
        v_document_number,
        v_reference,
        v_user.id,
        v_fiscal_year,
        v_period,
        v_requested_amount,
        v_net_disbursed,
        v_initiation_fee,
        v_loan_interest,
        v_required_collateral,
        v_ltv_percent,
        v_liquidation_ltv_percent,
        v_liquidation_price,
        'active'::public."LoanStatus",
        v_currency,
        v_user.country_code
    )
    returning id::text
    into v_loan_id;

    /*
     * Create loan principal entry.
     */
    v_stage := 'create loan entry';

    insert into public.loan_entry (
        loan_id,
        fiscal_year,
        period,
        document_number,
        entry_type,
        debit_principal,
        credit_principal,
        debit_interest,
        credit_interest,
        currency_code,
        country_code
    )
    values (
        v_loan_id,
        v_fiscal_year,
        v_period,
        v_document_number,
        'disbursement'::public."LoanEntryType",
        v_requested_amount,
        0,
        0,
        0,
        v_currency,
        v_user.country_code
    );

    /*
     * Increase locked collateral.
     */
    v_stage := 'update collateral';

    update public.collateral
    set
        locked_tokens =
            coalesce(
                locked_tokens,
                0
            ) +
            v_required_collateral
    where user_id =
          v_user.id;

    if not found then
        raise exception
            'COLLATERAL_UPDATE_FAILED';
    end if;

    /*
     * Record the collateral increase as a debit.
     */
    v_stage := 'create collateral entry';

    insert into public.collateral_entry (
        loan_id,
        document_number,
        debit,
        credit,
        country_code
    )
    values (
        v_loan_id,
        v_document_number,
        v_required_collateral,
        0,
        v_user.country_code
    );

    /*
     * Existing signature:
     *
     * update_loan_snapshot(
     *     loan_id,
     *     user_id,
     *     country_code,
     *     debit_principal,
     *     credit_principal,
     *     debit_interest,
     *     credit_interest,
     *     fiscal_year,
     *     period
     * )
     */
    v_stage := 'update loan snapshot';

    perform public.update_loan_snapshot(
        v_loan_id,
        v_user.id,
        v_user.country_code,
        v_requested_amount,
        0::numeric,
        0::numeric,
        0::numeric,
        v_fiscal_year,
        v_period
    );

    /*
     * Existing signature:
     *
     * update_collateral_snapshot(
     *     user_id,
     *     country_code,
     *     debit,
     *     credit,
     *     fiscal_year,
     *     period
     * )
     */
    v_stage := 'update collateral snapshot';

    perform public.update_collateral_snapshot(
        v_user.id,
        v_user.country_code,
        v_required_collateral,
        0::numeric,
        v_fiscal_year,
        v_period
    );

    return query
    select
        true,
        v_document_number,
        v_loan_id,

        to_char(
            round(
                v_required_collateral,
                6
            ),
            'FM999999999999999999999999990.000000'
        ),

        to_char(
            round(
                v_initiation_fee,
                2
            ),
            'FM999999999999999999999999990.00'
        ),

        to_char(
            round(
                v_net_disbursed,
                2
            ),
            'FM999999999999999999999999990.00'
        ),

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
                    'LOAN_DISBURSEMENT_FAILED at [%s]: %s',
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
                    'Check the Loan Disbursement stage reported in the error'
                );
end;
$function$;


revoke all on function
    public.execute_my_loan_disbursement(
        text,
        text,
        text,
        text,
        text
    )
from public;

revoke execute on function
    public.execute_my_loan_disbursement(
        text,
        text,
        text,
        text,
        text
    )
from anon;

grant execute on function
    public.execute_my_loan_disbursement(
        text,
        text,
        text,
        text,
        text
    )
to authenticated;