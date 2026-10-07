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


type AgentDashboardContext = {
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
     * Fetch the authenticated active agent's blockchain
     * wallet address.
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
          "FAILED_TO_FETCH_AGENT_DASHBOARD",
      );
    }

    const context =
      (
        contextRows as unknown as
          AgentDashboardContext[] | null
      )?.[0];

    if (!context?.wallet_address) {
      throw new AppError(
        "WALLET_ADDRESS_NOT_FOUND",
      );
    }

    /*
     * Fetch the blockchain gold-token balance required
     * by loanSummary.
     */
    const blockchainBalances =
      await getBlockchainWalletBalances(
        context.wallet_address,
      );

    /*
     * Build the agent dashboard using the trusted
     * blockchain token balance.
     */
    const {
      data: dashboard,
      error: dashboardError,
    } = await authSupabase.rpc(
      "build_my_agent_dashboard",
      {
        p_token_balance:
          blockchainBalances.token_balance,
      },
    );

    if (dashboardError) {
      console.error(
        "Agent dashboard RPC failed",
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

// import {
//   errorResponse,
//   successResponse,
// } from "../_shared/api-response.ts";

// import {
//   createSupabaseClient,
// } from "../_shared/supabase-client.ts";

// import {
//   AppError,
// } from "../_shared/app-error.ts";

// Deno.serve(async (request: Request) => {
//   try {
//     if (request.method !== "POST") {
//       throw new AppError(
//         "METHOD_NOT_ALLOWED",
//       );
//     }

//     const authSupabase =
//       createSupabaseClient(request);

//     const {
//       data: dashboard,
//       error: dashboardError,
//     } = await authSupabase.rpc(
//       "build_my_agent_dashboard",
//     );

//     if (dashboardError) {
//       console.error(
//         "Agent dashboard RPC failed",
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
//           "FAILED_TO_FETCH_AGENT_DASHBOARD",
//       );
//     }

//     return successResponse(
//       dashboard,
//     );
//   } catch (error) {
//     console.error(
//       "AGENT_DASHBOARD_ERROR",
//       error,
//     );

//     return errorResponse(error);
//   }
// });