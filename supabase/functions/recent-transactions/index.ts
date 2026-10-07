// supabase/functions/recent-transactions/index.ts

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

function parseOptionalDate(
  value: string | null,
  errorCode: string,
): string | null {
  if (!value) {
    return null;
  }

  const parsedDate =
    new Date(value);

  if (
    Number.isNaN(
      parsedDate.getTime(),
    )
  ) {
    throw new AppError(
      errorCode,
    );
  }

  return parsedDate
    .toISOString()
    .slice(0, 10);
}

function parseInteger(
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

    const page =
      parseInteger(
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
      parseInteger(
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

    const startDate =
      parseOptionalDate(
        url.searchParams.get(
          "startDate",
        ),
        "INVALID_START_DATE",
      );

    const endDate =
      parseOptionalDate(
        url.searchParams.get(
          "endDate",
        ),
        "INVALID_END_DATE",
      );

    if (
      startDate &&
      endDate &&
      endDate < startDate
    ) {
      throw new AppError(
        "INVALID_REPORT_DATE_RANGE",
      );
    }

    const currencyValue =
      url.searchParams
        .get("currency")
        ?.trim()
        .toLowerCase();

    const currency =
      currencyValue || null;

    const authSupabase =
      createSupabaseClient(request);

    const {
      data,
      error,
    } = await authSupabase.rpc(
      "fetch_my_recent_financial_transactions",
      {
        p_currency_code:
          currency,

        p_page:
          page,

        p_page_size:
          pageSize,

        p_start_date:
          startDate,

        p_end_date:
          endDate,
      },
    );

    if (error) {
      console.error(
        "Recent-transactions RPC failed",
        {
          code: error.code,
          message: error.message,
          details: error.details,
          hint: error.hint,
          currency,
          page,
          pageSize,
          startDate,
          endDate,
        },
      );

      throw new AppError(
        error.message ||
          "FAILED_TO_FETCH_TRANSACTIONS",
      );
    }

    /*
     * Do not add a "currencies" wrapper.
     *
     * FinanceTransactionSummary expects:
     *
     * {
     *   "usd": {
     *     "pagination": {...},
     *     "transactions": [...]
     *   }
     * }
     */
    return successResponse(
      data ?? {},
    );
  } catch (error) {
    console.error(
      "RECENT_TRANSACTIONS_ERROR",
      {
        error:
          error instanceof Error
            ? error.message
            : String(error),
      },
    );

    return errorResponse(
      error,
      "FAILED_TO_FETCH_TRANSACTIONS",
    );
  }
});