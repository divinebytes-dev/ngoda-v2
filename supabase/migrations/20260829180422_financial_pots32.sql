CREATE OR REPLACE FUNCTION public.get_my_financial_badges()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
    v_user_id text;
    v_result jsonb;
BEGIN

    -- ==========================================================
    -- AUTHENTICATION
    -- ==========================================================

    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION USING
            ERRCODE = '42501',
            MESSAGE = 'UNAUTHORIZED';
    END IF;


    -- ==========================================================
    -- VALIDATE CUSTOMER
    -- ==========================================================

    SELECT
        u.id
    INTO
        v_user_id
    FROM public.users AS u
    JOIN public.user_role AS r
        ON r.id = u.role_id
    WHERE u.id = auth.uid()::text
      AND u.status = 'active'::public."UserStatus"
      AND lower(r.name::text) = 'customer'
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION USING
            ERRCODE = '42501',
            MESSAGE = 'FINANCIAL_BEHAVIOUR_NOT_AUTHORIZED';
    END IF;


    -- ==========================================================
    -- BUILD BADGE REPORT
    --
    -- Returns every active badge definition together with
    -- the authenticated user's achievement information.
    --
    -- An unearned badge remains in the response with:
    --
    -- earned = false
    -- achieved_value_usd = null
    -- fiscal_year = null
    -- period = null
    -- achieved_at = null
    -- ==========================================================

    SELECT
        jsonb_build_object(

            'badges',

            COALESCE(
                jsonb_agg(
                    jsonb_build_object(

                        'id',
                            b.id,

                        'code',
                            b.code,

                        'behavior',
                            b.behavior,

                        'metric',
                            b.metric,

                        'level',
                            b.level,

                        'threshold_usd',
                            b.threshold_usd,

                        'name',
                            b.name,

                        'description',
                            b.description,

                        'earned',
                            ub.id IS NOT NULL,

                        'achieved_value_usd',
                            ub.achieved_value_usd,

                        'fiscal_year',
                            ub.fiscal_year,

                        'period',
                            ub.period,

                        'achieved_at',
                            ub.achieved_at
                    )
                    ORDER BY
                        b.behavior,
                        b.level,
                        b.threshold_usd
                ),
                '[]'::jsonb
            )
        )
    INTO
        v_result
    FROM public.financial_badge AS b

    LEFT JOIN public.user_financial_badge AS ub
        ON ub.badge_id = b.id
       AND ub.user_id = v_user_id

    WHERE b.is_active = true;


    -- ==========================================================
    -- RETURN
    -- ==========================================================

    RETURN COALESCE(
        v_result,
        jsonb_build_object(
            'badges',
            '[]'::jsonb
        )
    );

END;
$function$;


-- ==============================================================
-- SECURITY
-- ==============================================================

REVOKE ALL
ON FUNCTION public.get_my_financial_badges()
FROM PUBLIC;

GRANT EXECUTE
ON FUNCTION public.get_my_financial_badges()
TO authenticated;