import {
  createSupabaseClient,
} from "../../_shared/supabase-client.ts";

import {
  errorResponse,
  successResponse,
} from "../../_shared/api-response.ts";

type AdjustmentAction =
  | "approve"
  | "reject";

const statusMap: Record<
  AdjustmentAction,
  "approved" | "rejected"
> = {
  approve: "approved",
  reject: "rejected",
};

function isAdjustmentAction(
  value: string,
): value is AdjustmentAction {
  return value === "approve" ||
    value === "reject";
}

function getErrorMessage(
  error: unknown,
): string {
  if (error instanceof Error) {
    return error.message;
  }

  if (
    typeof error === "object" &&
    error !== null &&
    "message" in error &&
    typeof error.message === "string"
  ) {
    return error.message;
  }

  return String(error);
}

Deno.serve(
  async (
    request: Request,
  ): Promise<Response> => {
    if (request.method !== "POST") {
      return errorResponse(
        "METHOD_NOT_ALLOWED"
      );
    }

    try {
      /*
       * Example:
       * token-adjustment-status/approve
       * token-adjustment-status/reject
       */
      const url =
        new URL(request.url);

      const pathSegments =
        url.pathname
          .split("/")
          .filter(Boolean);

      const rawAction =
        pathSegments.at(-1)
          ?.trim()
          .toLowerCase();

      if (
        !rawAction ||
        !isAdjustmentAction(rawAction)
      ) {
        return errorResponse(
          "INVALID_STATUS",
        );
      }

      const body =
        await request.json();

      const adjustmentRequestId =
        typeof body.adjustment_request_id ===
          "string"
          ? body.adjustment_request_id.trim()
          : "";

      if (!adjustmentRequestId) {
        return errorResponse(
          "ADJUSTMENT_REQUEST_ID_REQUIRED",
        );
      }

      const forwardedFor =
        request.headers.get(
          "x-forwarded-for",
        );

      const realIp =
        request.headers.get(
          "x-real-ip",
        );

      const ipAddress =
        forwardedFor ||
        realIp ||
        "unknown";

      const status =
        statusMap[rawAction];

      const supabase =
        createSupabaseClient(request);

      const {
        data,
        error,
      } = await supabase.rpc(
        "update_token_adjustment_request_status",
        {
          p_adjustment_request_id:
            adjustmentRequestId,

          p_status:
            status,

          p_ip_address:
            ipAddress,
        },
      );

      if (error) {
        console.error(
          "UPDATE_TOKEN_ADJUSTMENT_RPC_FAILED",
          {
            code:
              error.code,

            message:
              error.message,

            details:
              error.details,

            hint:
              error.hint,

            adjustmentRequestId,
            action:
              rawAction,

            status,
          },
        );

        return errorResponse(
          error.message,
        );
      }

      console.log(
        "TOKEN_ADJUSTMENT_STATUS_UPDATED",
        {
          adjustmentRequestId,
          action:
            rawAction,

          status,
        },
      );

      return successResponse(
        data,
      );
    } catch (error) {
      const message =
        getErrorMessage(error);

      console.error(
        "UPDATE_TOKEN_ADJUSTMENT_ERROR",
        {
          error:
            message,
        },
      );

      return errorResponse(
        message ||
          "FAILED_TO_UPDATE_ADJUSTMENT",
      );
    }
  },
);