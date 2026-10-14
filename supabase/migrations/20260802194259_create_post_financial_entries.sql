/* =========================================================
 * POST FINANCIAL ENTRIES
 * ========================================================= */

create or replace function public.post_financial_entries(
    p_document_number text,
    p_country_code text,
    p_transaction_id bigint,
    p_transaction_type public."TransactionType",
    p_created_by text,
    p_components public.posting_component[],
    p_mappings public.transaction_gl_mapping[],
    p_currency_code text,
    p_fiscal_year integer,
    p_period integer,
    p_reference text default null,
    p_deposit_type public."CustomerDepositType" default null
)
returns table (
    count integer,
    total_debit numeric,
    total_credit numeric
)
language plpgsql
volatile
as $$
declare
    v_component public.posting_component;
    v_mapping public.transaction_gl_mapping%rowtype;
    v_candidate_mapping public.transaction_gl_mapping%rowtype;

    v_mapping_found boolean;
    v_entry_count integer := 0;
    v_total_debit numeric := 0;
    v_total_credit numeric := 0;
begin
    /*
     * First pass:
     * Validate mappings, count entries and calculate totals.
     */
    foreach v_component in array p_components
    loop
        v_mapping_found := false;
        v_mapping := null;

        /*
         * JavaScript Map uses the last mapping found for a component.
         */
        foreach v_candidate_mapping in array p_mappings
        loop
            if v_candidate_mapping.component_type =
               v_component.component_type
            then
                v_mapping := v_candidate_mapping;
                v_mapping_found := true;
            end if;
        end loop;

        if not v_mapping_found then
            raise exception
                'MISSING_GL_MAPPING_FOR_COMPONENT_%',
                v_component.component_type;
        end if;

        if v_component.debit_amount <= 0
           and v_component.credit_amount <= 0
        then
            continue;
        end if;

        if v_component.debit_amount > 0 then
            v_entry_count := v_entry_count + 1;
            v_total_debit :=
                v_total_debit +
                v_component.debit_amount;
        end if;

        if v_component.credit_amount > 0 then
            v_entry_count := v_entry_count + 1;
            v_total_credit :=
                v_total_credit +
                v_component.credit_amount;
        end if;
    end loop;

    if v_entry_count = 0 then
        raise exception 'NO_FINANCIAL_ENTRIES_TO_POST';
    end if;

    if v_total_debit <> v_total_credit then
        raise exception
            'DOCUMENT_NOT_BALANCED_DEBIT_%_CREDIT_%',
            v_total_debit,
            v_total_credit;
    end if;

    /*
     * Second pass:
     * Create the validated financial entries.
     */
    foreach v_component in array p_components
    loop
        v_mapping_found := false;
        v_mapping := null;

        foreach v_candidate_mapping in array p_mappings
        loop
            if v_candidate_mapping.component_type =
               v_component.component_type
            then
                v_mapping := v_candidate_mapping;
                v_mapping_found := true;
            end if;
        end loop;

        if not v_mapping_found then
            raise exception
                'MISSING_GL_MAPPING_FOR_COMPONENT_%',
                v_component.component_type;
        end if;

        if v_component.debit_amount > 0 then
            insert into public.financial_entry (
                document_number,
                country_code,
                reference,
                transaction_id,
                transaction_type,
                fiscal_year,
                period,
                gl_account_code,
                debit,
                credit,
                created_by,
                currency_code,
                deposit_type
            )
            values (
                p_document_number,
                p_country_code,
                p_reference,
                p_transaction_id,
                p_transaction_type,
                p_fiscal_year,
                p_period,
                v_mapping.debit_gl,
                v_component.debit_amount,
                0,
                p_created_by,
                p_currency_code,
                p_deposit_type
            );
        end if;

        if v_component.credit_amount > 0 then
            insert into public.financial_entry (
                document_number,
                country_code,
                reference,
                transaction_id,
                transaction_type,
                fiscal_year,
                period,
                gl_account_code,
                debit,
                credit,
                created_by,
                currency_code,
                deposit_type
            )
            values (
                p_document_number,
                p_country_code,
                p_reference,
                p_transaction_id,
                p_transaction_type,
                p_fiscal_year,
                p_period,
                v_mapping.credit_gl,
                0,
                v_component.credit_amount,
                p_created_by,
                p_currency_code,
                p_deposit_type
            );
        end if;
    end loop;

    perform public.update_gl_balance_snapshot(
        p_components,
        p_mappings,
        p_currency_code,
        p_fiscal_year,
        p_country_code,
        p_period
    );

    return query
    select
        v_entry_count,
        v_total_debit,
        v_total_credit;
end;
$$;