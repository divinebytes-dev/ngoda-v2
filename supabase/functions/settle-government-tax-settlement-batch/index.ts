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


type SettleGovernmentTaxBatchBody = {
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
      SettleGovernmentTaxBatchBody;

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

    const supabase =
      createSupabaseClient(
        request,
      );

    const {
      data,
      error,
    } = await supabase.rpc(
      "execute_my_government_tax_settlement_batch",
      {
        p_batch_id:
          batchId,

        p_ip_address:
          ipAddress,
      },
    );

    if (error) {
      console.error(
        "SETTLE_GOVERNMENT_TAX_BATCH_RPC_FAILED",
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
          "INSUFFICIENT_TREASURY_WALLET_BALANCE",
        )
      ) {
        throw new AppError(
          error.message,
          409,
        );
      }

      throw new AppError(
        error.message ||
          "POST_GOVERNMENT_TAX_SETTLEMENT_FAILED",
      );
    }

    if (!data) {
      throw new AppError(
        "GOVERNMENT_TAX_SETTLEMENT_RESULT_NOT_FOUND",
      );
    }

    return successResponse(
      data,
    );
  } catch (error) {
    console.error(
      "SETTLE_GOVERNMENT_TAX_BATCH_ERROR",
      {
        error:
          error instanceof Error
            ? error.message
            : String(error),
      },
    );

    return errorResponse(
      error,
      "POST_GOVERNMENT_TAX_SETTLEMENT_FAILED",
    );
  }
});