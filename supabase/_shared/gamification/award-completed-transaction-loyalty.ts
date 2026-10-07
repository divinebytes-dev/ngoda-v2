import type {
  SupabaseClient,
} from "jsr:@supabase/supabase-js@2";

import {
  awardLoyaltyPoints,
} from "./award-loyalty-points.ts";

import type {
  LoyaltyAwardResult,
} from "../types/loyalty-award.ts";

import type {
  LoyaltyEarningEventType,
} from "../types/loyalty-event-type.ts";


const TRANSACTION_EVENT_TYPES: Readonly<
  Record<string, LoyaltyEarningEventType>
> = {
  cash_transfer: "user_transfer",
  cash_deposit: "user_deposit",
  credit_agent_cash_deposit: "user_deposit",
  customer_direct_deposit: "user_deposit",
  merchant_payment: "merchant_payment",
  gold_token_buy: "gold_token_buy",
  loan_repayment: "loan_repayment",
};


export type CompletedTransactionLoyaltyInput = {
  transactionType: string;
  userId: string;
  reference: string;
  sourceTransactionId?: string | null;
  amount: string;
  amountUsd: string;
  countryCode: string;
  currencyCode: string;
  metadata?: Record<string, unknown>;
};


export type TransactionLoyaltyOutcome =
  | {
    status: "skipped";
    reason: "TRANSACTION_NOT_LOYALTY_ELIGIBLE";
  }
  | {
    status: "completed" | "ignored";
    result: LoyaltyAwardResult;
  }
  | {
    status: "failed";
    error: string;
  };


function normalizeCode(value: string): string {
  return value.trim().toLowerCase();
}


function errorMessage(error: unknown): string {
  return error instanceof Error
    ? error.message
    : String(error);
}


/**
 * Publishes loyalty only after the caller's financial transaction has
 * committed successfully.
 *
 * The caller supplies the authoritative beneficiary. Never take userId,
 * amountUsd, or transactionType directly from the mobile request body.
 */
export async function awardCompletedTransactionLoyalty(
  supabase: SupabaseClient,
  input: CompletedTransactionLoyaltyInput,
): Promise<TransactionLoyaltyOutcome> {
  const transactionType =
    normalizeCode(input.transactionType);

  const eventType =
    TRANSACTION_EVENT_TYPES[transactionType];

  if (!eventType) {
    return {
      status: "skipped",
      reason: "TRANSACTION_NOT_LOYALTY_ELIGIBLE",
    };
  }

  try {
    const result = await awardLoyaltyPoints(
      supabase,
      {
        idempotencyKey:
          `loyalty:${eventType}:${input.reference}`,
        eventType,
        userId: input.userId,
        sourceReference: input.reference,
        sourceTransactionId:
          input.sourceTransactionId ?? null,
        transactionType,
        amount: input.amount,
        amountUsd: input.amountUsd,
        countryCode:
          normalizeCode(input.countryCode),
        currencyCode:
          normalizeCode(input.currencyCode),
        metadata: {
          ...input.metadata,
          publisher: transactionType,
        },
      },
    );

    return {
      status:
        result.event_status === "ignored"
          ? "ignored"
          : "completed",
      result,
    };
  } catch (error) {
    const message = errorMessage(error);

    console.error(
      "TRANSACTION_LOYALTY_AWARD_FAILED",
      {
        transactionType,
        reference: input.reference,
        userId: input.userId,
        error: message,
      },
    );

    /*
     * The money movement is already committed. Returning a separate loyalty
     * failure prevents the API from reporting the financial transaction as
     * failed. Recalling this helper is safe because its key is idempotent.
     */
    return {
      status: "failed",
      error: message,
    };
  }
}


export function loyaltyEventTypeForTransaction(
  transactionType: string,
): LoyaltyEarningEventType | null {
  return TRANSACTION_EVENT_TYPES[
    normalizeCode(transactionType)
  ] ?? null;
}
