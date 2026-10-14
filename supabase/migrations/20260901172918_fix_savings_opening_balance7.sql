BEGIN;


/*
 * ==============================================================
 * BACKFILL OUTGOING CASH-FLOW SNAPSHOTS
 * ==============================================================
 *
 * Source:
 *     public.financial_pot_event
 *
 * Target:
 *     public.financial_pot
 *
 * Fields:
 *
 *     withdrawal_cash_amount
 *     withdrawal_cash_amount_usd
 *
 *     spending_cash_amount
 *     spending_cash_amount_usd
 *
 *     investment_cash_amount
 *     investment_cash_amount_usd
 *
 *     repayment_cash_amount
 *     repayment_cash_amount_usd
 *
 * These values represent actual cash leaving savings.
 *
 * They are intentionally separate from:
 *
 *     withdrawal_amount
 *     spending_amount
 *     investment_purchase_amount
 *     loan_repayment_amount
 *
 * because those fields represent business/activity amounts.
 * ==============================================================
 */


/*
 * ==============================================================
 * RESET SNAPSHOT FIELDS
 * ==============================================================
 *
 * Makes this migration repeatable.
 * ==============================================================
 */

UPDATE public.financial_pot
SET
    withdrawal_cash_amount = 0,
    withdrawal_cash_amount_usd = 0,

    spending_cash_amount = 0,
    spending_cash_amount_usd = 0,

    investment_cash_amount = 0,
    investment_cash_amount_usd = 0,

    repayment_cash_amount = 0,
    repayment_cash_amount_usd = 0;


/*
 * ==============================================================
 * REBUILD FROM FINANCIAL POT EVENTS
 * ==============================================================
 */

WITH event_totals AS (

    SELECT
        e.user_id,

        lower(
            e.country_code
        ) AS country_code,

        lower(
            e.currency_code
        ) AS currency_code,

        e.fiscal_year,
        e.period,


        /*
         * ------------------------------------------------------
         * WITHDRAWAL
         * ------------------------------------------------------
         *
         * Exact equivalent of the previous report logic:
         *
         * activity_type = withdrawal
         *
         * Uses actual cash movement, not business amount.
         * ------------------------------------------------------
         */

        COALESCE(
            SUM(
                CASE
                    WHEN e.activity_type =
                         'withdrawal'
                             ::public.financial_activity_type

                    THEN COALESCE(
                        e.cash_amount,
                        0
                    )

                    ELSE 0
                END
            ),
            0
        ) AS withdrawal_cash_amount,

        COALESCE(
            SUM(
                CASE
                    WHEN e.activity_type =
                         'withdrawal'
                             ::public.financial_activity_type

                    THEN COALESCE(
                        e.cash_amount_usd,
                        0
                    )

                    ELSE 0
                END
            ),
            0
        ) AS withdrawal_cash_amount_usd,


        /*
         * ------------------------------------------------------
         * SPENDING
         * ------------------------------------------------------
         */

        COALESCE(
            SUM(
                CASE
                    WHEN e.activity_type =
                         'spending'
                             ::public.financial_activity_type

                    THEN COALESCE(
                        e.cash_amount,
                        0
                    )

                    ELSE 0
                END
            ),
            0
        ) AS spending_cash_amount,

        COALESCE(
            SUM(
                CASE
                    WHEN e.activity_type =
                         'spending'
                             ::public.financial_activity_type

                    THEN COALESCE(
                        e.cash_amount_usd,
                        0
                    )

                    ELSE 0
                END
            ),
            0
        ) AS spending_cash_amount_usd,


        /*
         * ------------------------------------------------------
         * INVESTMENT BUY
         * ------------------------------------------------------
         *
         * Actual cash removed from savings to purchase
         * investments.
         * ------------------------------------------------------
         */

        COALESCE(
            SUM(
                CASE
                    WHEN e.activity_type =
                         'investment_buy'
                             ::public.financial_activity_type

                    THEN COALESCE(
                        e.cash_amount,
                        0
                    )

                    ELSE 0
                END
            ),
            0
        ) AS investment_cash_amount,

        COALESCE(
            SUM(
                CASE
                    WHEN e.activity_type =
                         'investment_buy'
                             ::public.financial_activity_type

                    THEN COALESCE(
                        e.cash_amount_usd,
                        0
                    )

                    ELSE 0
                END
            ),
            0
        ) AS investment_cash_amount_usd,


        /*
         * ------------------------------------------------------
         * LOAN REPAYMENT
         * ------------------------------------------------------
         *
         * initial_loan_repayment_seed is excluded exactly as it
         * was in get_my_financial_periods().
         *
         * A seed adjusts the opening loan position. It is not a
         * current-period cash distribution.
         * ------------------------------------------------------
         */

        COALESCE(
            SUM(
                CASE
                    WHEN e.activity_type =
                         'loan_repayment'
                             ::public.financial_activity_type

                     AND e.transaction_type <>
                         'initial_loan_repayment_seed'

                    THEN COALESCE(
                        e.cash_amount,
                        0
                    )

                    ELSE 0
                END
            ),
            0
        ) AS repayment_cash_amount,

        COALESCE(
            SUM(
                CASE
                    WHEN e.activity_type =
                         'loan_repayment'
                             ::public.financial_activity_type

                     AND e.transaction_type <>
                         'initial_loan_repayment_seed'

                    THEN COALESCE(
                        e.cash_amount_usd,
                        0
                    )

                    ELSE 0
                END
            ),
            0
        ) AS repayment_cash_amount_usd


    FROM public.financial_pot_event AS e

    GROUP BY
        e.user_id,
        lower(e.country_code),
        lower(e.currency_code),
        e.fiscal_year,
        e.period
)


/*
 * ==============================================================
 * UPDATE FINANCIAL POT
 * ==============================================================
 */

UPDATE public.financial_pot AS fp

SET
    withdrawal_cash_amount =
        et.withdrawal_cash_amount,

    withdrawal_cash_amount_usd =
        et.withdrawal_cash_amount_usd,


    spending_cash_amount =
        et.spending_cash_amount,

    spending_cash_amount_usd =
        et.spending_cash_amount_usd,


    investment_cash_amount =
        et.investment_cash_amount,

    investment_cash_amount_usd =
        et.investment_cash_amount_usd,


    repayment_cash_amount =
        et.repayment_cash_amount,

    repayment_cash_amount_usd =
        et.repayment_cash_amount_usd,

    updated_at = now()

FROM event_totals AS et

WHERE et.user_id =
      fp.user_id

  AND et.country_code =
      lower(fp.country_code)

  AND et.currency_code =
      lower(fp.currency_code)

  AND et.fiscal_year =
      fp.fiscal_year

  AND et.period =
      fp.period;


COMMIT;