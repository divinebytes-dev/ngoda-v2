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


type VendorDashboardContext = {
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

    /*
     * Fetch the authenticated active vendor's
     * blockchain wallet address.
     */
    const {
      data: contextRows,
      error: contextError,
    } = await authSupabase.rpc(
      "fetch_my_vendor_dashboard_context",
    );

    if (contextError) {
      console.error(
        "Vendor dashboard context RPC failed",
        {
          code:
            contextError.code,

          message:
            contextError.message,

          details:
            contextError.details,

          hint:
            contextError.hint,
        },
      );

      throw new AppError(
        contextError.message ||
          "FAILED_TO_FETCH_VENDOR_DASHBOARD",
      );
    }

    const context =
      (
        contextRows as unknown as
          VendorDashboardContext[] | null
      )?.[0];

    if (!context?.wallet_address) {
      throw new AppError(
        "WALLET_ADDRESS_NOT_FOUND",
      );
    }

    /*
     * Fetch the blockchain token balance required by
     * vendor loanSummary.
     */
    const blockchainBalances =
      await getBlockchainWalletBalances(
        context.wallet_address,
      );

    /*
     * Build the existing vendor dashboard plus the new
     * loanSummary.
     */
    const {
      data: dashboard,
      error: dashboardError,
    } = await authSupabase.rpc(
      "build_my_vendor_dashboard",
      {
        p_token_balance:
          blockchainBalances.token_balance,
      },
    );

    if (dashboardError) {
      console.error(
        "Vendor dashboard RPC failed",
        {
          code:
            dashboardError.code,

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
          "FAILED_TO_FETCH_VENDOR_DASHBOARD",
      );
    }

    if (!dashboard) {
      throw new AppError(
        "VENDOR_DASHBOARD_NOT_FOUND",
      );
    }

    return successResponse(
      dashboard,
    );
  } catch (error) {
    console.error(
      "VENDOR_DASHBOARD_ERROR",
      error,
    );

    return errorResponse(
      error,
    );
  }
});

