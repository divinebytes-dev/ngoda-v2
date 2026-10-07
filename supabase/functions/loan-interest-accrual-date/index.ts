// supabase/functions/loan-interest-accrual-date/index.ts

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

type LastAccrualRow = {
  last_accrual_run: string | null;
};

Deno.serve(async (request: Request) => {
  try {
    if (request.method !== "GET") {
      throw new AppError(
        "METHOD_NOT_ALLOWED",
      );
    }

    const authSupabase =
      createSupabaseClient(request);

    const {
      data,
      error,
    } = await authSupabase.rpc(
      "fetch_my_last_loan_interest_accrual",
    );

    if (error) {
      console.error(
        "Fetch last loan-interest accrual RPC failed",
        {
          code: error.code,
          message: error.message,
          details: error.details,
          hint: error.hint,
        },
      );

      throw new AppError(
        error.message ||
          "FAILED_TO_FETCH_LAST_INTEREST_DATE",
      );
    }

    const rows =
      data as unknown as
        LastAccrualRow[] | null;

    const lastAccrual =
      rows?.[0]?.last_accrual_run ??
      null;

    return successResponse({
      last_accrual_run:
        lastAccrual,
    });
  } catch (error) {
    console.error(
      "FETCH_LAST_LOAN_INTEREST_ACCRUAL_ERROR",
      {
        error:
          error instanceof Error
            ? error.message
            : String(error),
      },
    );

    return errorResponse(
      error,
      "FAILED_TO_FETCH_LAST_INTEREST_DATE",
    );
  }
});