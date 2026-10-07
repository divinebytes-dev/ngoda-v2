// supabase/functions/_shared/financial-intelligence/
// record-financial-activity.ts

import {
  RecordFinancialActivityInput,
} from "../types/record-financial-activity-input.ts";


export type FinancialActivityOutcome =
  | {
      status: "completed";
    }
  | {
      status: "failed";
      error: string;
    };


export async function recordFinancialActivity(
  supabase: any,
  input: RecordFinancialActivityInput,
): Promise<FinancialActivityOutcome> {
  try {
    const {
      error,
    } = await supabase.rpc(
      "record_financial_activity",
      {
        p_reference:
          input.reference,

        p_user_id:
          input.userId,

        p_country_code:
          input.countryCode,

        p_currency_code:
          input.currencyCode,

        p_transaction_type:
          input.transactionType,

        p_activity_type:
          input.activityType,

        p_amount:
          input.amount,

        p_amount_usd:
          input.amountUsd,

        p_cash_amount:
          input.cashAmount ??
          "0.000000",

        p_cash_amount_usd:
          input.cashAmountUsd ??
          "0.000000",

        p_gold_quantity:
          input.goldQuantity ??
          "0.000000",

        p_investment_cost_usd:
          input.investmentCostUsd ??
          "0.000000",

        p_principal_amount:
          input.principalAmount ??
          "0.000000",

        p_principal_amount_usd:
          input.principalAmountUsd ??
          "0.000000",

        p_interest_amount:
          input.interestAmount ??
          "0.000000",

        p_interest_amount_usd:
          input.interestAmountUsd ??
          "0.000000",
      },
    );

    if (error) {
      console.error(
        "RECORD_FINANCIAL_ACTIVITY_FAILED",
        {
          reference:
            input.reference,

          userId:
            input.userId,

          transactionType:
            input.transactionType,

          activityType:
            input.activityType,

          code:
            error.code,

          message:
            error.message,

          details:
            error.details,

          hint:
            error.hint,
        },
      );

      return {
        status: "failed",

        error:
          error.message ||
          "RECORD_FINANCIAL_ACTIVITY_FAILED",
      };
    }

    return {
      status: "completed",
    };
  } catch (error) {
    /*
     * Financial Intelligence is a secondary
     * post-transaction process.
     *
     * An unexpected exception here must never
     * propagate back to the completed financial
     * transaction.
     */
    console.error(
      "RECORD_FINANCIAL_ACTIVITY_EXCEPTION",
      {
        reference:
          input.reference,

        userId:
          input.userId,

        transactionType:
          input.transactionType,

        activityType:
          input.activityType,

        error:
          error instanceof Error
            ? error.message
            : String(error),
      },
    );

    return {
      status: "failed",

      error:
        error instanceof Error
          ? error.message
          : "RECORD_FINANCIAL_ACTIVITY_FAILED",
    };
  }
}