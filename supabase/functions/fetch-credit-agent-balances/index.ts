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


function parsePositiveInteger(
  value: string | null,
  defaultValue: number,
  errorCode: string,
): number {
  if (value === null || value.trim() === "") {
    return defaultValue;
  }

  if (!/^[0-9]+$/.test(value.trim())) {
    throw new AppError(errorCode);
  }

  const result = Number(value);

  if (
    !Number.isSafeInteger(result) ||
    result < 1
  ) {
    throw new AppError(errorCode);
  }

  return result;
}


Deno.serve(async (request: Request) => {
  try {
    if (request.method !== "GET") {
      throw new AppError(
        "METHOD_NOT_ALLOWED",
        405,
      );
    }

    const url = new URL(request.url);

    const page = parsePositiveInteger(
      url.searchParams.get("page"),
      1,
      "INVALID_PAGE",
    );

    const pageSize = parsePositiveInteger(
      url.searchParams.get("pageSize"),
      50,
      "INVALID_PAGE_SIZE",
    );

    if (pageSize > 100) {
      throw new AppError(
        "INVALID_PAGE_SIZE",
      );
    }

    /*
     * The authenticated client forwards the caller's JWT.
     *
     * PostgreSQL validates:
     *
     * - authentication;
     * - Accounts role;
     * - country;
     * - report visibility.
     */
    const supabase =
      createSupabaseClient(request);

    const {
      data,
      error,
    } = await supabase.rpc(
      "fetch_my_credit_agent_balances",
      {
        p_page:
          page,

        p_page_size:
          pageSize,
      },
    );

    if (error) {
      console.error(
        "CREDIT_AGENT_BALANCES_RPC_FAILED",
        {
          code:
            error.code,

          message:
            error.message,

          details:
            error.details,

          hint:
            error.hint,

          page,

          pageSize,
        },
      );

      throw new AppError(
        error.message ||
          "FAILED_TO_FETCH_CREDIT_AGENT_BALANCES",
      );
    }

    if (
      data === null ||
      data === undefined
    ) {
      throw new AppError(
        "CREDIT_AGENT_BALANCES_RESULT_NOT_FOUND",
      );
    }

    /*
     * Return the RPC result unchanged.
     *
     * Expected structure:
     *
     * {
     *   creditAgents: [...],
     *   pagination: {...}
     * }
     */
    return successResponse(data);
  } catch (error) {
    return errorResponse(
      error,
      "FAILED_TO_FETCH_CREDIT_AGENT_BALANCES",
    );
  }
});