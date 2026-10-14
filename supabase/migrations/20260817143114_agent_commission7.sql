CREATE OR REPLACE FUNCTION public.fetch_my_agent_commission_settlement_batches(
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

    v_rows jsonb :=
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
     * Build the settlement summary.
     *
     * Results are grouped by:
     *
     * - transaction type;
     * - currency.
     *
     * The agent count is the number of distinct agents,
     * merchants or vendors earning commission.
     */
    select coalesce(
        jsonb_agg(
            jsonb_build_object(
                'transaction_type',
                summary_record.transaction_type,

                'currency_code',
                summary_record.currency_code,

                'agents',
                summary_record.agents,

                'total_amount',
                summary_record.total_amount::text,

                'total_fee_amount',
                summary_record.total_fee_amount::text,

                'total_commission_amount',
                summary_record.total_commission_amount::text
            )
            order by
                summary_record.currency_code,
                summary_record.transaction_type
        ),
        '[]'::jsonb
    )
    into v_rows
    from (
        select
            commission_record.transaction_type::text
                as transaction_type,

            lower(
                btrim(
                    commission_record.currency_code
                )
            ) as currency_code,

            count(
                distinct commission_record.agent_id
            )::integer as agents,

            coalesce(
                sum(
                    commission_record.amount
                ),
                0
            )::numeric as total_amount,

            coalesce(
                sum(
                    commission_record.fee_amount
                ),
                0
            )::numeric as total_fee_amount,

            coalesce(
                sum(
                    commission_record.commission_amount
                ),
                0
            )::numeric as total_commission_amount

        from public.agent_commission
            commission_record

        join public.agent_settlement_batch
            batch_record
          on batch_record.id =
             commission_record.settlement_batch_id

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
                  )

        group by
            commission_record.transaction_type,

            lower(
                btrim(
                    commission_record.currency_code
                )
            )
    ) as summary_record;

    return jsonb_build_object(
        'rows',
        v_rows
    );
end;
$function$;


REVOKE ALL ON FUNCTION
    public.fetch_my_agent_commission_settlement_batches(
        public."SettlementStatus"
    )
FROM PUBLIC;

REVOKE ALL ON FUNCTION
    public.fetch_my_agent_commission_settlement_batches(
        public."SettlementStatus"
    )
FROM anon;

GRANT EXECUTE ON FUNCTION
    public.fetch_my_agent_commission_settlement_batches(
        public."SettlementStatus"
    )
TO authenticated;