CREATE OR REPLACE FUNCTION public.fetch_my_agent_commission_batches(
    p_status public."SettlementStatus"
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
declare
    v_user public.users%rowtype;

    v_batches jsonb :=
        '[]'::jsonb;
begin
    /*
     * Authentication and authorization.
     */
    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHORIZED';
    end if;

    if not public.has_role(
        array[
            'finance',
            'accounts'
        ]::text[]
    ) then
        raise exception using
            errcode = '42501',
            message = 'FORBIDDEN';
    end if;

    if p_status is null then
        raise exception
            'SETTLEMENT_STATUS_REQUIRED';
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
     * Fetch batch headers only.
     *
     * Settlement items are fetched separately using the
     * paginated drill-down endpoint.
     */
    select coalesce(
        jsonb_agg(
            to_jsonb(
                batch_record
            )
            ||
            jsonb_build_object(
                'total_amount',
                batch_record.total_amount::text
            )
            order by
                batch_record.created_at desc,
                batch_record.id desc
        ),
        '[]'::jsonb
    )
    into v_batches
    from public.agent_settlement_batch
        batch_record
    where batch_record.status =
              p_status

      and lower(
          btrim(
              batch_record.country_code
          )
      ) =
              lower(
                  btrim(
                      v_user.country_code
                  )
              );

    return jsonb_build_object(
        'settlementBatch',
        v_batches
    );
end;
$function$;


REVOKE ALL ON FUNCTION
    public.fetch_my_agent_commission_batches(
        public."SettlementStatus"
    )
FROM PUBLIC;

REVOKE ALL ON FUNCTION
    public.fetch_my_agent_commission_batches(
        public."SettlementStatus"
    )
FROM anon;

GRANT EXECUTE ON FUNCTION
    public.fetch_my_agent_commission_batches(
        public."SettlementStatus"
    )
TO authenticated;