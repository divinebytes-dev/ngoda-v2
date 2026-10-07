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

import {
  getRelayerGasBalance,
  getTotalSupply,
} from "../../_shared/blockchain/balances.ts";

type TreasuryContext = {
  user_id: string;
  country_code: string;
};

Deno.serve(async (request: Request) => {
  try {
    if (request.method !== "POST") {
      throw new AppError(
        "METHOD_NOT_ALLOWED",
      );
    }

    const authSupabase =
      createSupabaseClient(request);

    /*
     * Validate the treasury role before making
     * blockchain requests.
     */
    const {
      data: contextRows,
      error: contextError,
    } = await authSupabase.rpc(
      "fetch_my_treasury_dashboard_context",
    );

    if (contextError) {
      console.error(
        "Treasury context RPC failed",
        {
          code: contextError.code,
          message: contextError.message,
          details: contextError.details,
          hint: contextError.hint,
        },
      );

      throw new AppError(
        contextError.message ||
          "FAILED_TO_FETCH_TREASURY_CONTEXT",
      );
    }

    const context =
      (
        contextRows as
          TreasuryContext[] | null
      )?.[0];

    if (!context?.user_id) {
      throw new AppError(
        "TREASURY_NOT_AUTHORIZED",
      );
    }

    /*
     * Fetch both blockchain values once and in parallel.
     */
    const [
      gasBalance,
      totalSupply,
    ] = await Promise.all([
      getRelayerGasBalance(),
      getTotalSupply(),
    ]);

    const {
      data: dashboard,
      error: dashboardError,
    } = await authSupabase.rpc(
      "build_my_treasury_dashboard",
      {
        p_token_supply:
          totalSupply.token_balance,

        p_gas_balance:
          gasBalance,
      },
    );

    if (dashboardError) {
      console.error(
        "Treasury dashboard RPC failed",
        {
          code: dashboardError.code,
          message:
            dashboardError.message,
          details:
            dashboardError.details,
          hint:
            dashboardError.hint,
        },
      );

      throw new AppError(
        dashboardError.message ||
          "FAILED_TO_FETCH_TREASURY_DASHBOARD",
      );
    }

    return successResponse(
      dashboard,
    );
  } catch (error) {
    console.error(
      "TREASURY_DASHBOARD_ERROR",
      error,
    );

    return errorResponse(error);
  }
});