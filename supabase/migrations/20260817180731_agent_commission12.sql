DROP INDEX IF EXISTS
    public.agent_settlement_one_active_batch_per_currency;

CREATE UNIQUE INDEX
    agent_settlement_one_active_batch_per_currency
ON public.agent_settlement_batch (
    lower(
        btrim(country_code)
    ),
    lower(
        btrim(currency_code)
    )
)
WHERE status NOT IN (
    'settled'::public."SettlementStatus",
    'cancelled'::public."SettlementStatus"
);


CREATE OR REPLACE FUNCTION public.update_my_agent_commission_settlement_batch(
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
        public.agent_settlement_batch%rowtype;

    v_batch_id text;
    v_action text;

    v_released_commissions integer := 0;

    v_stage text :=
        'initialization';

    v_error_state text;
    v_error_message text;
    v_error_detail text;
    v_error_hint text;
    v_error_context text;
begin
    /*
     * Authentication and authorization.
     *
     * Finance reviews and either approves or cancels the
     * batch created by Accounts.
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
            btrim(
                p_batch_id
            ),
            ''
        );

    if v_batch_id is null then
        raise exception
            'SETTLEMENT_BATCH_ID_REQUIRED';
    end if;

    v_action :=
        lower(
            nullif(
                btrim(
                    p_action
                ),
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
     * Fetch trusted Finance user context.
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
     * Lock the batch and enforce country isolation.
     */
    v_stage :=
        'lock settlement batch';

    select batch_record.*
    into v_batch
    from public.agent_settlement_batch
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
            'AGENT_COMMISSION_SETTLEMENT_BATCH_NOT_FOUND';
    end if;

    /*
     * Approve the batch.
     */
    if v_action = 'approve' then
        v_stage :=
            'approve settlement batch';

        if v_batch.status::text not in (
            'draft',
            'pending'
        ) then
            raise exception
                'INVALID_AGENT_COMMISSION_BATCH_STATUS_FOR_APPROVAL_%',
                upper(
                    v_batch.status::text
                );
        end if;

        update public.agent_settlement_batch
        set
            status =
                'approved'::public."SettlementStatus",

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
                'AGENT_COMMISSION_BATCH_APPROVAL_FAILED';
        end if;
    end if;

    /*
     * Cancel the batch.
     *
     * Processing, partial and settled batches cannot be
     * cancelled because payment may already have moved.
     */
    if v_action = 'cancel' then
        v_stage :=
            'validate batch cancellation';

        if v_batch.status::text not in (
            'draft',
            'pending',
            'approved',
            'failed'
        ) then
            raise exception
                'INVALID_AGENT_COMMISSION_BATCH_STATUS_FOR_CANCELLATION_%',
                upper(
                    v_batch.status::text
                );
        end if;

        if v_batch.paid_at is not null then
            raise exception
                'AGENT_COMMISSION_BATCH_PAYMENT_ALREADY_STARTED';
        end if;

        /*
         * No commission belonging to this batch may
         * already have been paid.
         */
        perform 1
        from public.agent_commission
            commission_record
        where commission_record.settlement_batch_id =
                  v_batch.id

          and commission_record.is_settled =
                  true
        limit 1;

        if found then
            raise exception
                'SETTLED_AGENT_COMMISSION_CANNOT_BE_CANCELLED';
        end if;

        /*
         * Release the commission entries so Accounts can
         * include them in a corrected date range.
         */
        v_stage :=
            'release commission entries';

        update public.agent_commission
        set
            settlement_batch_id =
                null
        where settlement_batch_id =
                  v_batch.id

          and is_settled =
                  false;

        get diagnostics
            v_released_commissions =
                row_count;

        /*
         * Keep settlement items for audit history. They
         * remain attached to the cancelled batch.
         */
        v_stage :=
            'cancel settlement batch';

        update public.agent_settlement_batch
        set
            status =
                'cancelled'::public."SettlementStatus",

            error_message =
                null
        where id =
              v_batch.id
        returning *
        into v_batch;

        if not found then
            raise exception
                'AGENT_COMMISSION_BATCH_CANCELLATION_FAILED';
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

        'released_commissions',
        v_released_commissions
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
                    'AGENT_COMMISSION_SETTLEMENT_UPDATE_FAILED at [%s]: %s',
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
                    'Check the Agent Commission Settlement update stage'
                );
end;
$function$;


REVOKE ALL ON FUNCTION
    public.update_my_agent_commission_settlement_batch(
        text,
        text
    )
FROM PUBLIC;

REVOKE ALL ON FUNCTION
    public.update_my_agent_commission_settlement_batch(
        text,
        text
    )
FROM anon;

GRANT EXECUTE ON FUNCTION
    public.update_my_agent_commission_settlement_batch(
        text,
        text
    )
TO authenticated;