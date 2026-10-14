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
  getSupportedBlockchainBalance,
} from "../../_shared/blockchain/balances.ts";

type VendorDashboardContext = {
  wallet_address: string;
};

type SupportedBlockchain = Parameters<
  typeof getSupportedBlockchainBalance
>[0];

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
     * 1. Fetch authenticated vendor context.
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
          code: contextError.code,
          message: contextError.message,
          details: contextError.details,
          hint: contextError.hint,
        },
      );

      throw new AppError(
        contextError.message ||
          "FAILED_TO_FETCH_VENDOR_DASHBOARD",
      );
    }

    const context = (
      contextRows as unknown as
        VendorDashboardContext[] | null
    )?.[0];

    if (!context?.wallet_address) {
      throw new AppError(
        "WALLET_ADDRESS_NOT_FOUND",
      );
    }

    /*
     * 2. Fetch active supported blockchains.
     *
     * The RPC must permit the vendor role.
     */
    const {
      data: blockchainRows,
      error: blockchainError,
    } = await authSupabase.rpc(
      "fetch_active_supported_blockchains",
    );

    if (blockchainError) {
      console.error(
        "Supported blockchains RPC failed",
        {
          code: blockchainError.code,
          message: blockchainError.message,
          details: blockchainError.details,
          hint: blockchainError.hint,
        },
      );

      throw new AppError(
        blockchainError.message ||
          "FAILED_TO_FETCH_SUPPORTED_BLOCKCHAINS",
      );
    }

    const supportedBlockchains =
      (blockchainRows ?? []) as SupportedBlockchain[];

    /*
     * 3. Fetch token balances separately for
     * each supported blockchain.
     */
    const blockchainBalances = await Promise.all(
      supportedBlockchains.map(
        (blockchain) =>
          getSupportedBlockchainBalance(
            blockchain,
            context.wallet_address,
          ),
      ),
    );

    /*
     * 4. Build vendor dashboard.
     *
     * Pass the complete per-chain balance array
     * as JSONB, replacing p_token_balance.
     */
    const {
      data: dashboard,
      error: dashboardError,
    } = await authSupabase.rpc(
      "build_my_vendor_dashboard",
      {
        p_blockchain_balances:
          blockchainBalances,
      },
    );

    if (dashboardError) {
      console.error(
        "Vendor dashboard RPC failed",
        {
          code: dashboardError.code,
          message: dashboardError.message,
          details: dashboardError.details,
          hint: dashboardError.hint,
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

    /*
     * 5. Return dashboard.
     */
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