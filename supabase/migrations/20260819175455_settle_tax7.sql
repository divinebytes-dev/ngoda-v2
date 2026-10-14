CREATE OR REPLACE FUNCTION public.update_my_government_tax_settlement_batch(
    p_batch_id text,
    p_action text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
declare
    v_user public.users%rowtype;

    v_batch
        public.government_tax_settlement_batch%rowtype;

    v_batch_id text;
    v_action text;

    v_fiscal_year integer;
    v_period integer;

    v_total_items integer := 0;
    v_updated_items integer := 0;
    v_released_payables integer := 0;

    v_stage text :=
        'initialization';

    v_error_state text;
    v_error_message text;
    v_error_detail text;
    v_error_hint text;
    v_error_context text;
begin
    /*
     * Authentication and Finance authorization.
     */
    v_stage :=
        'authorize finance user';

    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHORIZED';
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
     * Validate input.
     */
    v_stage :=
        'validate input';

    v_batch_id :=
        nullif(
            btrim(p_batch_id),
            ''
        );

    if v_batch_id is null then
        raise exception
            'SETTLEMENT_BATCH_ID_REQUIRED';
    end if;

    v_action :=
        lower(
            nullif(
                btrim(p_action),
                ''
            )
        );

    if v_action is null then
        raise exception
            'SETTLEMENT_ACTION_REQUIRED';
    end if;

    if v_action not in (
        'approve',
        'cancel'
    ) then
        raise exception
            'INVALID_SETTLEMENT_ACTION';
    end if;

    /*
     * Fetch trusted Finance user.
     */
    v_stage :=
        'fetch finance user';

    v_user :=
        public.fetch_user_by_id(
            auth.uid()::text
        );

    if v_user.id is null then
        raise exception
            'FINANCE_USER_NOT_FOUND';
    end if;

    if v_user.status <>
       'active'::public."UserStatus"
    then
        raise exception
            'FINANCE_USER_NOT_ACTIVE';
    end if;

    if nullif(
        btrim(
            v_user.country_code
        ),
        ''
    ) is null
    then
        raise exception
            'USER_COUNTRY_NOT_CONFIGURED';
    end if;

    /*
     * Lock the tax batch and enforce country isolation.
     */
    v_stage :=
        'lock tax settlement batch';

    select batch_record.*
    into v_batch
    from public.government_tax_settlement_batch
        batch_record
    where batch_record.id::text =
              v_batch_id

      and lower(
          btrim(
              batch_record.country_code
          )
      ) =
          lower(
              btrim(
                  v_user.country_code
              )
          )
    for update;

    if not found then
        raise exception
            'GOVERNMENT_TAX_SETTLEMENT_BATCH_NOT_FOUND';
    end if;

    /*
     * Lock all items before changing their statuses.
     */
    v_stage :=
        'lock tax settlement items';

    perform 1
    from public.government_tax_settlement_item
        item_record
    where item_record.batch_id =
          v_batch.id
    for update;

    /*
     * Validate that the batch has items.
     */
    select count(*)::integer
    into v_total_items
    from public.government_tax_settlement_item
        item_record
    where item_record.batch_id =
          v_batch.id;

    if v_total_items = 0 then
        raise exception
            'GOVERNMENT_TAX_SETTLEMENT_ITEMS_NOT_FOUND';
    end if;

    /*
     * Current fiscal period for the approval audit.
     */
    v_stage :=
        'fetch fiscal period';

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
     * Approve the batch and its items.
     */
    if v_action = 'approve' then
        v_stage :=
            'validate tax settlement approval';

        if v_batch.status::text not in (
            'draft',
            'pending'
        ) then
            raise exception
                'ONLY_DRAFT_OR_PENDING_TAX_BATCHES_CAN_BE_APPROVED';
        end if;

        /*
         * Four-eyes control.
         *
         * The Accounts user who created the batch cannot
         * approve the same batch.
         */
        if v_batch.created_by =
           v_user.id
        then
            raise exception
                'CREATOR_AND_APPROVER_MUST_BE_DIFFERENT';
        end if;

        /*
         * Every item must still be awaiting approval.
         */
        perform 1
        from public.government_tax_settlement_item
            item_record
        where item_record.batch_id =
                  v_batch.id

          and item_record.status::text not in (
              'draft',
              'pending'
          )
        limit 1;

        if found then
            raise exception
                'INVALID_GOVERNMENT_TAX_ITEM_STATUS_FOR_APPROVAL';
        end if;

        /*
         * Approve every tax settlement item.
         */
        v_stage :=
            'approve tax settlement items';

        update public.government_tax_settlement_item
        set
            status =
                'approved'
        where batch_id =
              v_batch.id

          and status::text in (
              'draft',
              'pending'
          );

        get diagnostics
            v_updated_items =
                row_count;

        if v_updated_items <>
           v_total_items
        then
            raise exception
                'GOVERNMENT_TAX_ITEM_APPROVAL_COUNT_MISMATCH_EXPECTED_%_UPDATED_%',
                v_total_items,
                v_updated_items;
        end if;

        /*
         * Approve the batch header.
         */
        v_stage :=
            'approve tax settlement batch';

        update public.government_tax_settlement_batch
        set
            status =
                'approved',

            approved_by =
                v_user.id,

            approved_at =
                now(),

            error_message =
                null
        where id =
              v_batch.id
        returning *
        into v_batch;

        if not found then
            raise exception
                'GOVERNMENT_TAX_BATCH_APPROVAL_FAILED';
        end if;

        /*
         * Audit the approval.
         */
        v_stage :=
            'create tax approval audit';

        insert into public.audit_log (
            user_id,
            country_code,
            fiscal_year,
            period,
            action_type,
            entity_type,
            entity_id,
            document_number
        )
        values (
            v_user.id,
            v_user.country_code,
            v_fiscal_year,
            v_period,
            'tax_settlement_approved'::public."AuditActionType",
            'tax_settlement_batch',
            v_batch.id::text,
            v_batch.document_number
        );
    end if;

    /*
     * Cancel the tax settlement batch.
     */
    if v_action = 'cancel' then
        v_stage :=
            'validate tax settlement cancellation';

        if v_batch.status::text not in (
            'draft',
            'pending',
            'approved',
            'failed'
        ) then
            raise exception
                'INVALID_GOVERNMENT_TAX_BATCH_STATUS_FOR_CANCELLATION_%',
                upper(
                    v_batch.status::text
                );
        end if;

        /*
         * paid_at indicates that payment processing has
         * already started.
         */
        if v_batch.paid_at is not null then
            raise exception
                'GOVERNMENT_TAX_BATCH_PAYMENT_ALREADY_STARTED';
        end if;

        /*
         * No item may have entered payment processing.
         */
        perform 1
        from public.government_tax_settlement_item
            item_record
        where item_record.batch_id =
                  v_batch.id

          and item_record.status::text in (
              'processing',
              'partial',
              'settled'
          )
        limit 1;

        if found then
            raise exception
                'GOVERNMENT_TAX_SETTLEMENT_ITEM_PAYMENT_ALREADY_STARTED';
        end if;

        /*
         * No payable row assigned to the batch may
         * already have been settled.
         */
        perform 1
        from public.government_tax_payable
            payable_record
        where payable_record.settlement_batch_id =
                  v_batch.id

          and payable_record.is_settled =
                  true
        limit 1;

        if found then
            raise exception
                'SETTLED_GOVERNMENT_TAX_PAYABLE_CANNOT_BE_CANCELLED';
        end if;

        /*
         * Mark every item cancelled.
         *
         * Items remain attached to the batch for audit
         * and reporting history.
         */
        v_stage :=
            'cancel tax settlement items';

        update public.government_tax_settlement_item
        set
            status =
                'cancelled'
        where batch_id =
              v_batch.id;

        get diagnostics
            v_updated_items =
                row_count;

        if v_updated_items <>
           v_total_items
        then
            raise exception
                'GOVERNMENT_TAX_ITEM_CANCELLATION_COUNT_MISMATCH_EXPECTED_%_UPDATED_%',
                v_total_items,
                v_updated_items;
        end if;

        /*
         * Release unsettled payable rows so Accounts can
         * include them in a corrected batch.
         */
        v_stage :=
            'release government tax payables';

        update public.government_tax_payable
        set
            settlement_batch_id =
                null
        where settlement_batch_id =
                  v_batch.id

          and is_settled =
                  false;

        get diagnostics
            v_released_payables =
                row_count;

        /*
         * Cancel the batch header.
         */
        v_stage :=
            'cancel tax settlement batch';

        update public.government_tax_settlement_batch
        set
            status =
                'cancelled',

            error_message =
                null
        where id =
              v_batch.id
        returning *
        into v_batch;

        if not found then
            raise exception
                'GOVERNMENT_TAX_BATCH_CANCELLATION_FAILED';
        end if;
    end if;

    return jsonb_build_object(
        'success',
        true,

        'batch_id',
        v_batch.id,

        'document_number',
        v_batch.document_number,

        'currency_code',
        v_batch.currency_code,

        'action',
        v_action,

        'status',
        v_batch.status,

        'approved_by',
        v_batch.approved_by,

        'approved_at',
        v_batch.approved_at,

        'total_items',
        v_total_items,

        'updated_items',
        v_updated_items,

        'released_payables',
        v_released_payables
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
                    'GOVERNMENT_TAX_SETTLEMENT_UPDATE_FAILED at [%s]: %s',
                    v_stage,
                    v_error_message
                ),

            detail =
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

            hint =
                coalesce(
                    nullif(
                        v_error_hint,
                        ''
                    ),
                    'Check the Government Tax Settlement update stage'
                );
end;
$function$;

REVOKE ALL ON FUNCTION
    public.update_my_government_tax_settlement_batch(
        text,
        text
    )
FROM PUBLIC;

REVOKE ALL ON FUNCTION
    public.update_my_government_tax_settlement_batch(
        text,
        text
    )
FROM anon;

GRANT EXECUTE ON FUNCTION
    public.update_my_government_tax_settlement_batch(
        text,
        text
    )
TO authenticated;

NOTIFY pgrst, 'reload schema';