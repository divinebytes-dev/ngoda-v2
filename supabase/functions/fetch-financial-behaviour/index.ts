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
     * This is a read endpoint.
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
      data: financialBehaviour,
      error: financialBehaviourError,
    } = await authSupabase.rpc(
      "get_my_financial_summary",
    );


    if (financialBehaviourError) {
      console.error(
        "Financial behaviour RPC failed",
        {
          code:
            financialBehaviourError.code,

          message:
            financialBehaviourError.message,

          details:
            financialBehaviourError.details,

          hint:
            financialBehaviourError.hint,
        },
      );


      throw new AppError(
        financialBehaviourError.message ||
          "FAILED_TO_FETCH_FINANCIAL_BEHAVIOUR",
        500,
      );
    }


    return successResponse(
      financialBehaviour ?? {
        fiscal_year: 0,
        current_period: 0,
        currencies: [],
        gold: {
          opening_quantity: 0,
          purchased: 0,
          sold: 0,
          transferred_in: 0,
          transferred_out: 0,
          closing_quantity: 0,
        },
      },
    );

  } catch (error) {

    console.error(
      "GET_FINANCIAL_SUMMARY_ERROR",
      error,
    );


    return errorResponse(error);
  }
});