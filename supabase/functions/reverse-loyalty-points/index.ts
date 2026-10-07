import {
  errorResponse,
  successResponse,
} from "../../_shared/api-response.ts";

import {
  AppError,
} from "../../_shared/app-error.ts";

import {
  parseJsonBody,
  parseReverseLoyaltyPointsRequest,
} from "../../_shared/gamification/request-parser.ts";

import {
  reverseLoyaltyPoints,
} from "../../_shared/gamification/reverse-loyalty-points.ts";

import {
  createSupabaseClient,
} from "../../_shared/supabase-client.ts";

import type {
  ReverseLoyaltyPointsRequest,
} from "../../_shared/types/loyalty-award.ts";


Deno.serve(async (request: Request) => {
  try {
    if (request.method !== "POST") {
      throw new AppError(
        "METHOD_NOT_ALLOWED",
        405,
      );
    }

    const body =
      await parseJsonBody(request) as
        ReverseLoyaltyPointsRequest;

    const parsedRequest =
      parseReverseLoyaltyPointsRequest(body);

    const supabase =
      createSupabaseClient(request);

    const result =
      await reverseLoyaltyPoints(
        supabase,
        parsedRequest,
      );

    return successResponse(result);
  } catch (error) {
    console.error(
      "REVERSE_LOYALTY_POINTS_ERROR",
      {
        error:
          error instanceof Error
            ? error.message
            : String(error),
      },
    );

    return errorResponse(
      error,
      "REVERSE_LOYALTY_POINTS_FAILED",
    );
  }
});

