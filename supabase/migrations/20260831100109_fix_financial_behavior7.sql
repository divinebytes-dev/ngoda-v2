BEGIN;

DO $$
DECLARE
    v_event_count integer;
    v_pot_count integer;
BEGIN

    -- ==========================================================
    -- 1. Correct the historical Financial Intelligence event
    --
    -- Business/activity amount remains 0.500000.
    -- Actual wallet cash movement was 0.510000.
    -- ==========================================================

    UPDATE public.financial_pot_event
    SET
        cash_amount = 0.510000,
        cash_amount_usd = 0.510000
    WHERE id = '89291705-6876-44fc-88cb-4cf27f349ef8'::uuid
      AND reference = '03dfea98-d8e8-4334-b418-5ccbd43ef1eb'
      AND user_id = '5db37d7e-260a-4392-aec6-0ef7852b1e03'
      AND currency_code = 'usd'
      AND fiscal_year = 2026
      AND period = 8
      AND transaction_type = 'merchant_payment'
      AND activity_type =
          'spending'::public.financial_activity_type
      AND amount = 0.500000
      AND amount_usd = 0.500000
      AND cash_amount = 0
      AND cash_amount_usd = 0;

    GET DIAGNOSTICS v_event_count = ROW_COUNT;

    IF v_event_count <> 1 THEN
        RAISE EXCEPTION
            'Expected to update exactly 1 financial_pot_event row, updated %',
            v_event_count;
    END IF;


    -- ==========================================================
    -- 2. Correct the USD financial pot
    --
    -- Do NOT change spending_amount.
    --
    -- spending_amount = behavioral/business spending = 0.500000
    --
    -- savings_outflow reflects actual wallet cash movement,
    -- therefore add 0.510000.
    -- ==========================================================

    UPDATE public.financial_pot
    SET
        savings_outflow =
            savings_outflow + 0.510000,

        savings_outflow_usd =
            savings_outflow_usd + 0.510000,

        saving_amount =
            saving_amount - 0.510000,

        saving_amount_usd =
            saving_amount_usd - 0.510000,

        closing_savings =
            closing_savings - 0.510000,

        closing_savings_usd =
            closing_savings_usd - 0.510000,

        updated_at = now()

    WHERE id =
        'b37b9bf8-750b-47d3-b01a-2aec9ed5deb1'::uuid

      AND user_id =
        '5db37d7e-260a-4392-aec6-0ef7852b1e03'

      AND country_code = 'zw'

      AND currency_code = 'usd'

      AND fiscal_year = 2026

      AND period = 8

      -- Safety checks against accidentally running this twice.
      AND savings_outflow = 21.889282
      AND savings_outflow_usd = 21.889282
      AND closing_savings = 67.032404
      AND closing_savings_usd = 67.029957;

    GET DIAGNOSTICS v_pot_count = ROW_COUNT;

    IF v_pot_count <> 1 THEN
        RAISE EXCEPTION
            'Expected to update exactly 1 financial_pot row, updated %',
            v_pot_count;
    END IF;

END;
$$;

COMMIT;