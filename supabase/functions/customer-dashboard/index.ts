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

import type {
  SupportedBlockchainConfig,
} from "../../_shared/types/supported_blockchain_config.ts";

type DashboardContext = {
  wallet_address: string;
};

type BlockchainBalance = {
  blockchain_code: string;
  chain_id: number;
  token_supply: string;
  balance: string;
  gas_balance: string;
  native_currency_code: string;
};

Deno.serve(async (request: Request) => {
  try {
    if (request.method !== "POST") {
      throw new AppError("METHOD_NOT_ALLOWED");
    }

    const authSupabase = createSupabaseClient(request);

    const {
      data: contextRows,
      error: contextError,
    } = await authSupabase.rpc(
      "fetch_my_customer_dashboard_context",
    );

    if (contextError) {
      console.error(
        "Customer dashboard context RPC failed",
        contextError,
      );

      throw new AppError(
        contextError.message ||
          "FAILED_TO_FETCH_DASHBOARD",
      );
    }

    const context = (
      contextRows as DashboardContext[] | null
    )?.[0];

    if (!context?.wallet_address) {
      throw new AppError(
        "WALLET_ADDRESS_NOT_FOUND",
      );
    }

    /*
     * Fetch active blockchain configurations.
     *
     * This RPC must authorize active customers,
     * in addition to its existing authorized roles.
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
        blockchainError,
      );

      throw new AppError(
        "FAILED_TO_FETCH_SUPPORTED_BLOCKCHAINS",
      );
    }

    const blockchains =
      blockchainRows as SupportedBlockchainConfig[] | null;

    if (!blockchains?.length) {
      throw new AppError(
        "NO_ACTIVE_BLOCKCHAINS_CONFIGURED",
      );
    }

    /*
     * Retrieve GOLD and native gas balances
     * independently for every active blockchain.
     */
    const blockchainBalances: BlockchainBalance[] =
      await Promise.all(
        blockchains.map((blockchain) =>
          getSupportedBlockchainBalance(
            blockchain,
            context.wallet_address,
          )
        ),
      );

    /*
     * Pass the complete per-chain balances to SQL.
     * SQL calculates the aggregate GOLD balance.
     */
    const {
      data: dashboard,
      error: dashboardError,
    } = await authSupabase.rpc(
      "build_my_customer_dashboard",
      {
        p_blockchain_balances:
          blockchainBalances,
      },
    );

    if (dashboardError) {
      console.error(
        "Customer dashboard RPC failed",
        dashboardError,
      );

      throw new AppError(
        dashboardError.message ||
          "FAILED_TO_FETCH_DASHBOARD",
      );
    }

    return successResponse(dashboard);
  } catch (error) {
    console.error(
      "Error fetching customer dashboard",
      error,
    );

    return errorResponse(
      "FAILED_TO_FETCH_DASHBOARD",
    );
  }
});