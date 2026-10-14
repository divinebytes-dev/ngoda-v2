create or replace function public.execute_my_gold_inventory_purchase(
    p_transaction_type public."TransactionType",
    p_token_total_supply numeric,
    p_quantity_grams numeric default null,
    p_price_per_gram numeric default null,
    p_currency_code text default null,
    p_bar_serial_number text default null,
    p_supplier_name text default null,
    p_custodian_name text default null,
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
    v_treasury public.users%rowtype;

    v_original_transaction
        public.financial_transaction%rowtype;

    v_original_reserve
        public.asset_reserve%rowtype;

    v_treasury_wallet
        public.wallet%rowtype;

    v_is_reversal boolean;

    v_quantity numeric;
    v_price numeric;
    v_total_value numeric;

    v_currency_code text;
    v_bar_serial_number text;

    v_supplier_name text;
    v_custodian_name text;

    v_description text;

    v_fiscal_year integer;
    v_period integer;

    v_mappings
        public.transaction_gl_mapping[];

    v_components
        public.posting_component[];

    v_document_prefix text;
    v_new_document_number text;

    v_transaction_reference text;
    v_entry_reference text;
    v_reversal_of text;
    v_reversed_by text;

    v_financial_transaction_id bigint;

    v_asset_entry_id
        public.asset_entry.id%type;

    v_asset_reserve_id
        public.asset_reserve.id%type;

    v_wallet_debit numeric := 0;
    v_wallet_credit numeric := 0;

    v_physical_gold_balance numeric := 0;

    /*
     * Pending mint quantities are positive.
     * Pending burning quantities are negative.
     */
    v_pending_token_adjustment numeric := 0;

    v_projected_token_supply numeric := 0;
    v_token_difference numeric := 0;

    v_minimum_adjustment numeric :=
        0.000001;

    v_adjustment_type
        public."TokenAdjustmentType";

    v_adjustment_request_id
        public.tokenised_asset_adjustment_request.id%type;

    v_adjustment_created boolean :=
        false;

    v_audit_action
        public."AuditActionType";
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
     * Validate transaction type.
     */
    if p_transaction_type not in (
        'gold_inventory_purchase'::public."TransactionType",
        'gold_inventory_purchase_reversal'::public."TransactionType"
    ) then
        raise exception
            'INVALID_GOLD_INVENTORY_TRANSACTION_TYPE_%',
            p_transaction_type;
    end if;

    v_is_reversal :=
        p_transaction_type =
        'gold_inventory_purchase_reversal'::public."TransactionType";

    if p_token_total_supply is null
       or p_token_total_supply < 0
    then
        raise exception
            'INVALID_TOKEN_TOTAL_SUPPLY';
    end if;


    /*
     * Fetch trusted finance-user context.
     */
    v_user :=
        public.fetch_user_by_id(
            auth.uid()::text
        );

    if v_user.id is null then
        raise exception
            'FINANCE_USER_NOT_FOUND';
    end if;

    if v_user.country_code is null then
        raise exception
            'USER_COUNTRY_NOT_CONFIGURED';
    end if;

    /*
     * Fetch country treasury.
     */
    v_treasury :=
        public.fetch_country_treasury(
            v_user.country_code
        );

    if v_treasury.id is null then
        raise exception
            'TREASURY_NOT_FOUND';
    end if;

    /*
     * Normal Gold inventory purchase.
     */
    if not v_is_reversal then
        v_quantity :=
            public.round_down(
                p_quantity_grams
            );

        if v_quantity is null
           or v_quantity <= 0
        then
            raise exception
                'INVALID_GOLD_QUANTITY';
        end if;

        v_price :=
            p_price_per_gram;

        if v_price is null
           or v_price <= 0
        then
            raise exception
                'INVALID_GOLD_PRICE';
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

        v_bar_serial_number :=
            nullif(
                btrim(p_bar_serial_number),
                ''
            );

        if v_bar_serial_number is null then
            raise exception
                'BAR_SERIAL_NUMBER_REQUIRED';
        end if;

        /*
         * Prevent an active physical bar from being captured
         * more than once in the same country.
         */
        perform 1
        from public.asset_reserve
            asset_reserve_record
        where asset_reserve_record.country_code =
              v_user.country_code

          and asset_reserve_record.bar_serial_number =
              v_bar_serial_number

          and asset_reserve_record.is_active =
              true
        limit 1;

        if found then
            raise exception
                'GOLD_BAR_ALREADY_CAPTURED';
        end if;

        v_supplier_name :=
            nullif(
                btrim(p_supplier_name),
                ''
            );

        v_custodian_name :=
            nullif(
                btrim(p_custodian_name),
                ''
            );

        v_total_value :=
            v_quantity *
            v_price;

        v_description :=
            format(
                'Gold inventory purchase %s',
                v_bar_serial_number
            );

        v_reversal_of :=
            null;

        v_reversed_by :=
            null;

        v_audit_action :=
            'gold_purchased'::public."AuditActionType";
    end if;

    /*
     * Gold inventory purchase reversal.
     */
    if v_is_reversal then
        if nullif(
            btrim(p_document_number),
            ''
        ) is null
        then
            raise exception
                'DOCUMENT_NUMBER_REQUIRED_FOR_REVERSAL';
        end if;

        /*
         * Lock the original financial transaction.
         */
        select financial_transaction_record.*
        into v_original_transaction
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

        if v_original_transaction.transaction_type <>
           'gold_inventory_purchase'::public."TransactionType"
        then
            raise exception
                'DOCUMENT_IS_NOT_GOLD_INVENTORY_PURCHASE';
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
              v_original_transaction.document_number

          and reversal_record.transaction_type =
              'gold_inventory_purchase_reversal'::public."TransactionType"
        limit 1;

        if found then
            raise exception
                'DOCUMENT_ALREADY_REVERSED';
        end if;

        /*
         * Lock and fetch the active original reserve.
         */
        select asset_reserve_record.*
        into v_original_reserve
        from public.asset_reserve
            asset_reserve_record
        where asset_reserve_record.document_number =
              v_original_transaction.document_number

          and asset_reserve_record.country_code =
              v_user.country_code

          and asset_reserve_record.type =
              'gold'::public."AssetType"

          and asset_reserve_record.is_active =
              true
        for update;

        if not found then
            raise exception
                'ACTIVE_ASSET_DOCUMENT_NOT_FOUND';
        end if;

        v_quantity :=
            v_original_reserve.quantity;

        v_price :=
            v_original_reserve.price;

        v_total_value :=
            v_original_reserve.total_value;

        if v_quantity is null
           or v_quantity <= 0
        then
            raise exception
                'INVALID_ORIGINAL_GOLD_QUANTITY';
        end if;

        if v_price is null
           or v_price <= 0
        then
            raise exception
                'INVALID_ORIGINAL_GOLD_PRICE';
        end if;

        if v_total_value is null
           or v_total_value <= 0
        then
            raise exception
                'INVALID_ORIGINAL_TOTAL_VALUE';
        end if;

        v_currency_code :=
            lower(
                v_original_reserve.currency_code
            );

        v_bar_serial_number :=
            v_original_reserve.bar_serial_number;

        v_supplier_name :=
            v_original_reserve.supplier_name;

        v_custodian_name :=
            v_original_reserve.custodian_name;

        v_description :=
            format(
                'Gold inventory purchase reversal %s',
                v_bar_serial_number
            );

        v_reversal_of :=
            v_original_transaction.document_number;

        v_reversed_by :=
            v_user.id;

        v_asset_reserve_id :=
            v_original_reserve.id;

        v_audit_action :=
            'gold_purchase_reversed'::public."AuditActionType";

        /*
         * Cancel a pending token adjustment created by the
         * original purchase.
         *
         * Completed requests remain intact. Reconciliation
         * later creates a burn request when required.
         */
        update public.tokenised_asset_adjustment_request
        set
            status =
                'cancelled'::public."AdjustmentStatus"
        where reference =
              v_original_reserve.asset_entry_id

          and status =
              'pending'::public."AdjustmentStatus";
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
     * Build posting components.
     */
    v_components :=
        public.build_posting_components(
            p_transaction_type,
            v_total_value,
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
     * Fetch configured document prefix.
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

    /*
     * Generate document number.
     */
    v_new_document_number :=
        public.generate_document_number(
            v_document_prefix,
            v_fiscal_year,
            v_period,
            v_user.country_code
        );

    /*
     * The financial-transaction reference is unique.
     * Therefore the reversal receives its own reference.
     *
     * Financial entries and wallet entries reference the
     * original document when this is a reversal.
     */
    v_transaction_reference :=
        v_new_document_number;

    v_entry_reference :=
        coalesce(
            v_reversal_of,
            v_new_document_number
        );

    /*
     * Create financial transaction.
     */
    insert into public.financial_transaction (
        document_number,
        reference,
        fiscal_year,
        period,
        transaction_type,
        description,
        currency_code,
        created_by,
        gross_amount,
        country_code,
        reversal_of,
        reversed_by
    )
    values (
        v_new_document_number,
        v_transaction_reference,
        v_fiscal_year,
        v_period,
        p_transaction_type,
        v_description,
        v_currency_code,
        v_user.id,
        v_total_value,
        v_user.country_code,
        v_reversal_of,
        v_reversed_by
    )
    returning id
    into v_financial_transaction_id;

    /*
     * Post financial entries.
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
     * Record the physical Gold movement.
     *
     * Purchase:
     *     credit = quantity
     *
     * Reversal:
     *     debit = quantity
     *
     * Both amounts remain positive.
     */
    insert into public.asset_entry (
        document_number,
        fiscal_year,
        period,
        debit,
        credit,
        total_value,
        price,
        currency_code,
        created_by,
        country_code
    )
    values (
        v_new_document_number,
        v_fiscal_year,
        v_period,

        case
            when v_is_reversal
                then v_quantity
            else 0
        end,

        case
            when v_is_reversal
                then 0
            else v_quantity
        end,

        v_total_value,
        v_price,
        v_currency_code,
        v_user.id,
        v_user.country_code
    )
    returning id
    into v_asset_entry_id;

    /*
     * A purchase creates a new active physical reserve.
     *
     * A reversal deactivates the original reserve. It does
     * not insert a reserve containing negative amounts.
     */
    if not v_is_reversal then
        insert into public.asset_reserve (
            document_number,
            asset_entry_id,
            fiscal_year,
            period,
            bar_serial_number,
            type,
            quantity,
            uom,
            price,
            total_value,
            currency_code,
            supplier_name,
            custodian_name,
            acquisition_date,
            country_code,
            is_active
        )
        values (
            v_new_document_number,
            v_asset_entry_id,
            v_fiscal_year,
            v_period,
            v_bar_serial_number,
            'gold'::public."AssetType",
            v_quantity,
            'gram'::public."Uom",
            v_price,
            v_total_value,
            v_currency_code,
            v_supplier_name,
            v_custodian_name,
            now(),
            v_user.country_code,
            true
        )
        returning id
        into v_asset_reserve_id;
    else
        update public.asset_reserve
        set
            is_active = false
        where id =
              v_original_reserve.id

          and country_code =
              v_user.country_code

          and is_active =
              true;

        if not found then
            raise exception
                'ACTIVE_ASSET_DOCUMENT_NOT_FOUND';
        end if;

        v_asset_reserve_id :=
            v_original_reserve.id;
    end if;

    /*
     * Lock treasury fiat wallet.
     */
    select wallet_record.*
    into v_treasury_wallet
    from public.wallet
        wallet_record
    where wallet_record.country_code =
          v_user.country_code

      and wallet_record.user_id =
          v_treasury.id

      and lower(
          wallet_record.currency_code
      ) =
          v_currency_code

      and wallet_record.owner_type =
          'treasury'::public."WalletOwnerType"
    for update;

    if not found then
        raise exception
            'TREASURY_WALLET_NOT_FOUND';
    end if;

    if not v_treasury_wallet.is_active then
        raise exception
            'TREASURY_WALLET_FROZEN';
    end if;

    /*
     * Purchase pays for the physical Gold from treasury.
     * Reversal restores the amount to treasury.
     */
    if not v_is_reversal then
        update public.wallet
        set
            balance =
                balance -
                v_total_value
        where id =
              v_treasury_wallet.id

          and is_active =
              true

          and balance >=
              v_total_value;

        if not found then
            raise exception
                'INSUFFICIENT_TREASURY_BALANCE';
        end if;

        v_wallet_debit :=
            v_total_value;

        v_wallet_credit :=
            0;
    else
        update public.wallet
        set
            balance =
                balance +
                v_total_value
        where id =
              v_treasury_wallet.id

          and is_active =
              true;

        if not found then
            raise exception
                'TREASURY_WALLET_UPDATE_FAILED';
        end if;

        v_wallet_debit :=
            0;

        v_wallet_credit :=
            v_total_value;
    end if;

    /*
     * Create treasury wallet entry.
     */
    insert into public.wallet_entry (
        document_number,
        reference,
        fiscal_year,
        period,
        transaction_type,
        wallet_id,
        currency_code,
        country_code,
        debit,
        credit,
        created_by
    )
    values (
        v_new_document_number,
        v_entry_reference,
        v_fiscal_year,
        v_period,
        p_transaction_type,
        v_treasury_wallet.id,
        v_currency_code,
        v_user.country_code,
        v_wallet_debit,
        v_wallet_credit,
        v_user.id
    );

    /*
     * Update treasury wallet snapshot.
     */
    perform public.update_wallet_balance_snapshot(
        p_transaction_type,
        v_treasury.id,
        v_treasury.id,
        null,
        v_currency_code,
        'treasury'::public."WalletOwnerType",
        'treasury'::public."WalletOwnerType",
        v_wallet_debit,
        v_wallet_credit,
        v_fiscal_year,
        v_period,
        v_user.country_code,
        0
    );

    /*
     * Calculate the physical Gold balance from append-only
     * asset entries.
     */
    select coalesce(
        sum(
            coalesce(
                asset_entry_record.credit,
                0
            ) -
            coalesce(
                asset_entry_record.debit,
                0
            )
        ),
        0
    )
    into v_physical_gold_balance
    from public.asset_entry
        asset_entry_record;

    /*
     * Include pending mint and burn requests in projected
     * token supply to prevent duplicate requests.
     */
    select coalesce(
        sum(
            case
                when adjustment_record.adjustment_type =
                     'minting'::public."TokenAdjustmentType"
                then
                    adjustment_record.quantity

                when adjustment_record.adjustment_type =
                     'burning'::public."TokenAdjustmentType"
                then
                    -adjustment_record.quantity

                else
                    0
            end
        ),
        0
    )
    into v_pending_token_adjustment
    from public.tokenised_asset_adjustment_request
        adjustment_record
    where adjustment_record.status =
          'pending'::public."AdjustmentStatus";

    v_projected_token_supply :=
        p_token_total_supply +
        v_pending_token_adjustment;

    v_token_difference :=
        public.round_down(
            v_physical_gold_balance -
            v_projected_token_supply
        );

    /*
     * Positive difference requires minting.
     * Negative difference requires burning.
     */
    if abs(
        v_token_difference
    ) >= v_minimum_adjustment
    then
        v_adjustment_type :=
            case
                when v_token_difference > 0
                then
                    'minting'::public."TokenAdjustmentType"

                else
                    'burning'::public."TokenAdjustmentType"
            end;

        insert into public.tokenised_asset_adjustment_request (
            document_number,
            fiscal_year,
            period,
            reference,
            adjustment_type,
            quantity,
            uom,
            total_value,
            currency_code,
            status,
            description,
            created_by
        )
        values (
            v_new_document_number,
            v_fiscal_year,
            v_period,
            v_asset_entry_id,
            v_adjustment_type,
            abs(
                v_token_difference
            ),
            'gram'::public."Uom",
            abs(
                v_token_difference
            ) *
            v_price,
            v_currency_code,
            'pending'::public."AdjustmentStatus",

            case
                when v_adjustment_type =
                     'minting'::public."TokenAdjustmentType"
                then
                    'Physical Gold reserve requires token minting'
                else
                    'Physical Gold reserve requires token burning'
            end,

            v_user.id
        )
        returning id
        into v_adjustment_request_id;

        v_adjustment_created :=
            true;
    end if;

    /*
     * Audit the inventory purchase or reversal.
     */
    insert into public.audit_log (
        user_id,
        country_code,
        fiscal_year,
        period,
        action_type,
        entity_type,
        entity_id,
        document_number,
        metadata,
        ip_address
    )
    values (
        v_user.id,
        v_user.country_code,
        v_fiscal_year,
        v_period,
        v_audit_action,
        'gold_purchase',
        v_asset_reserve_id::text,
        v_new_document_number,

        jsonb_build_object(
            'transaction_type',
            p_transaction_type,

            'supplier',
            v_supplier_name,

            'quantity',
            v_quantity::text,

            'price_per_gram',
            v_price::text,

            'total_value',
            v_total_value::text,

            'currency',
            v_currency_code,

            'bar_serial_number',
            v_bar_serial_number,

            'reversal_of',
            v_reversal_of,

            'physical_gold_balance',
            v_physical_gold_balance::text,

            'onchain_token_supply',
            p_token_total_supply::text,

            'pending_token_adjustment',
            v_pending_token_adjustment::text,

            'token_difference',
            v_token_difference::text,

            'adjustment_request_id',
            v_adjustment_request_id
        ),

        p_ip_address
    );

    return jsonb_build_object(
        'success',
        true,

        'document_number',
        v_new_document_number,

        'transaction_type',
        p_transaction_type,

        'quantity_grams',
        v_quantity::text,

        'price_per_gram',
        v_price::text,

        'total_value',
        v_total_value::text,

        'currency',
        v_currency_code,

        'reversal_of',
        v_reversal_of,

        'physical_gold_balance',
        v_physical_gold_balance::text,

        'token_total_supply',
        p_token_total_supply::text,

        'projected_token_supply',
        v_projected_token_supply::text,

        'token_difference',
        v_token_difference::text,

        'adjustment_created',
        v_adjustment_created,

        'adjustment_request_id',
        v_adjustment_request_id,

        'adjustment_type',
        v_adjustment_type,

        'mint_status',
        case
            when v_adjustment_created
                then 'pending'
            else 'not_required'
        end
    );
end;
$function$;


revoke all on function
    public.execute_my_gold_inventory_purchase(
        public."TransactionType",
        numeric,
        numeric,
        numeric,
        text,
        text,
        text,
        text,
        text,
        text
    )
from public;

revoke all on function
    public.execute_my_gold_inventory_purchase(
        public."TransactionType",
        numeric,
        numeric,
        numeric,
        text,
        text,
        text,
        text,
        text,
        text
    )
from anon;

grant execute on function
    public.execute_my_gold_inventory_purchase(
        public."TransactionType",
        numeric,
        numeric,
        numeric,
        text,
        text,
        text,
        text,
        text,
        text
    )
to authenticated;

notify pgrst, 'reload schema';