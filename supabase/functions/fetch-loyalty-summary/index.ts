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

import type {
  LoyaltySummary,
} from "../../_shared/types/loyalty-read.ts";


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
      "fetch_my_loyalty_summary",
    );

    if (error) {
      console.error(
        "FETCH_LOYALTY_SUMMARY_RPC_FAILED",
        {
          code: error.code,
          message: error.message,
          details: error.details,
          hint: error.hint,
        },
      );

      throw new AppError(
        error.message ||
          "FETCH_LOYALTY_SUMMARY_FAILED",
      );
    }

    if (
      data === null ||
      typeof data !== "object" ||
      Array.isArray(data)
    ) {
      throw new AppError(
        "INVALID_LOYALTY_SUMMARY_RESULT",
      );
    }

    return successResponse(
      data as LoyaltySummary,
    );
  } catch (error) {
    console.error(
      "FETCH_LOYALTY_SUMMARY_ERROR",
      {
        error:
          error instanceof Error
            ? error.message
            : String(error),
      },
    );

    return errorResponse(
      error,
      "FETCH_LOYALTY_SUMMARY_FAILED",
    );
  }
});

