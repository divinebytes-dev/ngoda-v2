DROP FUNCTION IF EXISTS
    public.fetch_my_agent_commission_settlement_batches(
        public."SettlementStatus"
    );

DROP FUNCTION IF EXISTS
    public.fetch_my_agent_commission_settlement_batches(
        text
    );


CREATE OR REPLACE FUNCTION public.fetch_my_agent_commission_settlement_batches(
    p_statuses public."SettlementStatus"[]
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
declare
    v_user public.users%rowtype;

    v_result jsonb :=
        '[]'::jsonb;
begin
    /*
     * Authentication.
     */
    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHORIZED';
    end if;

    /*
     * Accounts processes settlement batches.
     * Finance reviews and approves/cancels them.
     */
    if not public.has_role(
        array[
            'accounts',
            'finance'
        ]::text[]
    ) then
        raise exception using
            errcode = '42501',
            message = 'FORBIDDEN';
    end if;

    /*
     * Validate statuses.
     */
    if p_statuses is null
       or cardinality(p_statuses) = 0
    then
        raise exception
            'SETTLEMENT_STATUSES_REQUIRED';
    end if;

    if array_position(
        p_statuses,
        null
    ) is not null
    then
        raise exception
            'INVALID_SETTLEMENT_STATUS';
    end if;

    /*
     * Fetch trusted user context.
     */
    v_user :=
        public.fetch_user_by_id(
            auth.uid()::text
        );

    if v_user.id is null then
        raise exception
            'USER_NOT_FOUND';
    end if;

    if v_user.status <>
       'active'::public."UserStatus"
    then
        raise exception
            'USER_NOT_ACTIVE';
    end if;

    if nullif(
        btrim(v_user.country_code),
        ''
    ) is null
    then
        raise exception
            'USER_COUNTRY_NOT_CONFIGURED';
    end if;

    /*
     * Fetch batches matching any requested status.
     *
     * Items are deliberately excluded. They are fetched
     * separately through the paginated drill-down.
     */
    select coalesce(
        jsonb_agg(
            jsonb_build_object(
                'id',
                batch_record.id,

                'period',
                batch_record.period,

                'fiscal_year',
                batch_record.fiscal_year,

                'document_number',
                batch_record.document_number,

                'reference',
                batch_record.reference,

                'currency_code',
                lower(
                    btrim(
                        batch_record.currency_code
                    )
                ),

                'start_date',
                batch_record.start_date,

                'end_date',
                batch_record.end_date,

                'total_agents',
                batch_record.total_agents,

                'total_amount',
                trim_scale(
                    batch_record.total_amount
                )::text,

                'status',
                batch_record.status,

                'created_by',
                batch_record.created_by,

                'approved_by',
                batch_record.approved_by,

                'created_at',
                batch_record.created_at,

                'approved_at',
                batch_record.approved_at,

                'paid_at',
                batch_record.paid_at,

                'error_message',
                batch_record.error_message
            )
            order by
                batch_record.created_at desc,
                batch_record.id desc
        ),
        '[]'::jsonb
    )
    into v_result
    from public.agent_settlement_batch
        batch_record
    where lower(
        btrim(
            batch_record.country_code
        )
    ) =
        lower(
            btrim(
                v_user.country_code
            )
        )

      and batch_record.status =
          any(p_statuses);

    return jsonb_build_object(
        'settlementBatch',
        v_result
    );
end;
$function$;



REVOKE ALL ON FUNCTION
    public.fetch_my_agent_commission_settlement_batches(
        public."SettlementStatus"[]
    )
FROM PUBLIC;

REVOKE ALL ON FUNCTION
    public.fetch_my_agent_commission_settlement_batches(
        public."SettlementStatus"[]
    )
FROM anon;

GRANT EXECUTE ON FUNCTION
    public.fetch_my_agent_commission_settlement_batches(
        public."SettlementStatus"[]
    )
TO authenticated;

NOTIFY pgrst, 'reload schema';

