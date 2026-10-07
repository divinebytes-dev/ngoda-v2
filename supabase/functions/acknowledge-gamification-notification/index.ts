import {
  errorResponse,
  successResponse,
} from "../../_shared/api-response.ts";

import {
  AppError,
} from "../../_shared/app-error.ts";

import {
  parseJsonBody,
} from "../../_shared/gamification/request-parser.ts";

import {
  parseAcknowledgeNotificationRequest,
} from "../../_shared/gamification/read-request-parser.ts";

import {
  createSupabaseClient,
} from "../../_shared/supabase-client.ts";

import type {
  AcknowledgeGamificationNotificationRequest,
  AcknowledgeGamificationNotificationResult,
} from "../../_shared/types/loyalty-read.ts";


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
        AcknowledgeGamificationNotificationRequest;

    const parsedRequest =
      parseAcknowledgeNotificationRequest(body);

    const supabase =
      createSupabaseClient(request);

    const {
      data,
      error,
    } = await supabase.rpc(
      "acknowledge_my_gamification_notification",
      {
        p_notification_id:
          parsedRequest.notificationId,

        p_mark_seen:
          parsedRequest.markSeen,
      },
    );

    if (error) {
      console.error(
        "ACKNOWLEDGE_GAMIFICATION_NOTIFICATION_RPC_FAILED",
        {
          code: error.code,
          message: error.message,
          details: error.details,
          hint: error.hint,
          notificationId:
            parsedRequest.notificationId,
        },
      );

      throw new AppError(
        error.message ||
          "ACKNOWLEDGE_GAMIFICATION_NOTIFICATION_FAILED",
      );
    }

    if (
      data === null ||
      typeof data !== "object" ||
      Array.isArray(data)
    ) {
      throw new AppError(
        "INVALID_GAMIFICATION_NOTIFICATION_ACKNOWLEDGEMENT",
      );
    }

    return successResponse(
      data as AcknowledgeGamificationNotificationResult,
    );
  } catch (error) {
    console.error(
      "ACKNOWLEDGE_GAMIFICATION_NOTIFICATION_ERROR",
      {
        error:
          error instanceof Error
            ? error.message
            : String(error),
      },
    );

    return errorResponse(
      error,
      "ACKNOWLEDGE_GAMIFICATION_NOTIFICATION_FAILED",
    );
  }
});

