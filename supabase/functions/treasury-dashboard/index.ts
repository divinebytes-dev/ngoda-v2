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
  getSupportedBlockchainBalance,
} from "../../_shared/blockchain/balances.ts";

import type {
  SupportedBlockchainConfig,
} from "../../_shared/types/supported_blockchain_config.ts";

import {
  isAddress,
} from "ethers";

type TreasuryContext = {
  user_id: string;
  country_code: string;
  wallet_address: string | null;
};

type RelayerBalance = {
  blockchain_code: string;
  chain_id: number;
  native_currency_code: string;
  gas_balance: string;
};

function isRecord(
  value: unknown,
): value is Record<string, unknown> {
  return (
    typeof value === "object" &&
    value !== null &&
    !Array.isArray(value)
  );
}

function getErrorMessage(
  error: unknown,
): string {
  return error instanceof Error
    ? error.message
    : String(error);
}

Deno.serve(
  async (request: Request): Promise<Response> => {
    try {
      if (request.method !== "POST") {
        throw new AppError(
          "METHOD_NOT_ALLOWED",
          405,
        );
      }

      const authSupabase =
        createSupabaseClient(request);

      /*
       * Authorize Treasury before making external
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
          "TREASURY_CONTEXT_RPC_FAILED",
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
          403,
        );
      }

      /*
       * Preserve the existing Treasury wallet source.
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

      const {
        data: blockchainRows,
        error: blockchainsError,
      } = await authSupabase.rpc(
        "fetch_active_supported_blockchains",
      );

      if (blockchainsError) {
        console.error(
          "SUPPORTED_BLOCKCHAINS_RPC_FAILED",
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

      if (!Array.isArray(blockchainRows)) {
        throw new AppError(
          "INVALID_SUPPORTED_BLOCKCHAINS_RESPONSE",
        );
      }

      const activeBlockchains =
        blockchainRows.map(
          (row): SupportedBlockchainConfig => {
            const chainId = Number(row.chain_id);

            if (
              !row.code?.trim() ||
              !row.rpc_url?.trim() ||
              !row.contract_address?.trim() ||
              !isAddress(row.contract_address.trim()) ||
              !row.native_currency_code?.trim() ||
              !Number.isSafeInteger(chainId) ||
              chainId <= 0
            ) {
              console.error(
                "INVALID_BLOCKCHAIN_CONFIGURATION",
                {
                  blockchain_code: row.code,
                },
              );

              throw new AppError(
                "INVALID_SUPPORTED_BLOCKCHAIN_CONFIG",
              );
            }

            return {
              code: row.code.trim().toLowerCase(),
              chain_id: chainId,
              rpc_url: row.rpc_url.trim(),
              contract_address:
                row.contract_address.trim(),
              native_currency_code:
                row.native_currency_code.trim(),
            };
          },
        );

      /*
       * Read Treasury and relayer balances per chain.
       *
       * The relayer helper uses RELAYER_ADDRESS,
       * with the selected blockchain's RPC.
       *
       * A failed read must not be displayed as zero.
       */
      const results = await Promise.all(
        activeBlockchains.map(
          async (blockchain) => {
            try {
              const [
                treasuryBalance,
                relayerGasBalance,
              ] = await Promise.all([
                getSupportedBlockchainBalance(
                  blockchain,
                  walletAddress,
                ),
                getRelayerGasBalance(blockchain),
              ]);

              const relayerBalance: RelayerBalance = {
                blockchain_code: blockchain.code,
                chain_id: blockchain.chain_id,
                native_currency_code:
                  blockchain.native_currency_code,
                gas_balance: relayerGasBalance,
              };

              return {
                treasuryBalance,
                relayerBalance,
              };
            } catch (error) {
              console.error(
                "TREASURY_DASHBOARD_BLOCKCHAIN_READ_FAILED",
                {
                  blockchain_code: blockchain.code,
                  chain_id: blockchain.chain_id,
                  error: getErrorMessage(error),
                },
              );

              throw new AppError(
                "FAILED_TO_FETCH_BLOCKCHAIN_BALANCE",
                503,
              );
            }
          },
        ),
      );

      const blockchainBalances = results.map(
        (result) => result.treasuryBalance,
      );

      const relayerBalances = results.map(
        (result) => result.relayerBalance,
      );

      /*
       * Preserve the existing SQL input and financial
       * dashboard calculations.
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
          "TREASURY_DASHBOARD_RPC_FAILED",
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

      if (!isRecord(dashboard)) {
        throw new AppError(
          "INVALID_TREASURY_DASHBOARD_RESPONSE",
          500,
        );
      }

      /*
       * Add operational relayer balances after SQL
       * has built the existing dashboard response.
       */
      return successResponse({
        ...dashboard,
        relayerBalances,
      });
    } catch (error) {
      console.error(
        "TREASURY_DASHBOARD_ERROR",
        {
          error: getErrorMessage(error),
        },
      );

      return errorResponse(error);
    }
  },
);

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
//   getSupportedBlockchainBalance,
// } from "../../_shared/blockchain/balances.ts";

