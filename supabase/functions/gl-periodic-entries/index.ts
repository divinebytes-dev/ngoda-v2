// supabase/functions/gl-entries/index.ts

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

function parseRequiredInteger(
  value: string | null,
  missingError: string,
  invalidError: string,
): number {
  if (!value) {
    throw new AppError(
      missingError,
    );
  }

  const parsedValue =
    Number(value);

  if (!Number.isInteger(parsedValue)) {
    throw new AppError(
      invalidError,
    );
  }

  return parsedValue;
}

function parseOptionalInteger(
  value: string | null,
  defaultValue: number,
  errorCode: string,
): number {
  if (!value) {
    return defaultValue;
  }

  const parsedValue =
    Number(value);

  if (!Number.isInteger(parsedValue)) {
    throw new AppError(
      errorCode,
    );
  }

  return parsedValue;
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
      url.searchParams
        .get("gl")
        ?.trim();

    if (!glAccountCode) {
      throw new AppError(
        "GL_IS_REQUIRED",
      );
    }

    const currency =
      url.searchParams
        .get("currency")
        ?.trim()
        .toLowerCase();

    if (!currency) {
      throw new AppError(
        "CURRENCY_IS_REQUIRED",
      );
    }

    const fiscalYear =
      parseRequiredInteger(
        url.searchParams.get(
          "fiscalYear",
        ),
        "FISCAL_YEAR_IS_REQUIRED",
        "INVALID_FISCAL_YEAR",
      );

    const period =
      parseRequiredInteger(
        url.searchParams.get(
          "period",
        ),
        "PERIOD_IS_REQUIRED",
        "INVALID_PERIOD",
      );

    if (
      period < 1 ||
      period > 12
    ) {
      throw new AppError(
        "INVALID_PERIOD",
      );
    }

    const page =
      parseOptionalInteger(
        url.searchParams.get(
          "page",
        ),
        1,
        "INVALID_PAGE",
      );

    if (page < 1) {
      throw new AppError(
        "INVALID_PAGE",
      );
    }

    const pageSize =
      parseOptionalInteger(
        url.searchParams.get(
          "pageSize",
        ),
        50,
        "INVALID_PAGE_SIZE",
      );

    if (
      pageSize < 1 ||
      pageSize > 100
    ) {
      throw new AppError(
        "INVALID_PAGE_SIZE",
      );
    }

    const authSupabase =
      createSupabaseClient(request);

    const {
      data,
      error,
    } = await authSupabase.rpc(
      "fetch_my_gl_period_entries",
      {
        p_gl_account_code:
          glAccountCode,

        p_currency_code:
          currency,

        p_fiscal_year:
          fiscalYear,

        p_period:
          period,

        p_page:
          page,

        p_page_size:
          pageSize,
      },
    );

    if (error) {
      console.error(
        "GL entries RPC failed",
        {
          code: error.code,
          message: error.message,
          details: error.details,
          hint: error.hint,
          glAccountCode,
          currency,
          fiscalYear,
          period,
          page,
          pageSize,
        },
      );

      throw new AppError(
        error.message ||
          "GL_ENTRIES_FAILED",
      );
    }

    return successResponse(data);
  } catch (error) {
    console.error(
      "GL_ENTRIES_ERROR",
      {
        error:
          error instanceof Error
            ? error.message
            : String(error),
      },
    );

    return errorResponse(
      error,
      "GL_ENTRIES_FAILED",
    );
  }
});