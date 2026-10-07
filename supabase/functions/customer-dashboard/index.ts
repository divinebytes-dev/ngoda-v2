
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
  getBlockchainWalletBalances,
} from "../../_shared/blockchain/balances.ts";


type DashboardContext = {
  wallet_address: string;
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

    const {
      data: contextRows,
      error: contextError,
    } = await authSupabase.rpc(
      "fetch_my_customer_dashboard_context",
    );

    if (contextError) {
      console.error(
        "Dashboard context RPC failed",
        {
          code: contextError.code,
          message: contextError.message,
          details: contextError.details,
          hint: contextError.hint,
        },
      );

      throw new AppError(
        contextError.message ||
          "FAILED_TO_FETCH_DASHBOARD",
      );
    }

    const context =
      (
        contextRows as
          DashboardContext[] | null
      )?.[0];

    if (!context?.wallet_address) {
      throw new AppError(
        "WALLET_ADDRESS_NOT_FOUND",
      );
    }

    const blockchainBalances =
      await getBlockchainWalletBalances(
        context.wallet_address,
      );

    const {
      data: dashboard,
      error: dashboardError,
    } = await authSupabase.rpc(
      "build_my_customer_dashboard",
      {
        p_token_balance:
          blockchainBalances.token_balance,
        p_gas_balance:
          blockchainBalances.gas_balance,
      },
    );

    if (dashboardError) {
      console.error(
        "Dashboard RPC failed",
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
          "FAILED_TO_FETCH_DASHBOARD",
      );
    }

    return successResponse(
      dashboard,
    );
  } catch (error) {
    console.error(
      "Error fetching customer dashboard",
      {
        message:
          error instanceof Error
            ? error.message
            : "FAILED_TO_FETCH_DASHBOARD",
      },
    );

    return errorResponse( "FAILED_TO_FETCH_DASHBOARD" );
  }
});