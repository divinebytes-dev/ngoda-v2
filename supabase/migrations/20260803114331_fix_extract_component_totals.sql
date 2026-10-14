create or replace function public.extract_component_totals(
    p_components public.posting_component[],
    p_reverse boolean default false
)
returns public.component_totals
language plpgsql
immutable
parallel safe
as $$
declare
    v_component public.posting_component;
    v_principal_amount numeric := 0;
    v_others_amount numeric := 0;
    v_principal_found boolean := false;
begin
    if p_components is null then
        return row(0, 0)::public.component_totals;
    end if;

    foreach v_component in array p_components
    loop
        if v_component is null then
            continue;
        end if;

        if v_component.component_type =
           'principal'::public."ComponentType"
        then
            if not v_principal_found then
                v_principal_amount :=
                    case
                        when coalesce(p_reverse, false)
                            then coalesce(v_component.credit_amount, 0)
                        else coalesce(v_component.debit_amount, 0)
                    end;

                v_principal_found := true;
            end if;
        else
            v_others_amount :=
                v_others_amount +
                case
                    when coalesce(p_reverse, false)
                        then coalesce(v_component.debit_amount, 0)
                    else coalesce(v_component.credit_amount, 0)
                end;
        end if;
    end loop;

    return row(
        v_principal_amount,
        v_others_amount
    )::public.component_totals;
end;
$$;