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
      );
    }

    /*
     * The authenticated client passes the caller's JWT
     * to PostgreSQL. The RPC allows agent, vendor and
     * merchant roles.
     */
    const supabase =
      createSupabaseClient(request);

    const {
      data,
      error,
    } = await supabase.rpc(
      "fetch_my_agent_commission_summary",
    );

    if (error) {
      console.error(
        "AGENT_COMMISSION_SUMMARY_RPC_FAILED",
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
          "FAILED_TO_FETCH_COMMISSION",
      );
    }

    return successResponse(
      data ?? {},
    );
  } catch (error) {
    console.error(
      "AGENT_COMMISSION_SUMMARY_ERROR",
      {
        error:
          error instanceof Error
            ? error.message
            : String(error),
      },
    );

    return errorResponse(
      error,
      "FAILED_TO_FETCH_COMMISSION",
    );
  }
});