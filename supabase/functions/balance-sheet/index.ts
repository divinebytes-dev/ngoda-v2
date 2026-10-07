// supabase/functions/balance-sheet/index.ts

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

    const url =
      new URL(request.url);

    const asOfDateValue =
      url.searchParams.get(
        "asOfDate",
      );

    if (!asOfDateValue) {
      throw new AppError(
        "AS_OF_DATE_REQUIRED",
      );
    }

    const parsedAsOfDate =
      new Date(asOfDateValue);

    if (
      Number.isNaN(
        parsedAsOfDate.getTime(),
      )
    ) {
      throw new AppError(
        "INVALID_AS_OF_DATE",
      );
    }

    const asOfDate =
      parsedAsOfDate
        .toISOString()
        .slice(0, 10);

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
      "fetch_my_balance_sheet",
      {
        p_as_of_date:
          asOfDate,

        p_currency_code:
          currency,
      },
    );

    if (error) {
      console.error(
        "Balance-sheet RPC failed",
        {
          code: error.code,
          message: error.message,
          details: error.details,
          hint: error.hint,
          asOfDate,
          currency,
        },
      );

      throw new AppError(
        error.message ||
          "FAILED_TO_LOAD_BALANCE_SHEET",
      );
    }

    return successResponse(data);
  } catch (error) {
    console.error(
      "BALANCE_SHEET_ERROR",
      {
        error:
          error instanceof Error
            ? error.message
            : String(error),
      },
    );

    return errorResponse(
      error,
      "FAILED_TO_LOAD_BALANCE_SHEET",
    );
  }
});