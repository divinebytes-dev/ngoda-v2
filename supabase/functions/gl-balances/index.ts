// supabase/functions/gl-balances/index.ts

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

    const authSupabase =
      createSupabaseClient(request);

    const {
      data,
      error,
    } = await authSupabase.rpc(
      "fetch_my_current_gl_balances",
    );

    if (error) {
      console.error(
        "Current GL balances RPC failed",
        {
          code: error.code,
          message: error.message,
          details: error.details,
          hint: error.hint,
        },
      );

      throw new AppError(
        error.message ||
          "FAILED_TO_FETCH_GL_BALANCES",
      );
    }

    return successResponse(
      data ?? {
        fiscalYear: 0,
        period: 0,
        totals: {},
        data: {},
      },
    );
  } catch (error) {
    console.error(
      "CURRENT_GL_BALANCES_ERROR",
      {
        error:
          error instanceof Error
            ? error.message
            : String(error),
      },
    );

    return errorResponse(
      error,
      "FAILED_TO_FETCH_GL_BALANCES",
    );
  }
});