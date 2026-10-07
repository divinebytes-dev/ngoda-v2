import {
  errorResponse,
  successResponse,
} from "../../_shared/api-response.ts";

import {
  createSupabaseClient,
} from "../../_shared/supabase-client.ts";

import {
  AppError,
} from "../../_shared/app-error.ts";


type SettleAgentCommissionBatchBody = {
  batch_id?: unknown;
};


function parseRequiredString(
  value: unknown,
  errorMessage: string,
): string {
  if (
    typeof value !== "string" ||
    value.trim() === ""
  ) {
    throw new AppError(
      errorMessage,
      400,
    );
  }

  return value.trim();
}


Deno.serve(async (request: Request) => {
  try {
    if (request.method !== "POST") {
      throw new AppError(
        "METHOD_NOT_ALLOWED",
        405,
      );
    }

    let body:
      SettleAgentCommissionBatchBody;

    try {
      body =
        await request.json();
    } catch {
      throw new AppError(
        "INVALID_REQUEST_BODY",
        400,
      );
    }

    const batchId =
      parseRequiredString(
        body.batch_id,
        "BATCH_ID_REQUIRED",
      );

    const ipAddress =
      request.headers
        .get("x-forwarded-for")
        ?.split(",")[0]
        ?.trim() ??
      request.headers
        .get("x-real-ip")
        ?.trim() ??
      "unknown";

    /*
     * The authenticated RPC derives the Accounts user
     * and country from auth.uid().
     */
    const supabase =
      createSupabaseClient(request);

    const {
      data,
      error,
    } = await supabase.rpc(
      "execute_my_agent_commission_settlement_batch",
      {
        p_batch_id:
          batchId,

        p_ip_address:
          ipAddress,
      },
    );

    if (error) {
      console.error(
        "SETTLE_AGENT_COMMISSION_BATCH_RPC_FAILED",
        {
          code:
            error.code,

          message:
            error.message,

          details:
            error.details,

          hint:
            error.hint,

          batchId,
        },
      );

      throw new AppError(
        error.message ||
          "POST_SETTLEMENT_FAILED",
      );
    }

    if (!data) {
      throw new AppError(
        "AGENT_COMMISSION_SETTLEMENT_RESULT_NOT_FOUND",
      );
    }

    return successResponse(
      data,
    );
  } catch (error) {
    console.error(
      "SETTLE_AGENT_COMMISSION_BATCH_ERROR",
      {
        error:
          error instanceof Error
            ? error.message
            : String(error),
      },
    );

    return errorResponse(
      error,
      "POST_SETTLEMENT_FAILED",
    );
  }
});