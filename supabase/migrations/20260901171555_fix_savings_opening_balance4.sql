BEGIN;


/*
 * ==============================================================
 * BACKFILL FINANCIAL POT MONEY-SOURCE SNAPSHOTS
 * ==============================================================
 *
 * Source:
 *     public.financial_pot_event
 *
 * Target:
 *     public.financial_pot
 *
 * Snapshot fields:
 *
 *     cash_in_amount
 *     cash_in_amount_usd
 *
 *     transfer_in_amount
 *     transfer_in_amount_usd
 *
 *     investment_proceeds_amount
 *     investment_proceeds_amount_usd
 *
 * This is a ONE-TIME historical rebuild.
 *
 * After this migration, record_financial_activity() maintains
 * these values incrementally for every new transaction.
 * ==============================================================
 */


/*
 * First reset the snapshot fields.
 *
 * This makes the migration repeatable. If it is run again, values
 * will be rebuilt from the event history instead of being added
 * again.
 */
UPDATE public.financial_pot
SET
    cash_in_amount = 0,
    cash_in_amount_usd = 0,

    transfer_in_amount = 0,
    transfer_in_amount_usd = 0,

    investment_proceeds_amount = 0,
    investment_proceeds_amount_usd = 0;


/*
 * ==============================================================
 * AGGREGATE HISTORICAL EVENTS
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
         * CASH IN
         * ------------------------------------------------------
         *
         * These are direct cash/deposit sources.
         *
         * cash_transfer is deliberately excluded because it has
         * its own transfer_in snapshot.
         * ------------------------------------------------------
         */

        COALESCE(
            SUM(
                CASE
                    WHEN e.activity_type =
                         'deposit'::public.financial_activity_type

                     AND lower(e.transaction_type) IN (
                         'cash_deposit',
                         'credit_agent_cash_deposit',
                         'customer_direct_deposit'
                     )

                    THEN COALESCE(
                        e.cash_amount,
                        0
                    )

                    ELSE 0
                END
            ),
            0
        ) AS cash_in_amount,

        COALESCE(
            SUM(
                CASE
                    WHEN e.activity_type =
                         'deposit'::public.financial_activity_type

                     AND lower(e.transaction_type) IN (
                         'cash_deposit',
                         'credit_agent_cash_deposit',
                         'customer_direct_deposit'
                     )

                    THEN COALESCE(
                        e.cash_amount_usd,
                        0
                    )

                    ELSE 0
                END
            ),
            0
        ) AS cash_in_amount_usd,


        /*
         * ------------------------------------------------------
         * TRANSFER IN
         * ------------------------------------------------------
         *
         * Only the receiving side of cash_transfer is recorded
         * here because its activity type is deposit.
         * ------------------------------------------------------
         */

        COALESCE(
            SUM(
                CASE
                    WHEN e.activity_type =
                         'deposit'::public.financial_activity_type

                     AND lower(e.transaction_type) =
                         'cash_transfer'

                    THEN COALESCE(
                        e.cash_amount,
                        0
                    )

                    ELSE 0
                END
            ),
            0
        ) AS transfer_in_amount,

        COALESCE(
            SUM(
                CASE
                    WHEN e.activity_type =
                         'deposit'::public.financial_activity_type

                     AND lower(e.transaction_type) =
                         'cash_transfer'

                    THEN COALESCE(
                        e.cash_amount_usd,
                        0
                    )

                    ELSE 0
                END
            ),
            0
        ) AS transfer_in_amount_usd,


        /*
         * ------------------------------------------------------
         * INVESTMENT PROCEEDS
         * ------------------------------------------------------
         *
         * Cash returned into savings when an investment is sold.
         *
         * This currently represents gold sell activity through
         * investment_sell.
         * ------------------------------------------------------
         */

        COALESCE(
            SUM(
                CASE
                    WHEN e.activity_type =
                         'investment_sell'
                             ::public.financial_activity_type

                    THEN COALESCE(
                        e.cash_amount,
                        0
                    )

                    ELSE 0
                END
            ),
            0
        ) AS investment_proceeds_amount,

        COALESCE(
            SUM(
                CASE
                    WHEN e.activity_type =
                         'investment_sell'
                             ::public.financial_activity_type

                    THEN COALESCE(
                        e.cash_amount_usd,
                        0
                    )

                    ELSE 0
                END
            ),
            0
        ) AS investment_proceeds_amount_usd

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
 * UPDATE FINANCIAL POT SNAPSHOTS
 * ==============================================================
 */

UPDATE public.financial_pot AS fp

SET
    cash_in_amount =
        et.cash_in_amount,

    cash_in_amount_usd =
        et.cash_in_amount_usd,

    transfer_in_amount =
        et.transfer_in_amount,

    transfer_in_amount_usd =
        et.transfer_in_amount_usd,

    investment_proceeds_amount =
        et.investment_proceeds_amount,

    investment_proceeds_amount_usd =
        et.investment_proceeds_amount_usd,

    updated_at = now()

FROM event_totals AS et

WHERE et.user_id = fp.user_id

  AND et.country_code =
      lower(fp.country_code)

  AND et.currency_code =
      lower(fp.currency_code)

  AND et.fiscal_year =
      fp.fiscal_year

  AND et.period =
      fp.period;


COMMIT;