import {
  AppError,
} from "../../_shared/app-error.ts";

import {
  errorResponse,
  successResponse,
} from "../../_shared/api-response.ts";

import {
  createSupabaseClient,
} from "../../_shared/supabase-client.ts";


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


function isRecord(
  value: unknown,
): value is Record<string, unknown> {
  return typeof value === "object" &&
    value !== null &&
    !Array.isArray(value);
}


function sanitizeResult(
  value: unknown,
): unknown {
  if (!isRecord(value)) {
    return value;
  }

  /*
   * Device tokens and internal notification templates must
   * never be returned to the frontend.
   */
  const {
    device_tokens: _deviceTokens,
    notification: _notification,
    ...safeResult
  } = value;

  return safeResult;
}


Deno.serve(
  async (
    request: Request,
  ): Promise<Response> => {
    if (request.method !== "POST") {
      return errorResponse(
        "METHOD_NOT_ALLOWED",
      );
    }

    let blockchainTransactionId:
      string | null = null;

    let postingCommitted =
      false;

    try {
      const body =
        await request.json();

      blockchainTransactionId =
        typeof body.id === "string"
          ? body.id.trim()
          : "";

      if (!blockchainTransactionId) {
        return errorResponse(
          "BLOCKCHAIN_TRANSACTION_ID_REQUIRED",
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

      const supabase =
        createSupabaseClient(
          request,
        );

      const {
        data,
        error,
      } = await supabase.rpc(
        "process_my_incomplete_blockchain_transaction",
        {
          p_blockchain_transaction_id:
            blockchainTransactionId,

          p_ip_address:
            ipAddress,
        },
      );

      if (error) {
        console.error(
          "INCOMPLETE_BLOCKCHAIN_POSTING_RPC_FAILED",
          {
            code:
              error.code,

            message:
              error.message,

            details:
              error.details,

            hint:
              error.hint,

            blockchainTransactionId,
          },
        );

        throw new AppError(
          error.message,
        );
      }

      postingCommitted =
        true;

      const safeResult =
        sanitizeResult(data);

      console.log(
        "INCOMPLETE_BLOCKCHAIN_POSTING_COMPLETED",
        {
          blockchainTransactionId,
          postingCommitted,
        },
      );

      return successResponse(
        safeResult,
      );
    } catch (error) {
      const message =
        getErrorMessage(
          error,
        );

      console.error(
        "INCOMPLETE_BLOCKCHAIN_POSTING_ERROR",
        {
          blockchainTransactionId,
          postingCommitted,
          error:
            message,
        },
      );

      return errorResponse(
        message ||
          "FAILED_TO_PROCESS_INCOMPLETE_BLOCKCHAIN_TRANSACTION",
      );
    }
  },
);