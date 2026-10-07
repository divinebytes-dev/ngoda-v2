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

    /*
     * Same authenticated-client pattern used by
     * the working customer dashboard.
     */
    const authSupabase =
      createSupabaseClient(request);

    const {
      data: dashboard,
      error: dashboardError,
    } = await authSupabase.rpc(
      "build_my_accounts_dashboard",
    );

    if (dashboardError) {
      console.error(
        "Accounts dashboard RPC failed",
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
          "FAILED_TO_FETCH_ACCOUNTS_DASHBOARD",
      );
    }

    return successResponse(
      dashboard,
    );
  } catch (error) {
    console.error(
      "ACCOUNTS_DASHBOARD_ERROR",
      error,
    );

    return errorResponse(error);
  }
});