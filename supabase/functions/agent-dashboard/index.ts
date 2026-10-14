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

type AgentDashboardContext = {
  wallet_address: string;
};

type SupportedBlockchain =
  Parameters<typeof getSupportedBlockchainBalance>[0];

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
     * Fetch the authenticated active agent's
     * blockchain wallet address.
     */
    const {
      data: contextRows,
      error: contextError,
    } = await authSupabase.rpc(
      "fetch_my_agent_dashboard_context",
    );

    if (contextError) {
      console.error(
        "Agent dashboard context RPC failed",
        {
          code: contextError.code,
          message: contextError.message,
          details: contextError.details,
          hint: contextError.hint,
        },
      );

      throw new AppError(
        contextError.message ||
          "FAILED_TO_FETCH_AGENT_DASHBOARD",
      );
    }

    const context = (
      contextRows as unknown as
        AgentDashboardContext[] | null
    )?.[0];

    if (!context?.wallet_address) {
      throw new AppError(
        "WALLET_ADDRESS_NOT_FOUND",
      );
    }

    /*
     * Fetch active supported blockchains.
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
     * Fetch GOLD balances for every active blockchain.
     */
    const blockchainBalances =
      await Promise.all(
        supportedBlockchains.map(
          (blockchain) =>
            getSupportedBlockchainBalance(
              blockchain,
              context.wallet_address,
            ),
        ),
      );

    /*
     * Build dashboard using multi-chain balances.
     */
    const {
      data: dashboard,
      error: dashboardError,
    } = await authSupabase.rpc(
      "build_my_agent_dashboard",
      {
        p_blockchain_balances:
          blockchainBalances,
      },
    );

    if (dashboardError) {
      console.error(
        "Agent dashboard RPC failed",
        {
          code: dashboardError.code,
          message: dashboardError.message,
          details: dashboardError.details,
          hint: dashboardError.hint,
        },
      );

      throw new AppError(
        dashboardError.message ||
          "FAILED_TO_FETCH_AGENT_DASHBOARD",
      );
    }

    if (!dashboard) {
      throw new AppError(
        "AGENT_DASHBOARD_NOT_FOUND",
      );
    }

    return successResponse(
      dashboard,
    );
  } catch (error) {
    console.error(
      "AGENT_DASHBOARD_ERROR",
      error,
    );

    return errorResponse(
      error,
    );
  }
});