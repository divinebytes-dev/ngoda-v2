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
    if (request.method !== "POST") {
      throw new AppError(
        "METHOD_NOT_ALLOWED",
      );
    }

    const authSupabase =
      createSupabaseClient(request);

    const {
      data: balances,
      error: balancesError,
    } = await authSupabase.rpc(
      "get_my_multi_wallet_balances",
    );

    if (balancesError) {
      console.error(
        "Multi-wallet balances RPC failed",
        {
          code: balancesError.code,
          message:
            balancesError.message,
          details:
            balancesError.details,
          hint:
            balancesError.hint,
        },
      );

      throw new AppError(
        balancesError.message ||
          "FAILED_TO_FETCH_MULTI_WALLET_BALANCES",
      );
    }

    return successResponse(
      balances ?? {
        merchantWallet: {
          wallet_balances: [],
          total_usd_value: "0",
        },

        customerWallet: {
          wallet_balances: [],
          total_usd_value: "0",
        },

        agentWallet: {
          wallet_balances: [],
          total_usd_value: "0",
        },
      },
    );
  } catch (error) {
    console.error(
      "MULTI_WALLET_BALANCES_ERROR",
      error,
    );

    return errorResponse(error);
  }
});