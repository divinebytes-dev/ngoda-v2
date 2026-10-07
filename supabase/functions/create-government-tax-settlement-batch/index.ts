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


type CreateGovernmentTaxBatchBody = {
  currency_code?: unknown;
  start_date?: unknown;
  end_date?: unknown;
};


function parseRequiredString(
  value: unknown,
  errorMessage: string,
): string {
  if (
    typeof value !== "string" ||
    value.trim() === ""
  ) {
    throw new AppError(
      errorMessage,
      400,
    );
  }

  return value.trim();
}


function parseIsoDate(
  value: unknown,
  errorMessage: string,
): string {
  const dateValue =
    parseRequiredString(
      value,
      errorMessage,
    );

  if (
    !/^\d{4}-\d{2}-\d{2}$/.test(
      dateValue,
    )
  ) {
    throw new AppError(
      errorMessage,
      400,
    );
  }

  const parsedDate =
    new Date(
      `${dateValue}T00:00:00.000Z`,
    );

  if (
    Number.isNaN(
      parsedDate.getTime(),
    ) ||
    parsedDate
      .toISOString()
      .slice(0, 10) !==
      dateValue
  ) {
    throw new AppError(
      errorMessage,
      400,
    );
  }

  return dateValue;
}


Deno.serve(async (request: Request) => {
  try {
    if (request.method !== "POST") {
      throw new AppError(
        "METHOD_NOT_ALLOWED",
        405,
      );
    }

    let body:
      CreateGovernmentTaxBatchBody;

    try {
      body =
        await request.json();
    } catch {
      throw new AppError(
        "INVALID_REQUEST_BODY",
        400,
      );
    }

    const currencyCode =
      parseRequiredString(
        body.currency_code,
        "CURRENCY_CODE_REQUIRED",
      ).toLowerCase();

    const startDate =
      parseIsoDate(
        body.start_date,
        "INVALID_START_DATE",
      );

    const endDate =
      parseIsoDate(
        body.end_date,
        "INVALID_END_DATE",
      );

    /*
     * Same-day settlement ranges are valid.
     */
    if (startDate > endDate) {
      throw new AppError(
        "INVALID_SETTLEMENT_DATE_RANGE",
        400,
      );
    }

    if (currencyCode === "gold") {
      throw new AppError(
        "INVALID_TAX_SETTLEMENT_CURRENCY",
        400,
      );
    }

    const supabase =
      createSupabaseClient(request);

    const {
      data,
      error,
    } = await supabase.rpc(
      "create_my_government_tax_settlement_batch",
      {
        p_currency_code:
          currencyCode,

        p_start_date:
          startDate,

        p_end_date:
          endDate,
      },
    );

    if (error) {
      console.error(
        "CREATE_GOVERNMENT_TAX_SETTLEMENT_BATCH_RPC_FAILED",
        {
          code:
            error.code,

          message:
            error.message,

          details:
            error.details,

          hint:
            error.hint,

          currencyCode,
          startDate,
          endDate,
        },
      );

      if (
        error.message.includes(
          "GOVERNMENT_TAX_SETTLEMENT_PAYMENT_UNDERWAY",
        )
      ) {
        throw new AppError(
          error.message,
          409,
        );
      }

      if (
        error.message.includes(
          "GOVERNMENT_TAX_PAYABLE_NOT_FOUND_FOR_SELECTED_DATE_RANGE",
        )
      ) {
        throw new AppError(
          "GOVERNMENT_TAX_PAYABLE_NOT_FOUND_FOR_SELECTED_DATE_RANGE",
          404,
        );
      }

      throw new AppError(
        error.message ||
          "TAX_SETTLEMENT_FAILED",
      );
    }

    if (!data) {
      throw new AppError(
        "GOVERNMENT_TAX_SETTLEMENT_BATCH_RESULT_NOT_FOUND",
      );
    }

    return successResponse(
      data,
    );
  } catch (error) {
    console.error(
      "CREATE_GOVERNMENT_TAX_SETTLEMENT_BATCH_ERROR",
      {
        error:
          error instanceof Error
            ? error.message
            : String(error),
      },
    );

    return errorResponse(
      error,
      "TAX_SETTLEMENT_FAILED",
    );
  }
});