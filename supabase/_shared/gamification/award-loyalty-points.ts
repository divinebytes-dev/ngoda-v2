import type {
  SupabaseClient,
} from "jsr:@supabase/supabase-js@2";

import {
  AppError,
} from "../app-error.ts";

import type {
  LoyaltyAwardResult,
  ParsedAwardLoyaltyPointsRequest,
} from "../types/loyalty-award.ts";


export async function awardLoyaltyPoints(
  supabase: SupabaseClient,
  request: ParsedAwardLoyaltyPointsRequest,
): Promise<LoyaltyAwardResult> {
  const {
    data,
    error,
  } = await supabase.rpc(
    "award_loyalty_points",
    {
      p_idempotency_key:
        request.idempotencyKey,

      p_event_type:
        request.eventType,

      p_user_id:
        request.userId,

      p_source_reference:
        request.sourceReference,

      p_source_transaction_id:
        request.sourceTransactionId,

      p_transaction_type:
        request.transactionType,

      p_amount:
        request.amount,

      p_amount_usd:
        request.amountUsd,

      p_country_code:
        request.countryCode,

      p_currency_code:
        request.currencyCode,

      p_metadata:
        request.metadata,
    },
  );

  if (error) {
    console.error(
      "AWARD_LOYALTY_POINTS_RPC_FAILED",
      {
        code:
          error.code,

        message:
          error.message,

        details:
          error.details,

        hint:
          error.hint,

        eventType:
          request.eventType,

        userId:
          request.userId,

        sourceReference:
          request.sourceReference,
      },
    );

    throw new AppError(
      error.message ||
        "AWARD_LOYALTY_POINTS_FAILED",
    );
  }

  if (
    data === null ||
    typeof data !== "object" ||
    Array.isArray(data)
  ) {
    throw new AppError(
      "INVALID_AWARD_LOYALTY_POINTS_RESULT",
    );
  }

  return data as LoyaltyAwardResult;
}

