CREATE OR REPLACE FUNCTION public.fetch_my_agent_commission_summary()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
declare
    v_user public.users%rowtype;

    v_now timestamptz :=
        current_timestamp;

    v_start_of_today timestamptz;
    v_start_of_tomorrow timestamptz;

    v_start_of_week timestamptz;
    v_start_of_next_week timestamptz;

    v_start_of_fortnight timestamptz;
    v_end_of_fortnight timestamptz;

    v_start_of_month timestamptz;
    v_start_of_next_month timestamptz;

    v_start_of_year timestamptz;
    v_start_of_next_year timestamptz;

    v_result jsonb :=
        '{}'::jsonb;
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
     * Agents, vendors and merchants may earn commission
     * by facilitating transactions such as cash
     * withdrawals.
     */
    if not public.has_role(
        array[
            'agent',
            'vendor',
            'merchant'
        ]::text[]
    ) then
        raise exception using
            errcode = '42501',
            message = 'FORBIDDEN';
    end if;

    /*
     * Fetch the authenticated user.
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

    /*
     * Calculate reporting boundaries.
     *
     * PostgreSQL weeks begin on Monday, matching the
     * ISO-week calculation previously used by dayjs.
     */
    v_start_of_today :=
        date_trunc(
            'day',
            v_now
        );

    v_start_of_tomorrow :=
        v_start_of_today +
        interval '1 day';

    v_start_of_week :=
        date_trunc(
            'week',
            v_now
        );

    v_start_of_next_week :=
        v_start_of_week +
        interval '1 week';

    /*
     * Fortnight means the current ISO week plus the
     * immediately preceding ISO week.
     */
    v_start_of_fortnight :=
        v_start_of_week -
        interval '1 week';

    v_end_of_fortnight :=
        v_start_of_next_week;

    v_start_of_month :=
        date_trunc(
            'month',
            v_now
        );

    v_start_of_next_month :=
        v_start_of_month +
        interval '1 month';

    v_start_of_year :=
        date_trunc(
            'year',
            v_now
        );

    v_start_of_next_year :=
        v_start_of_year +
        interval '1 year';

    /*
     * Build:
     *
     * {
     *   "usd": {
     *     "today": {...},
     *     "week": {...},
     *     "fortnight": {...},
     *     "month": {...},
     *     "year": {...}
     *   }
     * }
     *
     * Only currencies having commission entries during
     * the current year are included, matching the
     * previous Prisma implementation.
     */
    with reporting_periods as (
        select *
        from (
            values
                (
                    'today'::text,
                    1,
                    v_start_of_today,
                    v_start_of_tomorrow
                ),

                (
                    'week'::text,
                    2,
                    v_start_of_week,
                    v_start_of_next_week
                ),

                (
                    'fortnight'::text,
                    3,
                    v_start_of_fortnight,
                    v_end_of_fortnight
                ),

                (
                    'month'::text,
                    4,
                    v_start_of_month,
                    v_start_of_next_month
                ),

                (
                    'year'::text,
                    5,
                    v_start_of_year,
                    v_start_of_next_year
                )
        ) as period_record(
            period_name,
            sort_order,
            start_at,
            end_at
        )
    ),

    user_currencies as (
        select distinct
            lower(
                btrim(
                    commission_record.currency_code
                )
            ) as currency_code

        from public.agent_commission
            commission_record

        where commission_record.agent_id =
                  v_user.id

          and commission_record.created_at >=
                  v_start_of_year

          and commission_record.created_at <
                  v_start_of_next_year
    ),

    period_totals as (
        select
            currency_record.currency_code,

            period_record.period_name,

            period_record.sort_order,

            coalesce(
                sum(
                    coalesce(
                        commission_record.amount,
                        0
                    )
                ),
                0
            )::numeric as total_amount,

            coalesce(
                sum(
                    coalesce(
                        commission_record.fee_amount,
                        0
                    )
                ),
                0
            )::numeric as total_fee,

            coalesce(
                sum(
                    coalesce(
                        commission_record.commission_amount,
                        0
                    )
                ),
                0
            )::numeric as total_commission,

            coalesce(
                sum(
                    case
                        when commission_record.is_settled =
                             true
                        then
                            coalesce(
                                commission_record.commission_amount,
                                0
                            )
                        else
                            0
                    end
                ),
                0
            )::numeric as paid,

            coalesce(
                sum(
                    case
                        when commission_record.is_settled =
                             false
                        then
                            coalesce(
                                commission_record.commission_amount,
                                0
                            )
                        else
                            0
                    end
                ),
                0
            )::numeric as not_paid

        from user_currencies
            currency_record

        cross join reporting_periods
            period_record

        left join public.agent_commission
            commission_record
          on commission_record.agent_id =
                 v_user.id

         and lower(
             btrim(
                 commission_record.currency_code
             )
         ) =
                 currency_record.currency_code

         and commission_record.created_at >=
                 period_record.start_at

         and commission_record.created_at <
                 period_record.end_at

         /*
          * Preserve the original behavior where only
          * current-year rows were loaded before period
          * calculations.
          */
         and commission_record.created_at >=
                 v_start_of_year

         and commission_record.created_at <
                 v_start_of_next_year

        group by
            currency_record.currency_code,
            period_record.period_name,
            period_record.sort_order
    ),

    currency_summaries as (
        select
            period_total.currency_code,

            jsonb_object_agg(
                period_total.period_name,

                jsonb_build_object(
                    'total_amount',
                    trim_scale(
                        period_total.total_amount
                    )::text,

                    'total_fee',
                    trim_scale(
                        period_total.total_fee
                    )::text,

                    'total_commission',
                    trim_scale(
                        period_total.total_commission
                    )::text,

                    'paid',
                    trim_scale(
                        period_total.paid
                    )::text,

                    'not_paid',
                    trim_scale(
                        period_total.not_paid
                    )::text
                )

                order by
                    period_total.sort_order
            ) as summary

        from period_totals
            period_total

        group by
            period_total.currency_code
    )

    select coalesce(
        jsonb_object_agg(
            currency_summary.currency_code,
            currency_summary.summary
            order by
                currency_summary.currency_code
        ),
        '{}'::jsonb
    )
    into v_result
    from currency_summaries
        currency_summary;

    return v_result;
end;
$function$;


REVOKE ALL ON FUNCTION
    public.fetch_my_agent_commission_summary()
FROM PUBLIC;

REVOKE ALL ON FUNCTION
    public.fetch_my_agent_commission_summary()
FROM anon;

GRANT EXECUTE ON FUNCTION
    public.fetch_my_agent_commission_summary()
TO authenticated;