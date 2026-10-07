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

type MiniStatementRequest = {
  start_date?: string;
  end_date?: string;
  currency?: string | null;
  page?: number;
  page_size?: number;
};

Deno.serve(async (request: Request) => {
  try {
    if (request.method !== "POST") {
      throw new AppError(
        "METHOD_NOT_ALLOWED",
      );
    }

    /*
     * Same authentication pattern as dashboard.
     *
     * The Authorization header is attached to this client,
     * allowing auth.uid() to resolve inside the RPC.
     */
    const authSupabase =
      createSupabaseClient(request);

    let body: MiniStatementRequest;

    try {
      body =
        await request.json() as MiniStatementRequest;
    } catch {
      throw new AppError(
        "INVALID_REQUEST_BODY",
      );
    }

    if (!body.start_date) {
      throw new AppError(
        "START_DATE_IS_REQUIRED",
      );
    }

    if (!body.end_date) {
      throw new AppError(
        "END_DATE_IS_REQUIRED",
      );
    }

    const startDate =
      new Date(body.start_date);

    const endDate =
      new Date(body.end_date);

    if (Number.isNaN(startDate.getTime())) {
      throw new AppError(
        "INVALID_START_DATE",
      );
    }

    if (Number.isNaN(endDate.getTime())) {
      throw new AppError(
        "INVALID_END_DATE",
      );
    }

    if (
      startDate.getTime() >
      endDate.getTime()
    ) {
      throw new AppError(
        "INVALID_DATE_RANGE",
      );
    }

    /*
     * Include the entire end date.
     */
    endDate.setUTCHours(
      23,
      59,
      59,
      999,
    );

    const page =
      Number(body.page ?? 1);

    const pageSize =
      Number(body.page_size ?? 50);

    if (
      !Number.isInteger(page) ||
      page < 1
    ) {
      throw new AppError(
        "INVALID_PAGE",
      );
    }

    if (
      !Number.isInteger(pageSize) ||
      pageSize < 1 ||
      pageSize > 100
    ) {
      throw new AppError(
        "INVALID_PAGE_SIZE",
      );
    }

    const currency =
      typeof body.currency === "string" &&
        body.currency.trim().length > 0
        ? body.currency
          .trim()
          .toLowerCase()
        : null;

    const {
      data,
      error,
    } = await authSupabase.rpc(
      "get_my_last_wallet_transactions",
      {
        p_start_date:
          startDate.toISOString(),

        p_end_date:
          endDate.toISOString(),

        p_currency_code:
          currency,

        p_page:
          page,

        p_page_size:
          pageSize,
      },
    );

    if (error) {
      console.error(
        "Wallet mini-statement RPC failed",
        {
          code: error.code,
          message: error.message,
          details: error.details,
          hint: error.hint,
        },
      );

      throw new AppError(
        error.message ||
          "FAILED_TO_FETCH_MINI_STATEMENT",
      );
    }

    return successResponse(
      data ?? {},
    );
  } catch (error) {
    console.error(
      "WALLET_MINI_STATEMENT_ERROR",
      error,
    );

    /*
     * errorResponse takes one argument.
     */
    return errorResponse(error);
  }
});