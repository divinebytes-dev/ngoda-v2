// supabase/functions/trial-balance/index.ts

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
      (startDate && !endDate) ||
      (!startDate && endDate)
    ) {
      throw new AppError(
        "START_AND_END_DATE_REQUIRED_TOGETHER",
      );
    }

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
      "fetch_my_trial_balance",
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
        "Trial-balance RPC failed",
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
          "FAILED_TO_LOAD_TRIAL_BALANCE",
      );
    }

    return successResponse(data);
  } catch (error) {
    console.error(
      "TRIAL_BALANCE_ERROR",
      {
        error:
          error instanceof Error
            ? error.message
            : String(error),
      },
    );

    return errorResponse(
      error,
      "FAILED_TO_LOAD_TRIAL_BALANCE",
    );
  }
});