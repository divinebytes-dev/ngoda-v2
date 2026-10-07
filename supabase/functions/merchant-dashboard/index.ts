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
      data: dashboard,
      error: dashboardError,
    } = await authSupabase.rpc(
      "build_my_merchant_dashboard",
    );

    if (dashboardError) {
      console.error(
        "Merchant dashboard RPC failed",
        {
          code: dashboardError.code,
          message:
            dashboardError.message,
          details:
            dashboardError.details,
          hint:
            dashboardError.hint,
        },
      );

      throw new AppError(
        dashboardError.message ||
          "FAILED_TO_FETCH_MERCHANT_DASHBOARD",
      );
    }

    return successResponse(
      dashboard,
    );
  } catch (error) {
    console.error(
      "MERCHANT_DASHBOARD_ERROR",
      error,
    );

    return errorResponse(error);
  }
});