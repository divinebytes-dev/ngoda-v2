// supabase/functions/gl-periodic-balances/index.ts

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

function getGlAccountCode(
  request: Request,
): string {
  const url =
    new URL(request.url);

  const queryCode =
    url.searchParams
      .get("gl_account_code")
      ?.trim();

  if (queryCode) {
    return queryCode;
  }

  /*
   * Also support:
   *
   * /functions/v1/gl-periodic-balances/{gl_account_code}
   */
  const pathSegments =
    url.pathname
      .split("/")
      .filter(
        (segment) =>
          segment.length > 0,
      );

  const functionIndex =
    pathSegments.lastIndexOf(
      "gl-periodic-balances",
    );

  const pathCode =
    functionIndex >= 0
      ? pathSegments[
        functionIndex + 1
      ]
      : undefined;

  if (pathCode) {
    return decodeURIComponent(
      pathCode,
    ).trim();
  }

  throw new AppError(
    "GL_ACCOUNT_CODE_REQUIRED",
  );
}

Deno.serve(async (request: Request) => {
  try {
    if (request.method !== "GET") {
      throw new AppError(
        "METHOD_NOT_ALLOWED",
      );
    }

    const url =
      new URL(request.url);

    const glAccountCode =
      getGlAccountCode(request);

    const requestedCurrency =
      url.searchParams
        .get("currency")
        ?.trim() ||
      "USD";

    const currencyCode =
      requestedCurrency
        .toLowerCase();

    const authSupabase =
      createSupabaseClient(request);

    const {
      data,
      error,
    } = await authSupabase.rpc(
      "fetch_my_gl_periodic_balances",
      {
        p_gl_account_code:
          glAccountCode,

        p_currency_code:
          currencyCode,
      },
    );

    if (error) {
      console.error(
        "GL drilldown RPC failed",
        {
          code: error.code,
          message: error.message,
          details: error.details,
          hint: error.hint,
          glAccountCode,
          currencyCode,
        },
      );

      throw new AppError(
        error.message ||
          "GL_PERIODIC_BALANCES_FAILED",
      );
    }

    if (!data) {
      throw new AppError(
        "GL_PERIODIC_BALANCES_NOT_FOUND",
      );
    }

    /*
     * Preserve the original response by adding the requested
     * currency beside the RPC result.
     */
    return successResponse({
      currency:
        requestedCurrency,
      ...(
        data as Record<
          string,
          unknown
        >
      ),
    });
  } catch (error) {
    console.error(
      "GL_PERIODIC_BALANCES_ERROR",
      {
        error:
          error instanceof Error
            ? error.message
            : String(error),
      },
    );

    return errorResponse(
      error,
      "GL_PERIODIC_BALANCES_FAILED",
    );
  }
});