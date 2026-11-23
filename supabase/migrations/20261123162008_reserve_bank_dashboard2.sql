begin;

lock table public.government_tax_payable in share row exclusive mode;

create or replace function public.sync_government_tax_payable_snapshot()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
    insert into public.government_tax_payable_snapshot as snapshot (
        country_code,
        currency,
        fiscal_year,
        period,
        gross_amount,
        tax_amount
    )
    values (
        new.country_code,
        new.currency_code,
        new.fiscal_year,
        new.period,
        new.gross_amount,
        new.tax_amount
    )
    on conflict (country_code, currency, fiscal_year, period)
    do update
    set gross_amount = snapshot.gross_amount + excluded.gross_amount,
        tax_amount = snapshot.tax_amount + excluded.tax_amount,
        updated_at = now();

    return null;
end;
$function$;

drop trigger if exists sync_government_tax_payable_snapshot
    on public.government_tax_payable;

create trigger sync_government_tax_payable_snapshot
after insert on public.government_tax_payable
for each row execute function public.sync_government_tax_payable_snapshot();

commit;