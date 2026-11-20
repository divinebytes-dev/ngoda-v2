begin;

-- Prevent duplicate periods, including concurrent manual creation.
-- If duplicates already exist, this statement fails visibly.
create unique index if not exists fiscal_period_country_year_period_uidx
on public.fiscal_period_config (
    country_code,
    fiscal_year,
    period
);


create or replace function public.run_country_fiscal_year_rollover(
    p_country_code text
)
returns jsonb
language plpgsql
security definer
set search_path to ''
set timezone to 'UTC'
as $function$
declare
    v_country text :=
        lower(nullif(btrim(p_country_code), ''));

    v_zone text;

    v_now timestamptz := statement_timestamp();
    v_local_now timestamp;

    v_year record;

    v_first_local timestamp;
    v_boundary_local timestamp;
    v_boundary_utc timestamp;
    v_target_start timestamp;

    v_next_year integer;
    v_next_count integer;

    v_created integer;
    v_closed integer;

    v_opened_years integer := 0;
    v_closed_years integer := 0;

    v_actor constant text := 'system:fiscal-year-rollover';
begin
    if v_country is null then
        raise exception 'COUNTRY_REQUIRED';
    end if;

    select c.time_zone
    into v_zone
    from public.operational_country c
    where c.country_code = v_country
      and c.is_active = true;

    if not found then
        return jsonb_build_object(
            'country_code', v_country,
            'inactive', true
        );
    end if;

    if v_zone is null
       or not exists (
           select 1
           from pg_catalog.pg_timezone_names
           where name = v_zone
       )
    then
        raise exception
            'INVALID_COUNTRY_TIME_ZONE_%',
            v_country;
    end if;

    if not pg_catalog.pg_try_advisory_xact_lock(
        pg_catalog.hashtextextended(
            'ngoda:fiscal-year-rollover:' || v_country,
            0
        )
    ) then
        return jsonb_build_object(
            'country_code', v_country,
            'already_running', true
        );
    end if;

    if not exists (
        select 1
        from public.fiscal_period_config
        where country_code = v_country
    ) then
        raise exception
            'COUNTRY_FISCAL_CALENDAR_NOT_CONFIGURED_%',
            v_country;
    end if;

    -- Coordinate calendar writes with existing manual operations.
    lock table public.fiscal_period_config
        in share row exclusive mode;

    v_local_now := v_now at time zone v_zone;

    for v_year in
        select
            f.fiscal_year,
            count(*) as periods,
            min(f.opening_date) as first_open,
            max(f.closing_date) as last_close
        from public.fiscal_period_config f
        where f.country_code = v_country
        group by f.fiscal_year
        having bool_or(f.is_closed = false)
        order by min(f.opening_date)
    loop
        if not isfinite(v_year.first_open)
           or not isfinite(v_year.last_close)
        then
            raise exception
                'INVALID_FISCAL_YEAR_DATES_%_%',
                v_country,
                v_year.fiscal_year;
        end if;

        v_first_local :=
            (v_year.first_open at time zone 'UTC')
                at time zone v_zone;

        -- Midnight after the final configured local calendar day.
        v_boundary_local := (
            (
                (v_year.last_close at time zone 'UTC')
                    at time zone v_zone
            )::date + 1
        )::timestamp;

        if v_local_now <
           v_boundary_local - interval '1 minute'
        then
            continue;
        end if;

        -- Validate the supplied 12-month calendar structure.
        if v_year.periods <> 12
           or v_first_local <>
              date_trunc('month', v_first_local)
           or v_boundary_local <>
              v_first_local + interval '1 year'
        then
            raise exception
                'INVALID_ANNUAL_FISCAL_CALENDAR_%_%',
                v_country,
                v_year.fiscal_year;
        end if;

        if exists (
            select 1
            from public.fiscal_period_config f
            where f.country_code = v_country
              and f.fiscal_year = v_year.fiscal_year
              and (
                  f.opening_date <> (
                      (
                          v_first_local
                          + (f.period - 1) * interval '1 month'
                      ) at time zone v_zone
                  ) at time zone 'UTC'

                  or f.closing_date < (
                      (
                          (
                              v_first_local
                              + f.period * interval '1 month'
                          ) at time zone v_zone
                      ) at time zone 'UTC'
                  ) - interval '1 second'

                  or f.closing_date >= (
                      (
                          v_first_local
                          + f.period * interval '1 month'
                      ) at time zone v_zone
                  ) at time zone 'UTC'
              )
        ) then
            raise exception
                'INVALID_FISCAL_PERIOD_BOUNDARIES_%_%',
                v_country,
                v_year.fiscal_year;
        end if;

        v_next_year := v_year.fiscal_year + 1;
        v_target_start := v_boundary_local;

        v_boundary_utc :=
            (v_boundary_local at time zone v_zone)
                at time zone 'UTC';

        -- Reject another fiscal year overlapping the target calendar.
        if exists (
            select 1
            from public.fiscal_period_config f
            where f.country_code = v_country
              and f.fiscal_year not in (
                  v_year.fiscal_year,
                  v_next_year
              )
              and f.opening_date < (
                  (
                      v_target_start + interval '1 year'
                  ) at time zone v_zone
              ) at time zone 'UTC'
              and f.closing_date >= v_boundary_utc
        ) then
            raise exception
                'OVERLAPPING_FISCAL_YEAR_%_%',
                v_country,
                v_next_year;
        end if;

        select count(*)
        into v_next_count
        from public.fiscal_period_config f
        where f.country_code = v_country
          and f.fiscal_year = v_next_year;

        if v_next_count = 0 then
            insert into public.fiscal_period_config (
                fiscal_year,
                period,
                country_code,
                period_name,
                opening_date,
                closing_date,
                is_closed,
                created_at,
                created_by,
                updated_at,
                updated_by
            )
            select
                v_next_year,
                f.period,
                v_country,
                f.period_name,

                (
                    (
                        v_target_start
                        + (f.period - 1) * interval '1 month'
                    ) at time zone v_zone
                ) at time zone 'UTC',

                (
                    (
                        (
                            v_target_start
                            + f.period * interval '1 month'
                        ) at time zone v_zone
                    ) at time zone 'UTC'
                ) - interval '1 millisecond',

                false,
                v_now at time zone 'UTC',
                v_actor,
                v_now at time zone 'UTC',
                v_actor
            from public.fiscal_period_config f
            where f.country_code = v_country
              and f.fiscal_year = v_year.fiscal_year
            order by f.period;

            get diagnostics v_created = row_count;

            if v_created <> 12 then
                raise exception
                    'FISCAL_YEAR_CREATION_INCOMPLETE_%_%',
                    v_country,
                    v_next_year;
            end if;

            v_opened_years := v_opened_years + 1;

        elsif v_next_count <> 12 then
            raise exception
                'NEXT_FISCAL_YEAR_INCOMPLETE_%_%',
                v_country,
                v_next_year;
        end if;

        -- Verify new or previously configured next-year periods.
        if exists (
            select 1
            from public.fiscal_period_config f
            where f.country_code = v_country
              and f.fiscal_year = v_next_year
              and (
                  f.opening_date <> (
                      (
                          v_target_start
                          + (f.period - 1) * interval '1 month'
                      ) at time zone v_zone
                  ) at time zone 'UTC'

                  or f.closing_date < (
                      (
                          (
                              v_target_start
                              + f.period * interval '1 month'
                          ) at time zone v_zone
                      ) at time zone 'UTC'
                  ) - interval '1 second'

                  or f.closing_date >= (
                      (
                          v_target_start
                          + f.period * interval '1 month'
                      ) at time zone v_zone
                  ) at time zone 'UTC'

                  or (
                      f.is_closed
                      and v_local_now <
                          v_target_start + interval '1 year'
                  )
              )
        ) then
            raise exception
                'NEXT_FISCAL_YEAR_INVALID_%_%',
                v_country,
                v_next_year;
        end if;

        -- Cover the final fractional second before the new year.
        update public.fiscal_period_config
        set
            closing_date =
                v_boundary_utc - interval '1 millisecond',
            updated_at = v_now at time zone 'UTC',
            updated_by = v_actor
        where country_code = v_country
          and fiscal_year = v_year.fiscal_year
          and period = 12
          and closing_date <
              v_boundary_utc - interval '1 millisecond';

        if v_local_now >= v_boundary_local then
            update public.fiscal_period_config
            set
                is_closed = true,
                updated_at = v_now at time zone 'UTC',
                updated_by = v_actor
            where country_code = v_country
              and fiscal_year = v_year.fiscal_year
              and is_closed = false;

            get diagnostics v_closed = row_count;

            if v_closed > 0 then
                v_closed_years := v_closed_years + 1;
            end if;
        end if;
    end loop;

    return jsonb_build_object(
        'success', true,
        'country_code', v_country,
        'opened_years', v_opened_years,
        'closed_years', v_closed_years
    );
end;
$function$;


-- Restrict this scheduled entry point to the database administrator.
revoke all
on function public.run_country_fiscal_year_rollover(text)
from public, anon, authenticated, service_role;

grant execute
on function public.run_country_fiscal_year_rollover(text)
to postgres;


-- Register one job per currently active operational country.
do $schedule$
declare
    v_country record;
begin
    for v_country in
        select country_code
        from public.operational_country
        where is_active = true
        order by country_code
    loop
        perform cron.schedule(
            'fiscal-year-rollover-' || v_country.country_code,
            '* * * * *',
            format(
                'select public.run_country_fiscal_year_rollover(%L);',
                v_country.country_code
            )
        );
    end loop;
end;
$schedule$;

commit;