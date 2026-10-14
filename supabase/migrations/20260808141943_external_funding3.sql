create or replace function public.execute_my_external_funding(
    p_transaction_type public."TransactionType",
    p_currency_code text default null,
    p_amount numeric default null,
    p_document_number text default null,
    p_ip_address text default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
    v_user public.users%rowtype;

    v_original_document
        public.financial_transaction%rowtype;

    v_currency_code text;
    v_amount numeric;

    /*
     * Header reference must always be unique.
     */
    v_transaction_reference text;

    /*
     * Entry reference connects the reversal entries to the
     * original document.
     */
    v_entry_reference text;

    v_reversal_of text;
    v_reversed_by text;

    v_description text;

    v_audit_action
        public."AuditActionType";

    v_fiscal_year integer;
    v_period integer;

    v_mappings
        public.transaction_gl_mapping[];

    v_components
        public.posting_component[];

    v_document_prefix text;
    v_new_document_number text;

    v_financial_transaction_id bigint;
begin
    /*
     * Authenticate and authorize.
     */
    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHENTICATED';
    end if;

    if not public.has_role(
        array[
            'finance'
        ]::text[]
    ) then
        raise exception using
            errcode = '42501',
            message = 'FORBIDDEN';
    end if;

    /*
     * Only these two transaction types are supported.
     */
    if p_transaction_type not in (
        'external_funding'::public."TransactionType",
        'external_funding_reversal'::public."TransactionType"
    ) then
        raise exception
            'INVALID_EXTERNAL_FUNDING_TRANSACTION_TYPE_%',
            p_transaction_type;
    end if;

    /*
     * Fetch the authenticated finance user.
     */
    v_user :=
        public.fetch_user_by_id(
            auth.uid()::text
        );

    if v_user.id is null then
        raise exception
            'USER_NOT_FOUND';
    end if;

    if v_user.country_code is null then
        raise exception
            'USER_COUNTRY_NOT_CONFIGURED';
    end if;

    /*
     * Normal external funding.
     */
    if p_transaction_type =
       'external_funding'::public."TransactionType"
    then
        v_currency_code :=
            lower(
                nullif(
                    btrim(p_currency_code),
                    ''
                )
            );

        if v_currency_code is null then
            raise exception
                'CURRENCY_IS_REQUIRED';
        end if;

        v_amount :=
            p_amount;

        if v_amount is null then
            raise exception
                'AMOUNT_IS_REQUIRED';
        end if;

        if v_amount <= 0 then
            raise exception
                'INVALID_AMOUNT';
        end if;

        v_description :=
            'External funding received in bank';

        v_audit_action :=
            'external_funding'::public."AuditActionType";

        v_reversal_of :=
            null;

        v_reversed_by :=
            null;
    end if;

    /*
     * External funding reversal.
     */
    if p_transaction_type =
       'external_funding_reversal'::public."TransactionType"
    then
        if nullif(
            btrim(p_document_number),
            ''
        ) is null
        then
            raise exception
                'DOCUMENT_NUMBER_REQUIRED_FOR_REVERSAL';
        end if;

        /*
         * Lock the original document.
         */
        select financial_transaction_record.*
        into v_original_document
        from public.financial_transaction
            financial_transaction_record
        where financial_transaction_record.document_number =
              btrim(p_document_number)

          and financial_transaction_record.country_code =
              v_user.country_code
        for update;

        if not found then
            raise exception
                'DOCUMENT_NOT_FOUND';
        end if;

        if v_original_document.transaction_type <>
           'external_funding'::public."TransactionType"
        then
            raise exception
                'DOCUMENT_IS_NOT_EXTERNAL_FUNDING';
        end if;

        /*
         * Prevent duplicate reversal.
         */
        perform 1
        from public.financial_transaction
            reversal_record
        where reversal_record.country_code =
              v_user.country_code

          and reversal_record.reversal_of =
              v_original_document.document_number

          and reversal_record.transaction_type =
              'external_funding_reversal'::public."TransactionType"
        limit 1;

        if found then
            raise exception
                'DOCUMENT_ALREADY_REVERSED';
        end if;

        /*
         * Reversal values come from the original document.
         */
        v_currency_code :=
            lower(
                v_original_document.currency_code
            );

        v_amount :=
            v_original_document.gross_amount;

        if v_amount is null
           or v_amount <= 0
        then
            raise exception
                'INVALID_ORIGINAL_DOCUMENT_AMOUNT';
        end if;

        v_description :=
            format(
                'External funding reversal for %s',
                v_original_document.document_number
            );

        v_audit_action :=
            'external_funding_reversed'::public."AuditActionType";

        v_reversal_of :=
            v_original_document.document_number;

        v_reversed_by :=
            v_user.id;
    end if;

    /*
     * Fetch GL mappings.
     */
    select array_agg(mapping_record)
    into v_mappings
    from public.fetch_gl_mappings(
        p_transaction_type
    ) as mapping_record;

    if v_mappings is null
       or cardinality(v_mappings) = 0
    then
        raise exception
            'GL_MAPPINGS_NOT_FOUND';
    end if;

    /*
     * Build normal or reversal components.
     */
    v_components :=
        public.build_posting_components(
            p_transaction_type,
            v_amount,
            v_mappings,
            v_user.country_code,
            v_currency_code,
            false
        );

    if v_components is null
       or cardinality(v_components) = 0
    then
        raise exception
            'POSTING_COMPONENTS_NOT_FOUND';
    end if;

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
        v_user.country_code
    ) as fiscal_period;

    if not found then
        raise exception
            'FISCAL_PERIOD_NOT_FOUND';
    end if;

    /*
     * Fetch and generate document number.
     */
    v_document_prefix :=
        public.fetch_transaction_doc_num_prefix(
            p_transaction_type
        );

    if v_document_prefix is null
       or btrim(v_document_prefix) = ''
    then
        raise exception
            'DOCUMENT_PREFIX_NOT_FOUND';
    end if;

    v_new_document_number :=
        public.generate_document_number(
            v_document_prefix,
            v_fiscal_year,
            v_period,
            v_user.country_code
        );

    /*
     * The financial transaction header always receives its
     * own unique reference.
     */
    v_transaction_reference :=
        v_new_document_number;

    /*
     * Financial entries use the original document as their
     * reference for reversals.
     */
    v_entry_reference :=
        coalesce(
            v_reversal_of,
            v_new_document_number
        );

    /*
     * Create the financial transaction.
     */
    insert into public.financial_transaction (
        document_number,
        reference,
        fiscal_year,
        country_code,
        period,
        transaction_type,
        description,
        created_by,
        gross_amount,
        reversal_of,
        reversed_by,
        currency_code
    )
    values (
        v_new_document_number,
        v_transaction_reference,
        v_fiscal_year,
        v_user.country_code,
        v_period,
        p_transaction_type,
        v_description,
        v_user.id,
        v_amount,
        v_reversal_of,
        v_reversed_by,
        v_currency_code
    )
    returning id
    into v_financial_transaction_id;

    /*
     * Post financial entries.
     *
     * No wallet entries are posted because external funding
     * remains in the bank GL until it is transferred to
     * treasury.
     */
    perform *
    from public.post_financial_entries(
        p_document_number =>
            v_new_document_number,

        p_country_code =>
            v_user.country_code,

        p_transaction_id =>
            v_financial_transaction_id,

        p_transaction_type =>
            p_transaction_type,

        p_created_by =>
            v_user.id,

        p_components =>
            v_components,

        p_mappings =>
            v_mappings,

        p_currency_code =>
            v_currency_code,

        p_fiscal_year =>
            v_fiscal_year,

        p_period =>
            v_period,

        p_reference =>
            v_entry_reference,

        p_deposit_type =>
            null
    );

    /*
     * Create the audit entry.
     */
    insert into public.audit_log (
        fiscal_year,
        period,
        user_id,
        country_code,
        action_type,
        entity_type,
        entity_id,
        metadata,
        ip_address,
        document_number
    )
    values (
        v_fiscal_year,
        v_period,
        v_user.id,
        v_user.country_code,
        v_audit_action,
        'external',
        'finance',
        jsonb_build_object(
            'document_number',
            v_new_document_number,

            'reference',
            v_transaction_reference,

            'entry_reference',
            v_entry_reference,

            'transaction_type',
            p_transaction_type,

            'currency_code',
            v_currency_code,

            'amount',
            v_amount::text,

            'reversal_of',
            v_reversal_of
        ),
        p_ip_address,
        v_new_document_number
    );

    return jsonb_build_object(
        'success',
        true,

        'document_number',
        v_new_document_number,

        'reference',
        v_transaction_reference,

        'transaction_type',
        p_transaction_type,

        'currency_code',
        v_currency_code,

        'amount',
        v_amount::text,

        'reversal_of',
        v_reversal_of
    );
end;
$function$;


revoke all on function
    public.execute_my_external_funding(
        public."TransactionType",
        text,
        numeric,
        text,
        text
    )
from public;

revoke all on function
    public.execute_my_external_funding(
        public."TransactionType",
        text,
        numeric,
        text,
        text
    )
from anon;

grant execute on function
    public.execute_my_external_funding(
        public."TransactionType",
        text,
        numeric,
        text,
        text
    )
to authenticated;