import {
  errorResponse,
  successResponse,
} from "../../_shared/api-response.ts";

import {
  AppError,
} from "../../_shared/app-error.ts";

import {
  createSupabaseClient,
} from "../../_shared/supabase-client.ts";


Deno.serve(async (request: Request) => {
  try {
    if (request.method !== "GET") {
      throw new AppError(
        "METHOD_NOT_ALLOWED",
        405,
      );
    }

    const supabase =
      createSupabaseClient(request);

    const {
      data,
      error,
    } = await supabase.rpc(
      "fetch_my_cash_transfer_fee_configuration",
    );

    if (error) {
      console.error(
        "FETCH_CASH_TRANSFER_FEE_CONFIGURATION_RPC_FAILED",
        {
          code: error.code,
          message: error.message,
          details: error.details,
          hint: error.hint,
        },
      );

      throw new AppError(
        error.message ||
          "FETCH_CASH_TRANSFER_FEE_CONFIGURATION_FAILED",
      );
    }

    if (
      data === null ||
      typeof data !== "object" ||
      Array.isArray(data)
    ) {
      throw new AppError(
        "INVALID_CASH_TRANSFER_FEE_CONFIGURATION_RESULT",
      );
    }

    return successResponse(data);
  } catch (error) {
    console.error(
      "FETCH_CASH_TRANSFER_FEE_CONFIGURATION_ERROR",
      {
        error:
          error instanceof Error
            ? error.message
            : String(error),
      },
    );

    return errorResponse(
      error,
      "FETCH_CASH_TRANSFER_FEE_CONFIGURATION_FAILED",
    );
  }
});
