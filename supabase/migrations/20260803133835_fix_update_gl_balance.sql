/* =========================================================
 * APPLY GL SNAPSHOT UPDATE
 * ========================================================= */
create or replace function public.update_gl_balance_snapshot(
    p_components public.posting_component[],
    p_mappings public.transaction_gl_mapping[],
    p_currency_code text,
    p_fiscal_year integer,
    p_country_code text,
    p_period integer
)
returns void
language plpgsql
volatile
as $$
declare
    v_component public.posting_component;
    v_candidate_mapping public.transaction_gl_mapping%rowtype;
    v_selected_mapping public.transaction_gl_mapping%rowtype;

    v_mapping_found boolean;
begin
    if p_components is null then
        raise exception 'POSTING_COMPONENTS_REQUIRED';
    end if;

    if p_mappings is null then
        raise exception 'GL_MAPPINGS_REQUIRED';
    end if;

    foreach v_component in array p_components
    loop
        v_mapping_found := false;

        /*
         * Continue through the complete array so the last matching
         * mapping wins, matching JavaScript Map behavior.
         */
        foreach v_candidate_mapping in array p_mappings
        loop
            if v_candidate_mapping.component_type =
               v_component.component_type
            then
                v_selected_mapping :=
                    v_candidate_mapping;

                v_mapping_found := true;
            end if;
        end loop;

        if not v_mapping_found then
            raise exception
                'MISSING_GL_MAPPING_%',
                v_component.component_type;
        end if;

        perform public.apply_gl_snapshot_update(
            v_selected_mapping.debit_gl,
            coalesce(v_component.debit_amount, 0),
            0,
            p_currency_code,
            p_country_code,
            p_fiscal_year,
            p_period
        );

        perform public.apply_gl_snapshot_update(
            v_selected_mapping.credit_gl,
            0,
            coalesce(v_component.credit_amount, 0),
            p_currency_code,
            p_country_code,
            p_fiscal_year,
            p_period
        );
    end loop;
end;
$$;