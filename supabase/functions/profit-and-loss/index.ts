// supabase/functions/profit-and-loss/index.ts

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

function parseRequiredDate(
  value: string | null,
  missingError: string,
  invalidError: string,
): string {
  if (!value) {
    throw new AppError(
      missingError,
    );
  }

  const parsedDate =
    new Date(value);

  if (
    Number.isNaN(
      parsedDate.getTime(),
    )
  ) {
    throw new AppError(
      invalidError,
    );
  }

  return parsedDate
    .toISOString()
    .slice(0, 10);
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

    const startDate =
      parseRequiredDate(
        url.searchParams.get(
          "startDate",
        ),
        "START_DATE_REQUIRED",
        "INVALID_START_DATE",
      );

    const endDate =
      parseRequiredDate(
        url.searchParams.get(
          "endDate",
        ),
        "END_DATE_REQUIRED",
        "INVALID_END_DATE",
      );

    if (endDate < startDate) {
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

    if (currency === "gold") {
      throw new AppError(
        "GOLD_CURRENCY_NOT_ALLOWED",
      );
    }

    const authSupabase =
      createSupabaseClient(request);

    const {
      data,
      error,
    } = await authSupabase.rpc(
      "fetch_my_profit_and_loss",
      {
        p_start_date:
          startDate,

        p_end_date:
          endDate,

        p_currency_code:
          currency,
      },
    );

    if (error) {
      console.error(
        "Profit-and-loss RPC failed",
        {
          code: error.code,
          message: error.message,
          details: error.details,
          hint: error.hint,
          startDate,
          endDate,
          currency,
        },
      );

      throw new AppError(
        error.message ||
          "FAILED_TO_LOAD_PROFIT_AND_LOSS",
      );
    }

    return successResponse(data);
  } catch (error) {
    console.error(
      "PROFIT_AND_LOSS_ERROR",
      {
        error:
          error instanceof Error
            ? error.message
            : String(error),
      },
    );

    return errorResponse(
      error,
      "FAILED_TO_LOAD_PROFIT_AND_LOSS",
    );
  }
});