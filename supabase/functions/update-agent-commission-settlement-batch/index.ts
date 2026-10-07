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


type UpdateSettlementBatchBody = {
  batch_id?: unknown;
  action?: unknown;
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
      UpdateSettlementBatchBody;

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
        "SETTLEMENT_BATCH_ID_REQUIRED",
      );

    const action =
      parseRequiredString(
        body.action,
        "SETTLEMENT_ACTION_REQUIRED",
      ).toLowerCase();

    if (
      action !== "approve" &&
      action !== "cancel"
    ) {
      throw new AppError(
        "INVALID_SETTLEMENT_ACTION",
        400,
      );
    }

    const supabase =
      createSupabaseClient(request);

    const {
      data,
      error: rpcError,
    } = await supabase.rpc(
      "update_my_agent_commission_settlement_batch",
      {
        p_batch_id:
          batchId,

        p_action:
          action,
      },
    );

    if (rpcError) {
      console.error(
        "UPDATE_AGENT_COMMISSION_SETTLEMENT_BATCH_RPC_FAILED",
        {
          code:
            rpcError.code,

          message:
            rpcError.message,

          details:
            rpcError.details,

          hint:
            rpcError.hint,

          batchId,
          action,
        },
      );

      if (rpcError.code === "42501") {
        throw new AppError(
          rpcError.message || "FORBIDDEN",
          403,
        );
      }

      if (
        rpcError.message.includes(
          "AGENT_COMMISSION_SETTLEMENT_BATCH_NOT_FOUND",
        )
      ) {
        throw new AppError(
          "AGENT_COMMISSION_SETTLEMENT_BATCH_NOT_FOUND",
          404,
        );
      }

      if (
        rpcError.message.includes(
          "INVALID_AGENT_COMMISSION_BATCH_STATUS",
        ) ||
        rpcError.message.includes(
          "AGENT_COMMISSION_BATCH_PAYMENT_ALREADY_STARTED",
        ) ||
        rpcError.message.includes(
          "SETTLED_AGENT_COMMISSION_CANNOT_BE_CANCELLED",
        )
      ) {
        throw new AppError(
          "INVALID_AGENT_COMMISSION_SETTLEMENT_STATUS",
          409,
        );
      }

      throw new AppError(
        rpcError.message ||
          "AGENT_COMMISSION_SETTLEMENT_UPDATE_FAILED",
      );
    }

    if (!data) {
      throw new AppError(
        "AGENT_COMMISSION_SETTLEMENT_UPDATE_RESULT_NOT_FOUND",
        500,
      );
    }

    return successResponse(
      data,
    );
  } catch (error) {
    console.error(
      "UPDATE_AGENT_COMMISSION_SETTLEMENT_BATCH_ERROR",
      {
        error:
          error instanceof Error
            ? error.message
            : String(error),
      },
    );

    return errorResponse(
      error,
      "AGENT_COMMISSION_SETTLEMENT_UPDATE_FAILED",
    );
  }
});