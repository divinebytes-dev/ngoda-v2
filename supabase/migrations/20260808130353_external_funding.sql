create or replace function public.execute_my_external_funding(
    p_currency_code text default null,
    p_amount numeric default null,
    p_original_document_number text default null,
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

    v_transaction_type
        public."TransactionType";

    v_description text;

    v_fiscal_year integer;
    v_period integer;

    v_mappings
        public.transaction_gl_mapping[];

    v_components
        public.posting_component[];

    v_document_prefix text;
    v_document_number text;

    v_reference text;
    v_reversal_of text;
    v_reversed_by text;

    v_financial_transaction_id bigint;

    v_stage text := 'initialization';

    v_error_state text;
    v_error_message text;
    v_error_detail text;
    v_error_hint text;
    v_error_context text;
begin
    /*
     * Authenticate and authorize.
     */
    v_stage := 'authenticate';

    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHENTICATED';
    end if;

    v_stage := 'authorize finance role';

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
     * Fetch trusted user context.
     */
    v_stage := 'fetch user context';

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
     * Decide whether this is new external funding or a
     * reversal.
     */
    if nullif(
        btrim(p_original_document_number),
        ''
    ) is null
    then
        /*
         * Normal external funding.
         */
        v_stage := 'validate external funding input';

        v_transaction_type :=
            'external_funding'::public."TransactionType";

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
            'External funding';

        v_reversal_of :=
            null;

        v_reversed_by :=
            null;
    else
        /*
         * External funding reversal.
         */
        v_stage :=
            'lock original external funding document';

        select financial_transaction_record.*
        into v_original_document
        from public.financial_transaction
            financial_transaction_record
        where financial_transaction_record.document_number =
              btrim(
                  p_original_document_number
              )

          and financial_transaction_record.country_code =
              v_user.country_code
        for update;

        if not found then
            raise exception
                'DOCUMENT_NOT_FOUND';
        end if;

        v_stage :=
            'validate original transaction type';

        if v_original_document.transaction_type <>
           'external_funding'::public."TransactionType"
        then
            raise exception
                'DOCUMENT_IS_NOT_EXTERNAL_FUNDING';
        end if;

        /*
         * Prevent the same document from being reversed more
         * than once.
         */
        v_stage :=
            'check existing reversal';

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
         * Currency and amount are trusted from the original
         * document.
         */
        v_transaction_type :=
            'external_funding_reversal'::public."TransactionType";

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
                'External funding reversal for document %s',
                v_original_document.document_number
            );

        v_reversal_of :=
            v_original_document.document_number;

        v_reversed_by :=
            v_user.id;
    end if;

    /*
     * Fetch the GL mappings.
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
     *
     * Reversal mappings/components determine the reversed
     * debit and credit directions.
     */
    v_stage := 'build posting components';

    v_components :=
        public.build_posting_components(
            v_transaction_type,
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
     * Fetch the configured document prefix.
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

    /*
     * Generate the document number.
     */
    v_stage := 'generate document number';

    v_document_number :=
        public.generate_document_number(
            v_document_prefix,
            v_fiscal_year,
            v_period,
            v_user.country_code
        );

    /*
     * Normal funding references itself.
     *
     * A reversal references the original document.
     */
    v_reference :=
        coalesce(
            v_reversal_of,
            v_document_number
        );

    /*
     * Create financial transaction header.
     */
    v_stage :=
        'create financial transaction';

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
        v_document_number,
        v_reference,
        v_fiscal_year,
        v_user.country_code,
        v_period,
        v_transaction_type,
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
     * Post the GL entries.
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
            v_currency_code,

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
     * Create audit record.
     *
     * treasury_funded is retained because it is the existing
     * AuditActionType used by this operation.
     */
    v_stage := 'create audit log';

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
        'treasury_funded'::public."AuditActionType",
        'external',
        'finance',
        jsonb_build_object(
            'document_number',
            v_document_number,

            'reference',
            v_reference,

            'transaction_type',
            v_transaction_type,

            'amount',
            v_amount::text,

            'currency_code',
            v_currency_code,

            'reversal_of',
            v_reversal_of
        ),
        p_ip_address,
        v_document_number
    );

    return jsonb_build_object(
        'success',
        true,

        'document_number',
        v_document_number,

        'reference',
        v_reference,

        'transaction_type',
        v_transaction_type,

        'currency_code',
        v_currency_code,

        'amount',
        v_amount::text,

        'reversal_of',
        v_reversal_of
    );

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
                    'EXTERNAL_FUNDING_FAILED at [%s]: %s',
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
                    'Check the external-funding stage reported in the error'
                );
end;
$function$;


revoke all on function
    public.execute_my_external_funding(
        text,
        numeric,
        text,
        text
    )
from public;

revoke all on function
    public.execute_my_external_funding(
        text,
        numeric,
        text,
        text
    )
from anon;

grant execute on function
    public.execute_my_external_funding(
        text,
        numeric,
        text,
        text
    )
to authenticated;