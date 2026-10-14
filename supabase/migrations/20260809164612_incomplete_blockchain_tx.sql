create or replace function public.fetch_incomplete_blockchain_transactions(
    p_page integer default 1,
    p_page_size integer default 50
)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
    v_page integer;
    v_page_size integer;
    v_offset integer;

    v_total_entries bigint := 0;
    v_total_pages integer := 1;

    v_transactions jsonb :=
        '[]'::jsonb;
begin
    /*
     * Require an authenticated request.
     *
     * No additional role restriction is introduced because
     * the original endpoint did not enforce one.
     */
    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHENTICATED';
    end if;

    /*
     * Validate pagination.
     */
    if p_page is null
       or p_page < 1
    then
        raise exception
            'INVALID_PAGE';
    end if;

    if p_page_size is null
       or p_page_size < 1
       or p_page_size > 100
    then
        raise exception
            'INVALID_PAGE_SIZE';
    end if;

    v_page :=
        p_page;

    v_page_size :=
        p_page_size;

    v_offset :=
        (v_page - 1) *
        v_page_size;

    /*
     * Count all blockchain transactions that have not yet
     * received an accounting document.
     */
    select count(*)
    into v_total_entries
    from public.blockchain_transaction
        blockchain_record
    where blockchain_record.document_number is null;

    v_total_pages :=
        case
            when v_total_entries = 0
                then 1
            else
                ceil(
                    v_total_entries::numeric /
                    v_page_size
                )::integer
        end;

    /*
     * Fetch the requested page.
     */
    select coalesce(
        jsonb_agg(
            to_jsonb(
                transaction_record
            )
            order by
                transaction_record.created_at desc,
                transaction_record.id desc
        ),
        '[]'::jsonb
    )
    into v_transactions
    from (
        select blockchain_record.*
        from public.blockchain_transaction
            blockchain_record
        where blockchain_record.document_number is null
        order by
            blockchain_record.created_at desc,
            blockchain_record.id desc
        limit v_page_size
        offset v_offset
    ) as transaction_record;

    return jsonb_build_object(
        'transactions',
        v_transactions,

        'pagination',
        jsonb_build_object(
            'page',
            v_page,

            'page_size',
            v_page_size,

            'total_entries',
            v_total_entries,

            'total_pages',
            v_total_pages,

            'has_previous',
            v_page > 1,

            'has_next',
            v_page < v_total_pages
        )
    );
end;
$function$;


revoke all on function
    public.fetch_incomplete_blockchain_transactions(
        integer,
        integer
    )
from public;

revoke all on function
    public.fetch_incomplete_blockchain_transactions(
        integer,
        integer
    )
from anon;

grant execute on function
    public.fetch_incomplete_blockchain_transactions(
        integer,
        integer
    )
to authenticated;

notify pgrst, 'reload schema';