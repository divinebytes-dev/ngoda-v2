import {
  AppError,
} from "../../_shared/app-error.ts";

import {
  errorResponse,
  successResponse,
} from "../../_shared/api-response.ts";

import {
  createSupabaseClient,
} from "../../_shared/supabase-client.ts";


function getErrorMessage(
  error: unknown,
): string {
  if (error instanceof Error) {
    return error.message;
  }

  if (
    typeof error === "object" &&
    error !== null &&
    "message" in error &&
    typeof error.message === "string"
  ) {
    return error.message;
  }

  return String(error);
}


Deno.serve(
  async (
    request: Request,
  ): Promise<Response> => {
    if (request.method !== "GET") {
      return errorResponse(
        "METHOD_NOT_ALLOWED",
      );
    }

    try {
      const supabase =
        createSupabaseClient(
          request,
        );

      const {
        data,
        error,
      } = await supabase.rpc(
        "fetch_my_current_token_gl_balance",
      );

      if (error) {
        console.error(
          "TOKEN_GL_BALANCE_RPC_FAILED",
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
          error.message,
        );
      }

      console.log(
        "TOKEN_GL_BALANCE_FETCHED",
        {
          fiscalYear:
            data?.fiscalYear,

          period:
            data?.period,
        },
      );

      return successResponse(
        data,
      );
    } catch (error) {
      const message =
        getErrorMessage(
          error,
        );

      console.error(
        "TOKEN_GL_BALANCE_ERROR",
        {
          error:
            message,
        },
      );

      return errorResponse(
        message ||
          "FAILED_TO_FETCH_TOKEN_GL_BALANCES",
      );
    }
  },
);