begin;

-- Prevent tax writes between the backfill and trigger installation.
lock table public.government_tax_payable in share row exclusive mode;

create table public.government_tax_payable_snapshot (
    id uuid primary key default gen_random_uuid(),
    country_code text not null,
    currency text not null,
    fiscal_year integer not null,
    period integer not null,
    gross_amount numeric not null,
    tax_amount numeric not null,
    tax_rate numeric generated always as (
        round(tax_amount * 100 / nullif(gross_amount, 0), 6)
    ) stored,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (country_code, currency, fiscal_year, period)
);

alter table public.government_tax_payable_snapshot
    enable row level security;

revoke all on public.government_tax_payable_snapshot
    from public, anon, authenticated;

insert into public.government_tax_payable_snapshot (
    country_code, currency, fiscal_year, period, gross_amount, tax_amount
)
select
    country_code,
    currency_code,
    fiscal_year,
    period,
    sum(gross_amount),
    sum(tax_amount)
from public.government_tax_payable
group by country_code, currency_code, fiscal_year, period;

create function public.sync_government_tax_payable_snapshot()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
    if tg_op = 'UPDATE' then
        if (old.country_code, old.currency_code, old.fiscal_year, old.period)
           is not distinct from
           (new.country_code, new.currency_code, new.fiscal_year, new.period)
        then
            if (old.gross_amount, old.tax_amount)
               is distinct from (new.gross_amount, new.tax_amount)
            then
                update public.government_tax_payable_snapshot
                set gross_amount = gross_amount + (new.gross_amount - old.gross_amount),
                    tax_amount = tax_amount + (new.tax_amount - old.tax_amount),
                    updated_at = now()
                where country_code = old.country_code
                  and currency = old.currency_code
                  and fiscal_year = old.fiscal_year
                  and period = old.period;
            end if;

            return null;
        end if;
    end if;

    if tg_op in ('UPDATE', 'DELETE') then
        update public.government_tax_payable_snapshot
        set gross_amount = gross_amount - old.gross_amount,
            tax_amount = tax_amount - old.tax_amount,
            updated_at = now()
        where country_code = old.country_code
          and currency = old.currency_code
          and fiscal_year = old.fiscal_year
          and period = old.period;
    end if;

    if tg_op in ('INSERT', 'UPDATE') then
        insert into public.government_tax_payable_snapshot as snapshot (
            country_code, currency, fiscal_year, period, gross_amount, tax_amount
        )
        values (
            new.country_code, new.currency_code, new.fiscal_year, new.period,
            new.gross_amount, new.tax_amount
        )
        on conflict (country_code, currency, fiscal_year, period)
        do update
        set gross_amount = snapshot.gross_amount + excluded.gross_amount,
            tax_amount = snapshot.tax_amount + excluded.tax_amount,
            updated_at = now();
    end if;

    return null;
end;
$function$;

revoke all on function public.sync_government_tax_payable_snapshot()
    from public, anon, authenticated;

create trigger sync_government_tax_payable_snapshot
after insert or update or delete on public.government_tax_payable
for each row execute function public.sync_government_tax_payable_snapshot();

commit;