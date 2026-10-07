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
  errorMessage: string,
  maximum?: number,
): number {
  if (
    value === null ||
    value.trim() === ""
  ) {
    return defaultValue;
  }

  const normalizedValue =
    value.trim();

  if (!/^\d+$/.test(normalizedValue)) {
    throw new AppError(
      errorMessage,
      400,
    );
  }

  const parsedValue =
    Number(normalizedValue);

  if (
    !Number.isSafeInteger(parsedValue) ||
    parsedValue < 1 ||
    (
      maximum !== undefined &&
      parsedValue > maximum
    )
  ) {
    throw new AppError(
      errorMessage,
      400,
    );
  }

  return parsedValue;
}


function parseLiquidationDate(
  value: string | null,
): string {
  if (
    value === null ||
    value.trim() === ""
  ) {
    throw new AppError(
      "LIQUIDATION_DATE_REQUIRED",
      400,
    );
  }

  const dateValue =
    value.trim();

  if (
    !/^\d{4}-\d{2}-\d{2}$/.test(
      dateValue,
    )
  ) {
    throw new AppError(
      "INVALID_LIQUIDATION_DATE",
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
      .slice(0, 10) !== dateValue
  ) {
    throw new AppError(
      "INVALID_LIQUIDATION_DATE",
      400,
    );
  }

  return dateValue;
}


Deno.serve(async (request: Request) => {
  try {
    if (request.method !== "GET") {
      throw new AppError(
        "METHOD_NOT_ALLOWED",
        405,
      );
    }

    const url =
      new URL(request.url);

    const liquidationDate =
      parseLiquidationDate(
        url.searchParams.get(
          "liquidationDate",
        ) ??
          url.searchParams.get(
            "liquidation_date",
          ) ??
          url.searchParams.get("date"),
      );

    const page =
      parsePositiveInteger(
        url.searchParams.get("page"),
        1,
        "INVALID_PAGE",
      );

    const pageSize =
      parsePositiveInteger(
        url.searchParams.get("pageSize") ??
          url.searchParams.get("page_size"),
        50,
        "INVALID_PAGE_SIZE",
        100,
      );

    /*
     * Use the authenticated client.
     *
     * PostgreSQL resolves the Accounts/Finance user and
     * restricts the report to that user's country.
     */
    const supabase =
      createSupabaseClient(request);

    const {
      data,
      error,
    } = await supabase.rpc(
      "fetch_my_liquidated_loans_by_date",
      {
        p_liquidation_date:
          liquidationDate,

        p_page:
          page,

        p_page_size:
          pageSize,
      },
    );

    if (error) {
      console.error(
        "FETCH_LIQUIDATED_LOANS_BY_DATE_RPC_FAILED",
        {
          code:
            error.code,

          message:
            error.message,

          details:
            error.details,

          hint:
            error.hint,

          liquidationDate,
          page,
          pageSize,
        },
      );

      throw new AppError(
        error.message ||
          "FETCH_LIQUIDATED_LOANS_BY_DATE_FAILED",
      );
    }

    return successResponse(
      data ?? {
        liquidation_date:
          liquidationDate,
        rows: [],
        pagination: {
          page,
          page_size:
            pageSize,
          total_entries:
            0,
          total_pages:
            1,
          has_previous:
            page > 1,
          has_next:
            false,
        },
      },
    );
  } catch (error) {
    console.error(
      "FETCH_LIQUIDATED_LOANS_BY_DATE_ERROR",
      {
        error:
          error instanceof Error
            ? error.message
            : String(error),
      },
    );

    return errorResponse(
      error,
      "FETCH_LIQUIDATED_LOANS_BY_DATE_FAILED",
    );
  }
});
