/* =========================================================
 * GENERATE DOCUMENT NUMBER
 * ========================================================= */

create or replace function public.generate_document_number(
    p_prefix text,
    p_fiscal_year integer,
    p_period integer,
    p_country_code text
)
returns text
language plpgsql
volatile
as $$
declare
    v_last_number integer;
begin
    insert into public.document_sequence (
        period,
        fiscal_year,
        country_code,
        prefix,
        last_number
    )
    values (
        p_period,
        p_fiscal_year,
        p_country_code,
        p_prefix,
        1
    )
    on conflict (
        country_code,
        prefix,
        fiscal_year
    )
    do update
    set last_number =
        public.document_sequence.last_number + 1
    returning last_number
    into v_last_number;

    return
        p_prefix || '-' ||
        p_fiscal_year::text || '-' ||
        lpad(v_last_number::text, 10, '0');
end;
$$;


/* =========================================================
 * FETCH TRANSACTION DOCUMENT NUMBER PREFIX
 * ========================================================= */

create or replace function public.fetch_transaction_doc_num_prefix(
    p_transaction_type public."TransactionType"
)
returns text
language plpgsql
stable
as $$
declare
    v_document_number text;
begin
    select p.document_number
    into v_document_number
    from public.transaction_type_document_number_prefix p
    where p.transaction_type = p_transaction_type
    limit 1;

    if not found then
        raise exception 'DOC_NUM_PREFIX_NOT_FOUND';
    end if;

    return v_document_number;
end;
$$;