// import type {
//   SupportedBlockchainConfig,
// } from "../../_shared/blockchain/client.ts";

// import {
//   isAddress,
// } from "ethers";

// type TreasuryContext = {
//   user_id: string;
//   country_code: string;
//   wallet_address: string | null;
// };

// Deno.serve(async (request: Request) => {
//   try {
//     /*
//      * Validate request method.
//      */
//     if (request.method !== "POST") {
//       throw new AppError(
//         "METHOD_NOT_ALLOWED",
//       );
//     }

//     const authSupabase =
//       createSupabaseClient(request);

//     /*
//      * Validate the authenticated Treasury user
//      * before making blockchain requests.
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

//     const context = (
//       contextRows as TreasuryContext[] | null
//     )?.[0];

//     if (!context?.user_id) {
//       throw new AppError(
//         "TREASURY_NOT_AUTHORIZED",
//       );
//     }

//     /*
//      * Validate the Treasury blockchain wallet
//      * address returned by the context RPC.
//      */
//     const walletAddress =
//       context.wallet_address?.trim();

//     if (
//       !walletAddress ||
//       !isAddress(walletAddress)
//     ) {
//       throw new AppError(
//         "INVALID_TREASURY_WALLET_ADDRESS",
//       );
//     }

//     /*
//      * Fetch all active supported blockchains
//      * through the authorized SQL function.
//      */
//     const {
//       data: blockchainRows,
//       error: blockchainsError,
//     } = await authSupabase.rpc(
//       "fetch_active_supported_blockchains",
//     );

//     if (blockchainsError) {
//       console.error(
//         "Supported blockchains RPC failed",
//         {
//           code: blockchainsError.code,
//           message: blockchainsError.message,
//           details: blockchainsError.details,
//           hint: blockchainsError.hint,
//         },
//       );

//       throw new AppError(
//         blockchainsError.message ||
//           "FAILED_TO_FETCH_SUPPORTED_BLOCKCHAINS",
//       );
//     }

//     const activeBlockchains =
//       (blockchainRows ?? []) as
//         SupportedBlockchainConfig[];

//     /*
//      * Validate blockchain configurations
//      * before making external RPC requests.
//      */
//     for (const blockchain of activeBlockchains) {
//       if (
//         !blockchain.code?.trim() ||
//         !blockchain.rpc_url?.trim() ||
//         !blockchain.contract_address?.trim() ||
//         !blockchain.native_currency_code?.trim() ||
//         !Number.isSafeInteger(
//           Number(blockchain.chain_id),
//         ) ||
//         Number(blockchain.chain_id) <= 0
//       ) {
//         console.error(
//           "Invalid blockchain configuration",
//           {
//             blockchain_code:
//               blockchain.code,
//           },
//         );

//         throw new AppError(
//           "INVALID_SUPPORTED_BLOCKCHAIN_CONFIG",
//         );
//       }
//     }

//     /*
//      * Fetch blockchain balances in parallel.
//      *
//      * Each blockchain uses its own:
//      * - RPC URL
//      * - Chain ID
//      * - Token contract address
//      *
//      * The wallet address comes from
//      * public.users.wallet_address.
//      *
//      * Returned values:
//      * - token_supply: total minted tokens
//      * - balance: Treasury wallet token balance
//      * - gas_balance: Treasury wallet native balance
//      */
//     const blockchainBalances =
//       await Promise.all(
//         activeBlockchains.map(
//           async (blockchain) => {
//             try {
//               return await getSupportedBlockchainBalance(
//                 blockchain,
//                 walletAddress,
//               );
//             } catch (error) {
//               console.error(
//                 "Blockchain balance fetch failed",
//                 {
//                   blockchain_code:
//                     blockchain.code,
//                   error,
//                 },
//               );

