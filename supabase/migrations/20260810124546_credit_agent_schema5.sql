create or replace function public.get_base_transaction_type(
    p_transaction_type public."TransactionType"
)
returns public."TransactionType"
language plpgsql
immutable
parallel safe
strict
set search_path to ''
as $function$
declare
    v_transaction_type_text text;
    v_base_transaction_type_text text;
    v_base_transaction_type
        public."TransactionType";
begin
    v_transaction_type_text :=
        p_transaction_type::text;

    /*
     * Normal transactions are already their own base type.
     */
    if v_transaction_type_text not like
       '%\_reversal' escape '\'
    then
        return p_transaction_type;
    end if;

    /*
     * Reversal transaction names follow:
     *
     * <base_transaction_type>_reversal
     */
    v_base_transaction_type_text :=
        left(
            v_transaction_type_text,
            length(v_transaction_type_text)
            - length('_reversal')
        );

    if nullif(
        btrim(v_base_transaction_type_text),
        ''
    ) is null
    then
        raise exception
            'BASE_TRANSACTION_TYPE_NOT_FOUND_%',
            upper(v_transaction_type_text);
    end if;

    /*
     * Validate that the derived base name exists in the
     * TransactionType enum.
     */
    begin
        v_base_transaction_type :=
            v_base_transaction_type_text
                ::public."TransactionType";

    exception
        when invalid_text_representation then
            raise exception
                'BASE_TRANSACTION_TYPE_NOT_FOUND_%',
                upper(v_transaction_type_text);
    end;

    return v_base_transaction_type;
end;
$function$;


revoke all on function
    public.get_base_transaction_type(
        public."TransactionType"
    )
from public;

revoke all on function
    public.get_base_transaction_type(
        public."TransactionType"
    )
from anon;

revoke all on function
    public.get_base_transaction_type(
        public."TransactionType"
    )
from authenticated;