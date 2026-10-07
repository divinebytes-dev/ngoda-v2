import {
  errorResponse,
  successResponse,
} from "../../_shared/api-response.ts";

import {
  AppError,
} from "../../_shared/app-error.ts";

import {
  parsePositiveInteger,
} from "../../_shared/gamification/read-request-parser.ts";

import {
  createSupabaseClient,
} from "../../_shared/supabase-client.ts";

import type {
  LoyaltyLedgerPage,
} from "../../_shared/types/loyalty-read.ts";


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

    const page =
      parsePositiveInteger(
        url.searchParams.get("page"),
        1,
        "INVALID_PAGE",
        1000000,
      );

    const pageSize =
      parsePositiveInteger(
        url.searchParams.get("pageSize") ??
          url.searchParams.get("page_size"),
        50,
        "INVALID_PAGE_SIZE",
        100,
      );

    const supabase =
      createSupabaseClient(request);

    const {
      data,
      error,
    } = await supabase.rpc(
      "fetch_my_loyalty_ledger",
      {
        p_page: page,
        p_page_size: pageSize,
      },
    );

    if (error) {
      console.error(
        "FETCH_LOYALTY_LEDGER_RPC_FAILED",
        {
          code: error.code,
          message: error.message,
          details: error.details,
          hint: error.hint,
          page,
          pageSize,
        },
      );

      throw new AppError(
        error.message ||
          "FETCH_LOYALTY_LEDGER_FAILED",
      );
    }

    if (
      data === null ||
      typeof data !== "object" ||
      Array.isArray(data)
    ) {
      throw new AppError(
        "INVALID_LOYALTY_LEDGER_RESULT",
      );
    }

    return successResponse(
      data as LoyaltyLedgerPage,
    );
  } catch (error) {
    console.error(
      "FETCH_LOYALTY_LEDGER_ERROR",
      {
        error:
          error instanceof Error
            ? error.message
            : String(error),
      },
    );

    return errorResponse(
      error,
      "FETCH_LOYALTY_LEDGER_FAILED",
    );
  }
});

