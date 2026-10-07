import {
  errorResponse,
  successResponse,
} from "../../_shared/api-response.ts";

import {
  AppError,
} from "../../_shared/app-error.ts";

import {
  awardLoyaltyPoints,
} from "../../_shared/gamification/award-loyalty-points.ts";

import {
  parseAwardLoyaltyPointsRequest,
  parseJsonBody,
} from "../../_shared/gamification/request-parser.ts";

import {
  createSupabaseClient,
} from "../../_shared/supabase-client.ts";

import type {
  AwardLoyaltyPointsRequest,
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
        AwardLoyaltyPointsRequest;

    const parsedRequest =
      parseAwardLoyaltyPointsRequest(body);

    /*
     * This client forwards the incoming Authorization JWT.
     * PostgreSQL therefore receives service_role only when the
     * caller actually supplied a service-role token.
     */
    const supabase =
      createSupabaseClient(request);

    const result =
      await awardLoyaltyPoints(
        supabase,
        parsedRequest,
      );

    return successResponse(result);
  } catch (error) {
    console.error(
      "AWARD_LOYALTY_POINTS_ERROR",
      {
        error:
          error instanceof Error
            ? error.message
            : String(error),
      },
    );

    return errorResponse(
      error,
      "AWARD_LOYALTY_POINTS_FAILED",
    );
  }
});

