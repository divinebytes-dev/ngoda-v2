/* =========================================================
 * GET ALL TRANSACTION VERSIONS
 * ========================================================= */

create or replace function public.get_all_transaction_v()
returns table (
    v text,
    "time" integer
)
language sql
stable
as $$
    select
        t.v,
        t."time"
    from public.transaction_v t;
$$;


/* =========================================================
 * GET TRANSACTION VERSION TIME
 * ========================================================= */

create or replace function public.get_transaction_v(
    p_v text
)
returns integer
language sql
stable
as $$
    select coalesce(
        (
            select t."time"
            from public.transaction_v t
            where t.v = p_v
            limit 1
        ),
        30
    );
$$;