/*
 * ============================================================
 * MERCHANT PAYMENT PREPARATION
 * ============================================================
 */


/*
 * ============================================================
 * 1. REUSABLE MERCHANT COMMISSION RATE
 * ============================================================
 */

create or replace function public.fetch_merchant_commission_rate(
    p_transaction_type public."TransactionType",
    p_currency_code text,
    p_country_code text
)
returns numeric
language sql
stable
security definer
set search_path to ''
as $function$
    select coalesce(
        (
            select
                commission_config.merchant_rate::numeric

            from public.merchant_fee_splitting_config
                commission_config

            where commission_config.transaction_type =
                  p_transaction_type

              and lower(
                  btrim(
                      commission_config.currency_code
                  )
              ) = lower(
                  btrim(
                      p_currency_code
                  )
              )

              and lower(
                  btrim(
                      commission_config.country_code
                  )
              ) = lower(
                  btrim(
                      p_country_code
                  )
              )

              and commission_config.is_active =
                  true

            limit 1
        ),
        0
    );
$function$;


/*
 * ============================================================
 * 2. TRUSTED MERCHANT PAYMENT PREPARATION
 * ============================================================
 */

create or replace function public.prepare_merchant_payment(
    p_payer_id text,
    p_transaction jsonb,
    p_approval jsonb,
    p_country_code text,
    p_transaction_state_id text
)
returns table (
    payer_id text,
    payer_wallet_address text,

    merchant_id text,
    merchant_wallet_address text,

    treasury_id text,

    country_code text,
    fiscal_year integer,
    period integer,
    document_prefix text,

    currency_code text,

    amount text,
    payer_debit_amount text,
    merchant_credit_amount text,
    other_amount text,

    payment_fee text,
    commission_rate text,
    commission_amount text,

    mappings
        public.transaction_gl_mapping[],

    components
        public.posting_component[]
)
language plpgsql
security definer
set search_path to ''
as $function$
declare
    v_state
        public.transaction_state%rowtype;

    v_payer
        public.users%rowtype;

    v_merchant
        public.users%rowtype;

    v_treasury
        public.users%rowtype;

    v_reference text;
    v_merchant_id text;
    v_currency_code text;

    v_amount numeric;

    v_payer_debit_amount numeric := 0;
    v_merchant_credit_amount numeric := 0;
    v_other_amount numeric := 0;

    v_payment_fee numeric := 0;
    v_commission_rate numeric := 0;
    v_commission_amount numeric := 0;

    v_fiscal_year integer;
    v_period integer;
    v_document_prefix text;

    v_mappings
        public.transaction_gl_mapping[];

    v_components
        public.posting_component[];

    v_component_totals
        public.component_totals;
