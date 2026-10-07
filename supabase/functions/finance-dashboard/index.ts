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

Deno.serve(async (request: Request) => {
  try {
    if (request.method !== "POST") {
      throw new AppError(
        "METHOD_NOT_ALLOWED",
      );
    }

    const authSupabase =
      createSupabaseClient(request);

    const {
      data: summary,
      error: summaryError,
    } = await authSupabase.rpc(
      "build_my_finance_dashboard",
    );

    if (summaryError) {
      console.error(
        "Finance dashboard RPC failed",
        {
          code: summaryError.code,
          message:
            summaryError.message,
          details:
            summaryError.details,
          hint:
            summaryError.hint,
        },
      );

      throw new AppError(
        summaryError.message ||
          "FAILED_TO_FETCH_RESERVE_SUMMARY",
      );
    }

    return successResponse(
      summary,
    );
  } catch (error) {
    console.error(
      "FINANCE_DASHBOARD_SUMMARY_ERROR",
      error,
    );

    return errorResponse(error);
  }
});