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


type UpdateGovernmentTaxSettlementBody = {
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
      UpdateGovernmentTaxSettlementBody;

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
      createSupabaseClient(
        request,
      );

    const {
      data,
      error,
    } = await supabase.rpc(
      "update_my_government_tax_settlement_batch",
      {
        p_batch_id:
          batchId,

        p_action:
          action,
      },
    );

    if (error) {
      console.error(
        "UPDATE_GOVERNMENT_TAX_SETTLEMENT_BATCH_RPC_FAILED",
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
          action,
        },
      );

      if (
        error.message.includes(
          "GOVERNMENT_TAX_SETTLEMENT_BATCH_NOT_FOUND",
        )
      ) {
        throw new AppError(
          "GOVERNMENT_TAX_SETTLEMENT_BATCH_NOT_FOUND",
          404,
        );
      }

      if (
        error.message.includes(
          "CREATOR_AND_APPROVER_MUST_BE_DIFFERENT",
        )
      ) {
        throw new AppError(
          "CREATOR_AND_APPROVER_MUST_BE_DIFFERENT",
          409,
        );
      }

      throw new AppError(
        error.message ||
          "UPDATE_GOVERNMENT_TAX_SETTLEMENT_BATCH_FAILED",
      );
    }

    if (!data) {
      throw new AppError(
        "GOVERNMENT_TAX_SETTLEMENT_UPDATE_RESULT_NOT_FOUND",
      );
    }

    return successResponse(
      data,
    );
  } catch (error) {
    console.error(
      "UPDATE_GOVERNMENT_TAX_SETTLEMENT_BATCH_ERROR",
      {
        error:
          error instanceof Error
            ? error.message
            : String(error),
      },
    );

    return errorResponse(
      error,
      "UPDATE_GOVERNMENT_TAX_SETTLEMENT_BATCH_FAILED",
    );
  }
});