begin
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
            'TRANSACTION_DATA_MISSING';
    end if;

    if p_approval is null then
        raise exception
            'SENDER_APPROVAL_MISSING';
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
          p_payer_id
      and state_record.transaction_type =
          'merchant_payment'::public."TransactionType"
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

    if v_state.sender_approval
       is distinct from p_approval
    then
        raise exception
            'SENDER_APPROVAL_MISMATCH';
    end if;

    if p_transaction ->> 'v'
       is distinct from 'v4'
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

    v_merchant_id :=
        nullif(
            btrim(
                p_transaction ->> 's'
            ),
            ''
        );

    if v_merchant_id is null then
        raise exception
            'MERCHANT_ID_IS_REQUIRED';
    end if;

    if v_state.user_id is distinct from
       v_merchant_id
    then
        raise exception
            'TRANSACTION_MERCHANT_MISMATCH';
    end if;

    v_currency_code :=
        lower(
            nullif(
                btrim(
                    p_transaction ->> 'c'
                ),
                ''
            )
        );

    if v_currency_code is null then
        raise exception
            'CURRENCY_IS_REQUIRED';
    end if;

    /*
     * Validate transaction and approval consistency.
     */
    if p_transaction ->> 'a'
       is distinct from
       p_approval ->> 'a'
    then
        raise exception
            'AMOUNT_MISMATCH';
    end if;

    if lower(
        p_transaction ->> 'c'
    ) is distinct from lower(
        p_approval ->> 'c'
    ) then
        raise exception
            'CURRENCY_MISMATCH';
    end if;

    if p_transaction ->> 'r'
       is distinct from
       p_approval ->> 'r'
    then
        raise exception
            'REFERENCE_MISMATCH';
    end if;

    /*
     * Parse the signed amount.
     */
    begin
        v_amount :=
            (
                p_transaction ->> 'a'
            )::numeric / 100;
    exception
        when invalid_text_representation then
            raise exception
                'INVALID_AMOUNT';
    end;

    if v_amount <= 0 then
        raise exception
            'INVALID_AMOUNT';
    end if;

    /*
     * Fetch trusted users.
     */
    v_payer :=
        public.fetch_user_by_id(
            p_payer_id
        );

    v_merchant :=
        public.fetch_user_by_id(
            v_merchant_id
        );

    v_treasury :=
        public.fetch_country_treasury(
            p_country_code
        );

    if v_payer.id is null then
        raise exception
            'PAYER_NOT_FOUND';
    end if;

    if v_merchant.id is null then
        raise exception
            'MERCHANT_NOT_FOUND';
    end if;

    if v_treasury.id is null then
        raise exception
            'TREASURY_NOT_FOUND';
    end if;

    if v_payer.status <>
       'active'::public."UserStatus"
    then
        raise exception
            'PAYER_NOT_ACTIVE';
    end if;

    if v_merchant.status <>
       'active'::public."UserStatus"
    then
        raise exception
            'MERCHANT_NOT_ACTIVE';
    end if;

    if v_payer.id =
       v_merchant.id
    then
        raise exception
            'OPERATION_NOT_ALLOWED';
    end if;

    if v_payer.country_code is distinct from
       v_merchant.country_code
    then
        raise exception
            'OPERATION_NOT_ALLOWED';
    end if;

    if lower(
        btrim(
            v_payer.country_code
        )
    ) is distinct from lower(
        btrim(
            p_country_code
        )
    ) then
        raise exception
            'PAYER_COUNTRY_MISMATCH';
    end if;

    /*
     * The receiver must have the merchant role.
     */
    if not exists (
        select 1
        from public.user_role role_record
        where role_record.id =
              v_merchant.role_id
          and lower(
              role_record.name::text
          ) = 'merchant'
    ) then
        raise exception
            'INVALID_MERCHANT_ROLE';
    end if;

    if v_payer.wallet_address is null
       or btrim(
           v_payer.wallet_address
       ) = ''
    then
        raise exception
            'PAYER_WALLET_NOT_CONFIGURED';
    end if;

    if v_merchant.wallet_address is null
       or btrim(
           v_merchant.wallet_address
       ) = ''
    then
        raise exception
            'MERCHANT_WALLET_NOT_CONFIGURED';
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
        p_country_code
    ) as fiscal_period;

    if not found then
        raise exception
            'FISCAL_PERIOD_NOT_FOUND';
    end if;

    /*
     * Fetch Merchant Payment GL mappings.
     */
    select array_agg(
        mapping_record
        order by
            mapping_record.component_type
    )
    into v_mappings
    from public.fetch_gl_mappings(
        'merchant_payment'::public."TransactionType"
    ) as mapping_record;

    if v_mappings is null
       or cardinality(
           v_mappings
       ) = 0
    then
        raise exception
            'MERCHANT_PAYMENT_GL_MAPPINGS_NOT_FOUND';
    end if;

    /*
     * Build and validate trusted posting components.
     */
    v_components :=
        public.build_posting_components(
            'merchant_payment'::public."TransactionType",
            v_amount,
            v_mappings,
            p_country_code,
            v_currency_code,
            false
        );

    if v_components is null
       or cardinality(
           v_components
       ) = 0
    then
        raise exception
            'MERCHANT_PAYMENT_COMPONENTS_NOT_FOUND';
    end if;

    v_components :=
        public.validate_components(
            v_components
        );

    /*
     * Extract payer debit and other component totals.
     */
    v_component_totals :=
        public.extract_component_totals(
            v_components,
            false
        );

    v_payer_debit_amount :=
        coalesce(
            v_component_totals.principal_amount,
            0
        );

    v_other_amount :=
        coalesce(
            v_component_totals.others_amount,
            0
        );

    if v_payer_debit_amount <= 0 then
        raise exception
            'INVALID_PAYER_DEBIT_AMOUNT';
    end if;

    /*
     * Merchant receives the original purchase amount.
     */
    v_merchant_credit_amount :=
        v_amount;

    /*
     * Extract the configured payment fee.
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
    into v_payment_fee
    from unnest(
        v_components
    ) as component_record(
        component_type,
        debit_amount,
        credit_amount
    )
    where component_record.component_type =
          'payment_fee'::public."ComponentType"
    limit 1;

    v_payment_fee :=
        coalesce(
            v_payment_fee,
            0
        );

    if v_payment_fee < 0 then
        raise exception
            'INVALID_PAYMENT_FEE';
    end if;

    /*
     * Fetch the merchant commission percentage.
     */
    v_commission_rate :=
        public.fetch_merchant_commission_rate(
            'merchant_payment'::public."TransactionType",
            v_currency_code,
            p_country_code
        );

    v_commission_rate :=
        coalesce(
            v_commission_rate,
            0
        );

    if v_commission_rate < 0
       or v_commission_rate > 100
    then
        raise exception
            'INVALID_MERCHANT_COMMISSION_RATE';
    end if;

    /*
     * Commission:
     *
     * payment fee × merchant rate / 100
     */
    v_commission_amount :=
        trunc(
            (
                v_payment_fee *
                v_commission_rate
            ) / 100,
            6
        );

    /*
     * Fetch configured document prefix.
     *
     * No hard-coded "MERCHANT-PAYMENT" value is used.
     */
    v_document_prefix :=
        public.fetch_transaction_doc_num_prefix(
            'merchant_payment'::public."TransactionType"
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
        v_payer.id,
        v_payer.wallet_address,

        v_merchant.id,
        v_merchant.wallet_address,

        v_treasury.id,

        lower(
            btrim(
                p_country_code
            )
        ),

        v_fiscal_year,
        v_period,
        v_document_prefix,

        v_currency_code,

        v_amount::text,
        v_payer_debit_amount::text,
        v_merchant_credit_amount::text,
        v_other_amount::text,

        v_payment_fee::text,
        v_commission_rate::text,
        v_commission_amount::text,

        v_mappings,
        v_components;
end;
$function$;


/*
 * ============================================================
 * OWNERSHIP AND PERMISSIONS
 * ============================================================
 */

alter function public.fetch_merchant_commission_rate(
    public."TransactionType",
    text,
    text
)
owner to postgres;

alter function public.prepare_merchant_payment(
    text,
    jsonb,
    jsonb,
    text,
    text
)
owner to postgres;


revoke all
on function public.fetch_merchant_commission_rate(
    public."TransactionType",
    text,
    text
)
from public, anon, authenticated, service_role;

revoke all
on function public.prepare_merchant_payment(
    text,
    jsonb,
    jsonb,
    text,
    text
)
from public, anon, authenticated, service_role;


grant execute
on function public.fetch_merchant_commission_rate(
    public."TransactionType",
    text,
    text
)
to service_role;

grant execute
on function public.prepare_merchant_payment(
    text,
    jsonb,
    jsonb,
    text,
    text
)
to service_role;