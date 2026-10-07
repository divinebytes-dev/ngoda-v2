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
    if (request.method !== "GET") {
      throw new AppError(
        "METHOD_NOT_ALLOWED",
        405,
      );
    }

    /*
     * The authenticated client forwards the administrator's
     * JWT to PostgreSQL.
     *
     * build_my_admin_dashboard validates the global Admin
     * role before returning data.
     */
    const supabase =
      createSupabaseClient(request);

    const {
      data,
      error,
    } = await supabase.rpc(
      "build_my_admin_dashboard",
    );

    if (error) {
      console.error(
        "ADMIN_DASHBOARD_RPC_FAILED",
        {
          code:
            error.code,

          message:
            error.message,

          details:
            error.details,

          hint:
            error.hint,
        },
      );

      throw new AppError(
        error.message ||
          "FAILED_TO_FETCH_ADMIN_DASHBOARD",
      );
    }

    if (
      data === null ||
      data === undefined
    ) {
      throw new AppError(
        "ADMIN_DASHBOARD_RESULT_NOT_FOUND",
      );
    }

    return successResponse(data);
  } catch (error) {
    return errorResponse(
      error,
      "FAILED_TO_FETCH_ADMIN_DASHBOARD",
    );
  }
});