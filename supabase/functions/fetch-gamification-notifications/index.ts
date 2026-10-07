import {
  errorResponse,
  successResponse,
} from "../../_shared/api-response.ts";

import {
  AppError,
} from "../../_shared/app-error.ts";

import {
  parsePositiveInteger,
} from "../../_shared/gamification/read-request-parser.ts";

import {
  createSupabaseClient,
} from "../../_shared/supabase-client.ts";

import type {
  GamificationNotificationFeed,
} from "../../_shared/types/loyalty-read.ts";


Deno.serve(async (request: Request) => {
  try {
    if (request.method !== "GET") {
      throw new AppError(
        "METHOD_NOT_ALLOWED",
        405,
      );
    }

    const url =
      new URL(request.url);

    const limit =
      parsePositiveInteger(
        url.searchParams.get("limit"),
        20,
        "INVALID_NOTIFICATION_LIMIT",
        50,
      );

    const supabase =
      createSupabaseClient(request);

    const {
      data,
      error,
    } = await supabase.rpc(
      "fetch_my_gamification_notifications",
      {
        p_limit: limit,
      },
    );

    if (error) {
      console.error(
        "FETCH_GAMIFICATION_NOTIFICATIONS_RPC_FAILED",
        {
          code: error.code,
          message: error.message,
          details: error.details,
          hint: error.hint,
          limit,
        },
      );

      throw new AppError(
        error.message ||
          "FETCH_GAMIFICATION_NOTIFICATIONS_FAILED",
      );
    }

    if (
      data === null ||
      typeof data !== "object" ||
      Array.isArray(data)
    ) {
      throw new AppError(
        "INVALID_GAMIFICATION_NOTIFICATIONS_RESULT",
      );
    }

    return successResponse(
      data as GamificationNotificationFeed,
    );
  } catch (error) {
    console.error(
      "FETCH_GAMIFICATION_NOTIFICATIONS_ERROR",
      {
        error:
          error instanceof Error
            ? error.message
            : String(error),
      },
    );

    return errorResponse(
      error,
      "FETCH_GAMIFICATION_NOTIFICATIONS_FAILED",
    );
  }
});

