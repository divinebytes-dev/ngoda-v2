CREATE OR REPLACE FUNCTION public.resolve_principal_mode(p_transaction_type "TransactionType")
 RETURNS "PrincipalMode"
 LANGUAGE plpgsql
 IMMUTABLE PARALLEL SAFE STRICT
AS $function$
declare
    v_principal_mode text;
begin
    v_principal_mode :=
        case
            /*
             * Gross mode:
             *
             * Principal debit includes charges while the
             * principal credit remains the base amount.
             */
            when p_transaction_type in (
                'cash_transfer'::public."TransactionType",
                'cash_withdrawal'::public."TransactionType",
                'merchant_payment'::public."TransactionType",
                'gold_token_transfer'::public."TransactionType",
                'gold_token_buy_sub_tx'::public."TransactionType",
                'credit_agent_cash_withdrawal'::public."TransactionType",
                'loan_liquidation'::public."TransactionType"
            )
            then
                'gross'

            /*
             * Neutral mode:
             *
             * Principal debit and credit are equal.
             * These transactions must not add ordinary
             * non-self-balancing charges.
             */
            when p_transaction_type in (
                'external_funding'::public."TransactionType",
                'treasury_funding'::public."TransactionType",
                'agent_deposit'::public."TransactionType",
                'agent_funding'::public."TransactionType",
                'credit_agent_funding'::public."TransactionType",
                'credit_agent_cash_deposit'::public."TransactionType",
                'credit_agent_cash_settlement'::public."TransactionType",
                'credit_agent_settlement'::public."TransactionType",
                'cash_deposit'::public."TransactionType",
                'merchant_withdrawal'::public."TransactionType",
                'gold_inventory_purchase'::public."TransactionType",
                'gold_inventory_sell'::public."TransactionType",
                'gold_token_mint'::public."TransactionType",
                'gold_token_burn'::public."TransactionType",
                'loan_liquidation_sub_tx'::public."TransactionType",
                'agent_commission_settlement'::public."TransactionType",
                'merchant_commission_settlement'::public."TransactionType",
                'referral_commission_settlement'::public."TransactionType",
                'government_tax_clearing'::public."TransactionType",
                'agent_settlement'::public."TransactionType",
                'agent_settlement_sub_tx'::public."TransactionType"
            )
            then
                'neutral'

            /*
             * Net mode:
             *
             * Charges are deducted from the principal credit.
             *
             * Example customer direct deposit:
             *
             * Amount: 500
             * Fee:      6
             *
             * Principal Dr 500 / Cr 494
             * Fee                 Cr   6
             */
            when p_transaction_type in (
                'customer_direct_deposit'::public."TransactionType",
                'gold_token_buy'::public."TransactionType",
                'gold_token_sell'::public."TransactionType",
                'gold_token_sell_sub_tx'::public."TransactionType",
                'loan_disbursement'::public."TransactionType",
                'loan_repayment'::public."TransactionType"
            )
            then
                'net'

            /*
             * Charges-only mode.
             */
            when p_transaction_type =
                 'loan_interest_accrual'::public."TransactionType"
            then
                'charges'

            else
                null
        end;

    if v_principal_mode is null then
        raise exception
            'PRINCIPAL_MODE_NOT_DEFINED_%',
            p_transaction_type;
    end if;

    return
        v_principal_mode::public."PrincipalMode";
end;
$function$
