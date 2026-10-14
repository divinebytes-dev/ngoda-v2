revoke all
on function public.cash_transfer(
    text,
    jsonb,
    public."TransactionType",
    text,
    text,
    text
)
from public, anon, authenticated;

grant execute
on function public.cash_transfer(
    text,
    jsonb,
    public."TransactionType",
    text,
    text,
    text
)
to service_role;



CREATE OR REPLACE FUNCTION public.cash_transfer(p_sender_id text, p_transaction jsonb, p_transaction_type "TransactionType", p_country_code text, p_transaction_state_id text, p_ip_address text DEFAULT NULL::text)
 RETURNS TABLE(success boolean, amount text, fee text, currency text, receiver_notification_id text, device_tokens text[], push_title text, push_body text, push_reference text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
    v_decimals numeric := 100;

    v_amount numeric;
    v_principal numeric;
    v_currency text;
    v_reference text;
    v_receiver_identifier text;

    v_fiscal_year integer;
    v_period integer;

    v_receiver public.users%rowtype;
    v_sender public.users%rowtype;
    v_treasury public.users%rowtype;

    v_mappings public.transaction_gl_mapping[];
    v_components public.posting_component[];

    v_component_totals public.component_totals;
    v_principal_amount numeric;
    v_others_amount numeric;
    v_fee numeric := 0;

    v_sender_notification public.notification_message;
    v_receiver_notification public.notification_message;

    v_device_tokens text[] := array[]::text[];

    v_document_prefix text;
    v_document_number text;
    v_financial_transaction_id bigint;
    v_receiver_notification_id text;

    /*
     * Debugging information.
     */
    v_stage text := 'initialization';
    v_error_state text;
    v_error_message text;
    v_error_detail text;
    v_error_hint text;
    v_error_context text;
begin
    
        v_stage := 'validate and lock transaction state';

        perform 1
        from public.transaction_state ts
        where ts.id =
            p_transaction_state_id
        and ts.created_by =
            p_sender_id
        and ts.status =
            'processing'::public."TransactionStatus"
        for update;

        if not found then
            raise exception
                'INVALID_TRANSACTION_STATE';
        end if;
            
    v_stage := 'validate transaction type';

    if p_transaction_type <>
       'cash_transfer'::public."TransactionType"
    then
        raise exception
            'INVALID_CASH_TRANSFER_TRANSACTION_TYPE_%',
            p_transaction_type;
    end if;

    v_stage := 'parse transaction amount';

    v_amount :=
        (p_transaction ->> 'a')::numeric /
        v_decimals;

    v_principal := v_amount;

    v_stage := 'parse transaction currency';

    v_currency := p_transaction ->> 'c';

    v_stage := 'parse transaction reference';

    v_reference := p_transaction ->> 'r';

    v_stage := 'parse receiver identifier';

    v_receiver_identifier := p_transaction ->> 's';

    v_stage := 'fetch GL mappings';

    select array_agg(m)
    into v_mappings
    from public.fetch_gl_mappings(
        p_transaction_type
    ) as m;

    if v_mappings is null then
        raise exception 'GL_MAPPINGS_NOT_FOUND';
    end if;

    v_stage := 'build posting components';

    v_components :=
        public.build_posting_components(
            p_transaction_type,
            v_principal,
            v_mappings,
            p_country_code,
            v_currency,
            false
        );

    if v_components is null then
        raise exception 'POSTING_COMPONENTS_NOT_FOUND';
    end if;

    v_stage := 'fetch fiscal period';

    select
        fp.fiscal_year,
        fp.period
    into
        v_fiscal_year,
        v_period
    from public.fetch_fiscal_period(
        p_country_code
    ) as fp;

    v_stage := 'fetch receiver';

    v_receiver :=
        public.fetch_user_by_email_or_phone(
            v_receiver_identifier
        );

    v_stage := 'fetch sender';

    v_sender :=
        public.fetch_user_by_id(
            p_sender_id
        );

    v_stage := 'fetch country treasury';

    v_treasury :=
        public.fetch_country_treasury(
            p_country_code
        );

    v_stage := 'validate receiver status';

    if v_receiver.status <>
       'active'::public."UserStatus"
    then
        raise exception 'RECEIVER_NOT_ACTIVE';
    end if;

    v_stage := 'validate sender status';

    if v_sender.status <>
       'active'::public."UserStatus"
    then
        raise exception 'SENDER_NOT_ACTIVE';
    end if;

    v_stage := 'validate sender and receiver';

    if v_sender.id = v_receiver.id then
        raise exception 'OPERATION_NOT_ALLOWED';
    end if;

    if v_sender.country_code is distinct from
       v_receiver.country_code
    then
        raise exception 'OPERATION_NOT_ALLOWED';
    end if;

    if v_sender.country_code is distinct from
       p_country_code
    then
        raise exception 'OPERATION_NOT_ALLOWED';
    end if;

    v_stage := 'extract component totals';

    v_component_totals :=
        public.extract_component_totals(
            v_components,
            false
        );

    v_stage := 'read principal amount';

    v_principal_amount :=
        v_component_totals.principal_amount;

    v_stage := 'read other component amount';

    v_others_amount :=
        v_component_totals.others_amount;

    /*
     * Extract the transfer fee without using a procedural loop.
     */
    v_stage := 'extract transfer fee';

    select coalesce(c.credit_amount, 0)
    into v_fee
    from unnest(v_components) as c(
        component_type,
        debit_amount,
        credit_amount
    )
    where c.component_type =
          'transfer_fee'::public."ComponentType"
    limit 1;

    v_fee := coalesce(v_fee, 0);

    v_stage := 'validate transfer fee';

    if v_fee <= 0 then
        raise exception 'INVALID_FEE_AMOUNT';
    end if;

    v_stage := 'create sender notification';

    v_sender_notification :=
        public.create_notification_message(
            p_country_code,
            p_transaction_type,
            'sender'::public."NotificationAudience",
            v_principal_amount,
            upper(v_currency),
            v_reference || '-01',
            0,
            coalesce(
                v_sender.email,
                v_sender.id
            ),
            v_receiver.email
        );

    v_stage := 'create receiver notification';

    v_receiver_notification :=
        public.create_notification_message(
            p_country_code,
            p_transaction_type,
            'receiver'::public."NotificationAudience",
            v_amount,
            upper(v_currency),
            v_reference || '-02',
            0,
            coalesce(
                v_sender.email,
                v_sender.id
            ),
            v_receiver.email
        );

    v_stage := 'fetch receiver device tokens';

    v_device_tokens :=
        public.fetch_device_tokens(
            p_country_code,
            v_receiver.id
        );

    v_stage := 'fetch document number prefix';

    v_document_prefix :=
        public.fetch_transaction_doc_num_prefix(
            p_transaction_type
        );

    v_stage := 'generate document number';

    v_document_number :=
        public.generate_document_number(
            v_document_prefix,
            v_fiscal_year,
            v_period,
            p_country_code
        );

    v_stage := 'insert financial transaction';

    insert into public.financial_transaction (
        document_number,
        fiscal_year,
        period,
        transaction_type,
        description,
        created_by,
        gross_amount,
        currency_code,
        reference,
        country_code
    )
    values (
        v_document_number,
        v_fiscal_year,
        v_period,
        p_transaction_type,
        'User transfer from ' ||
            coalesce(
                v_sender.email,
                v_sender.phone,
                v_sender.id
            ) ||
            ' to ' ||
            coalesce(
                v_receiver.email,
                v_receiver.phone,
                v_receiver.id
            ),
        p_sender_id,
        v_principal_amount,
        v_currency,
        v_reference,
        p_country_code
    )
    returning id
    into v_financial_transaction_id;

    v_stage := 'post financial entries';

perform *
from public.post_financial_entries(
    p_document_number =>  v_document_number,
    p_country_code =>   p_country_code,
    p_transaction_id =>  v_financial_transaction_id,
    p_transaction_type =>   p_transaction_type,
    p_created_by =>   p_sender_id,
    p_components =>    v_components,
    p_mappings =>    v_mappings,
    p_currency_code =>     v_currency,
    p_fiscal_year =>  v_fiscal_year,
    p_period =>   v_period,
    p_reference =>  v_reference,
    p_deposit_type =>  null
);

    v_stage := 'post wallet entries';

    select result.receiver_notification_id
    into v_receiver_notification_id
    from public.post_wallet_entries(
        p_fiscal_year => v_fiscal_year,
        p_period => v_period,
        p_document_number => v_document_number,
        p_reference => v_reference,
        p_receiver_id => v_receiver.id,
        p_sender_id => p_sender_id,
        p_transaction_type => p_transaction_type,
        p_credit_amount => v_amount,
        p_debit_amount => v_principal_amount,
        p_sender_wallet_owner =>
            'customer'::public."WalletOwnerType",
        p_receiver_wallet_owner =>
            'customer'::public."WalletOwnerType",
        p_currency_code => v_currency,
        p_country_code => p_country_code,
        p_audit_action_type =>
            'cash_transferred'::public."AuditActionType",
        p_treasury_id => v_treasury.id,
        p_fee_amount => v_fee,
        p_ip_address => p_ip_address,
        p_receiver_notification => v_receiver_notification,
        p_sender_notification =>  v_sender_notification
    ) as result;

    v_stage := 'update transaction state';

    update public.transaction_state
    set
        user_id =
            v_receiver.id,

        status =
            'success'::public."TransactionStatus",

        message =
            null,

        updated_at =
            now()
    where id =
        p_transaction_state_id
    and created_by =
        p_sender_id
    and status =
        'processing'::public."TransactionStatus";

    if not found then
        raise exception
            'TRANSACTION_STATE_UPDATE_FAILED';
    end if;

    v_stage := 'return cash transfer result';

    return query
    select
        true,
        v_amount::text,
        v_others_amount::text,
        v_currency,
        v_receiver_notification_id,
        v_device_tokens,
        v_receiver_notification.title,
        v_receiver_notification.body,
        v_receiver_notification.payload ->> 'reference';

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
                'CASH_TRANSFER_FAILED at [%s]: %s',
                v_stage,
                v_error_message
            ),
            detail = coalesce(
                nullif(
                    concat_ws(
                        E'\n',
                        nullif(v_error_detail, ''),
                        nullif(v_error_context, '')
                    ),
                    ''
                ),
                'No additional PostgreSQL context'
            ),
            hint = coalesce(
                nullif(v_error_hint, ''),
                'Check the cash-transfer stage reported in the error'
            );
end;
$function$
