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
} from "../../_shared/blockchain/client.ts";

import {
  isAddress,
} from "ethers";

type TreasuryContext = {
  user_id: string;
  country_code: string;
  wallet_address: string | null;
};

Deno.serve(async (request: Request) => {
  try {
    /*
     * Validate request method.
     */
    if (request.method !== "POST") {
      throw new AppError(
        "METHOD_NOT_ALLOWED",
      );
    }

    const authSupabase =
      createSupabaseClient(request);

    /*
     * Validate the authenticated Treasury user
     * before making blockchain requests.
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

    const context = (
      contextRows as TreasuryContext[] | null
    )?.[0];

    if (!context?.user_id) {
      throw new AppError(
        "TREASURY_NOT_AUTHORIZED",
      );
    }

    /*
     * Validate the Treasury blockchain wallet
     * address returned by the context RPC.
     */
    const walletAddress =
      context.wallet_address?.trim();

    if (
      !walletAddress ||
      !isAddress(walletAddress)
    ) {
      throw new AppError(
        "INVALID_TREASURY_WALLET_ADDRESS",
      );
    }

    /*
     * Fetch all active supported blockchains
     * through the authorized SQL function.
     */
    const {
      data: blockchainRows,
      error: blockchainsError,
    } = await authSupabase.rpc(
      "fetch_active_supported_blockchains",
    );

    if (blockchainsError) {
      console.error(
        "Supported blockchains RPC failed",
        {
          code: blockchainsError.code,
          message: blockchainsError.message,
          details: blockchainsError.details,
          hint: blockchainsError.hint,
        },
      );

      throw new AppError(
        blockchainsError.message ||
          "FAILED_TO_FETCH_SUPPORTED_BLOCKCHAINS",
      );
    }

    const activeBlockchains =
      (blockchainRows ?? []) as
        SupportedBlockchainConfig[];

    /*
     * Validate blockchain configurations
     * before making external RPC requests.
     */
    for (const blockchain of activeBlockchains) {
      if (
        !blockchain.code?.trim() ||
        !blockchain.rpc_url?.trim() ||
        !blockchain.contract_address?.trim() ||
        !blockchain.native_currency_code?.trim() ||
        !Number.isSafeInteger(
          Number(blockchain.chain_id),
        ) ||
        Number(blockchain.chain_id) <= 0
      ) {
        console.error(
          "Invalid blockchain configuration",
          {
            blockchain_code:
              blockchain.code,
          },
        );

        throw new AppError(
          "INVALID_SUPPORTED_BLOCKCHAIN_CONFIG",
        );
      }
    }

    /*
     * Fetch blockchain balances in parallel.
     *
     * Each blockchain uses its own:
     * - RPC URL
     * - Chain ID
     * - Token contract address
     *
     * The wallet address comes from
     * public.users.wallet_address.
     *
     * Returned values:
     * - token_supply: total minted tokens
     * - balance: Treasury wallet token balance
     * - gas_balance: Treasury wallet native balance
     */
    const blockchainBalances =
      await Promise.all(
        activeBlockchains.map(
          async (blockchain) => {
            try {
              return await getSupportedBlockchainBalance(
                blockchain,
                walletAddress,
              );
            } catch (error) {
              console.error(
                "Blockchain balance fetch failed",
                {
                  blockchain_code:
                    blockchain.code,
                  error,
                },
              );

              throw new AppError(
                "FAILED_TO_FETCH_BLOCKCHAIN_BALANCE",
              );
            }
          },
        ),
      );

    /*
     * Build the Treasury dashboard using
     * the blockchain balances array.
     */
    const {
      data: dashboard,
      error: dashboardError,
    } = await authSupabase.rpc(
      "build_my_treasury_dashboard",
      {
        p_blockchain_balances:
          blockchainBalances,
      },
    );

    if (dashboardError) {
      console.error(
        "Treasury dashboard RPC failed",
        {
          code: dashboardError.code,
          message: dashboardError.message,
          details: dashboardError.details,
          hint: dashboardError.hint,
        },
      );

      throw new AppError(
        dashboardError.message ||
          "FAILED_TO_FETCH_TREASURY_DASHBOARD",
      );
    }

    return successResponse(dashboard);
  } catch (error) {
    console.error(
      "TREASURY_DASHBOARD_ERROR",
      error,
    );

    return errorResponse(error);
  }
});

// import {
//   errorResponse,
//   successResponse,
// } from "../../_shared/api-response.ts";

// import {
//   createSupabaseClient,
// } from "../../_shared/supabase-client.ts";

// import {
//   AppError,
// } from "../../_shared/app-error.ts";

// import {
//   getRelayerGasBalance,
//   getTotalSupply,
// } from "../../_shared/blockchain/balances.ts";

// type TreasuryContext = {
//   user_id: string;
//   country_code: string;
// };

// Deno.serve(async (request: Request) => {
//   try {
//     if (request.method !== "POST") {
//       throw new AppError(
//         "METHOD_NOT_ALLOWED",
//       );
//     }

//     const authSupabase =
//       createSupabaseClient(request);

//     /*
//      * Validate the treasury role before making
//      * blockchain requests.
//      */
//     const {
//       data: contextRows,
//       error: contextError,
//     } = await authSupabase.rpc(
//       "fetch_my_treasury_dashboard_context",
//     );

//     if (contextError) {
//       console.error(
//         "Treasury context RPC failed",
//         {
//           code: contextError.code,
//           message: contextError.message,
//           details: contextError.details,
//           hint: contextError.hint,
//         },
//       );

//       throw new AppError(
//         contextError.message ||
//           "FAILED_TO_FETCH_TREASURY_CONTEXT",
//       );
//     }

//     const context =
//       (
//         contextRows as
//           TreasuryContext[] | null
//       )?.[0];

//     if (!context?.user_id) {
//       throw new AppError(
//         "TREASURY_NOT_AUTHORIZED",
//       );
//     }

//     /*
//      * Fetch both blockchain values once and in parallel.
//      */
//     const [
//       gasBalance,
//       totalSupply,
//     ] = await Promise.all([
//       getRelayerGasBalance(),
//       getTotalSupply(),
//     ]);

//     const {
//       data: dashboard,
//       error: dashboardError,
//     } = await authSupabase.rpc(
//       "build_my_treasury_dashboard",
//       {
//         p_token_supply:
//           totalSupply.token_balance,

//         p_gas_balance:
//           gasBalance,
//       },
//     );

//     if (dashboardError) {
//       console.error(
//         "Treasury dashboard RPC failed",
//         {
//           code: dashboardError.code,
//           message:
//             dashboardError.message,
//           details:
//             dashboardError.details,
//           hint:
//             dashboardError.hint,
//         },
//       );

//       throw new AppError(
//         dashboardError.message ||
//           "FAILED_TO_FETCH_TREASURY_DASHBOARD",
//       );
//     }

//     return successResponse(
//       dashboard,
//     );
//   } catch (error) {
//     console.error(
//       "TREASURY_DASHBOARD_ERROR",
//       error,
//     );

//     return errorResponse(error);
//   }
// });