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
      "get_my_wallet_balances",
    );

    if (balancesError) {
      console.error(
        "Wallet balances RPC failed",
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
          "FAILED_TO_FETCH_WALLET_BALANCES",
      );
    }

    return successResponse(
      balances ?? {
        balances: {},
      },
    );
  } catch (error) {
    console.error(
      "WALLET_BALANCES_ERROR",
      error,
    );

    return errorResponse(error);
  }
});