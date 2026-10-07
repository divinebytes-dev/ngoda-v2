import type {
  SupabaseClient,
} from "jsr:@supabase/supabase-js@2";

import {
  AppError,
} from "../app-error.ts";

import type {
  LoyaltyReversalResult,
  ParsedReverseLoyaltyPointsRequest,
} from "../types/loyalty-award.ts";


export async function reverseLoyaltyPoints(
  supabase: SupabaseClient,
  request: ParsedReverseLoyaltyPointsRequest,
): Promise<LoyaltyReversalResult> {
  const {
    data,
    error,
  } = await supabase.rpc(
    "reverse_loyalty_points",
    {
      p_original_event_id:
        request.originalEventId,

      p_idempotency_key:
        request.idempotencyKey,

      p_source_reference:
        request.sourceReference,

      p_metadata:
        request.metadata,
    },
  );

  if (error) {
    console.error(
      "REVERSE_LOYALTY_POINTS_RPC_FAILED",
      {
        code:
          error.code,

        message:
          error.message,

        details:
          error.details,

        hint:
          error.hint,

        originalEventId:
          request.originalEventId,

        sourceReference:
          request.sourceReference,
      },
    );

    throw new AppError(
      error.message ||
        "REVERSE_LOYALTY_POINTS_FAILED",
    );
  }

  if (
    data === null ||
    typeof data !== "object" ||
    Array.isArray(data)
  ) {
    throw new AppError(
      "INVALID_REVERSE_LOYALTY_POINTS_RESULT",
    );
  }

  return data as LoyaltyReversalResult;
}