//               throw new AppError(
//                 "FAILED_TO_FETCH_BLOCKCHAIN_BALANCE",
//               );
//             }
//           },
//         ),
//       );

//     /*
//      * Build the Treasury dashboard using
//      * the blockchain balances array.
//      */
//     const {
//       data: dashboard,
//       error: dashboardError,
//     } = await authSupabase.rpc(
//       "build_my_treasury_dashboard",
//       {
//         p_blockchain_balances:
//           blockchainBalances,
//       },
//     );

//     if (dashboardError) {
//       console.error(
//         "Treasury dashboard RPC failed",
//         {
//           code: dashboardError.code,
//           message: dashboardError.message,
//           details: dashboardError.details,
//           hint: dashboardError.hint,
//         },
//       );

//       throw new AppError(
//         dashboardError.message ||
//           "FAILED_TO_FETCH_TREASURY_DASHBOARD",
//       );
//     }

//     return successResponse(dashboard);
//   } catch (error) {
//     console.error(
//       "TREASURY_DASHBOARD_ERROR",
//       error,
//     );

//     return errorResponse(error);
//   }
// });

// // import {
// //   errorResponse,
// //   successResponse,
// // } from "../../_shared/api-response.ts";

// // import {
// //   createSupabaseClient,
// // } from "../../_shared/supabase-client.ts";

// // import {
// //   AppError,
// // } from "../../_shared/app-error.ts";

// // import {
// //   getRelayerGasBalance,
// //   getTotalSupply,
// // } from "../../_shared/blockchain/balances.ts";

// // type TreasuryContext = {
// //   user_id: string;
// //   country_code: string;
// // };

// // Deno.serve(async (request: Request) => {
// //   try {
// //     if (request.method !== "POST") {
// //       throw new AppError(
// //         "METHOD_NOT_ALLOWED",
// //       );
// //     }

// //     const authSupabase =
// //       createSupabaseClient(request);

// //     /*
// //      * Validate the treasury role before making
// //      * blockchain requests.
// //      */
// //     const {
// //       data: contextRows,
// //       error: contextError,
// //     } = await authSupabase.rpc(
// //       "fetch_my_treasury_dashboard_context",
// //     );

// //     if (contextError) {
// //       console.error(
// //         "Treasury context RPC failed",
// //         {
// //           code: contextError.code,
// //           message: contextError.message,
// //           details: contextError.details,
// //           hint: contextError.hint,
// //         },
// //       );

// //       throw new AppError(
// //         contextError.message ||
// //           "FAILED_TO_FETCH_TREASURY_CONTEXT",
// //       );
// //     }

// //     const context =
// //       (
// //         contextRows as
// //           TreasuryContext[] | null
// //       )?.[0];

// //     if (!context?.user_id) {
// //       throw new AppError(
// //         "TREASURY_NOT_AUTHORIZED",
// //       );
// //     }

// //     /*
// //      * Fetch both blockchain values once and in parallel.
// //      */
// //     const [
// //       gasBalance,
// //       totalSupply,
// //     ] = await Promise.all([
// //       getRelayerGasBalance(),
// //       getTotalSupply(),
// //     ]);

// //     const {
// //       data: dashboard,
// //       error: dashboardError,
// //     } = await authSupabase.rpc(
// //       "build_my_treasury_dashboard",
// //       {
// //         p_token_supply:
// //           totalSupply.token_balance,

// //         p_gas_balance:
// //           gasBalance,
// //       },
// //     );

// //     if (dashboardError) {
// //       console.error(
// //         "Treasury dashboard RPC failed",
// //         {
// //           code: dashboardError.code,
// //           message:
// //             dashboardError.message,
// //           details:
// //             dashboardError.details,
// //           hint:
// //             dashboardError.hint,
// //         },
// //       );

// //       throw new AppError(
// //         dashboardError.message ||
// //           "FAILED_TO_FETCH_TREASURY_DASHBOARD",
// //       );
// //     }

// //     return successResponse(
// //       dashboard,
// //     );
// //   } catch (error) {
// //     console.error(
// //       "TREASURY_DASHBOARD_ERROR",
// //       error,
// //     );

// //     return errorResponse(error);
// //   }
// // });