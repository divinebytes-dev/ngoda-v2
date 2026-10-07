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
    /*
     * Financial periods are read-only.
     */
    if (request.method !== "GET") {
      throw new AppError(
        "METHOD_NOT_ALLOWED",
        405,
      );
    }


    const authSupabase =
      createSupabaseClient(request);


    const {
      data: financialPeriods,
      error: financialPeriodsError,
    } = await authSupabase.rpc(
      "get_my_financial_periods",
    );


    if (financialPeriodsError) {
      console.error(
        "Financial periods RPC failed",
        {
          code:
            financialPeriodsError.code,

          message:
            financialPeriodsError.message,

          details:
            financialPeriodsError.details,

          hint:
            financialPeriodsError.hint,
        },
      );


      switch (
        financialPeriodsError.message
      ) {
        case "UNAUTHORIZED":
          throw new AppError(
            "UNAUTHORIZED",
            401,
          );

        case "FINANCIAL_BEHAVIOUR_NOT_AUTHORIZED":
          throw new AppError(
            "FINANCIAL_BEHAVIOUR_NOT_AUTHORIZED",
            403,
          );

        case "USER_COUNTRY_NOT_FOUND":
          throw new AppError(
            "USER_COUNTRY_NOT_FOUND",
            404,
          );

        case "FISCAL_PERIOD_NOT_FOUND":
          throw new AppError(
            "FISCAL_PERIOD_NOT_FOUND",
            404,
          );

        default:
          throw new AppError(
            "FAILED_TO_FETCH_FINANCIAL_PERIODS",
            500,
          );
      }
    }


    return successResponse(
      financialPeriods ?? {
        fiscal_year: 0,
        current_period: 0,
        periods: [],
      },
    );

  } catch (error) {

    console.error(
      "GET_FINANCIAL_PERIODS_ERROR",
      error,
    );


    return errorResponse(error);
  }
});