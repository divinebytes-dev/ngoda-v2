import { formatUnits } from "ethers";
import type {
  SupportedBlockchainConfig,
} from "../../_shared/types/supported_blockchain_config.ts";

// supabase/functions/loan-preview/index.ts

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


type LoanPreviewContext = {
  wallet_address: string;
  country_code: string;
};


type RpcError = {
  code?: string;
  message: string;
  details?: string | null;
  hint?: string | null;
};


type RpcResult = {
  data: unknown;
  error: RpcError | null;
};


type UntypedRpcClient = {
  rpc(
    functionName: string,
    parameters?: Record<string, unknown>,
  ): Promise<RpcResult>;
};


type LoanPreviewRequest = {
  required_amount?:
    | string
    | number;
};


function getErrorMessage(
  error: unknown,
  fallback: string,
): string {
  if (
    error instanceof Error &&
    error.message
  ) {
    return error.message;
  }

  if (typeof error === "string") {
    return error;
  }

  return fallback;
}


Deno.serve(async (request: Request) => {
  try {
    if (request.method !== "POST") {
      throw new AppError(
        "METHOD_NOT_ALLOWED",
      );
    }

    const authSupabase =
      createSupabaseClient(request);

    const rpcClient =
      authSupabase as unknown as
        UntypedRpcClient;

    let body: LoanPreviewRequest;

    try {
      body = await request.json();
    } catch {
      throw new AppError(
        "INVALID_REQUEST_BODY",
      );
    }

    if (!body || typeof body !== "object" || Array.isArray(body)) {
      throw new AppError("INVALID_REQUEST_BODY");
    }
    if (body.required_amount !== undefined &&
        typeof body.required_amount !== "string" &&
        typeof body.required_amount !== "number") {
      throw new AppError("INVALID_LOAN_AMOUNT");
    }
    if (typeof body.required_amount === "number" &&
        !Number.isFinite(body.required_amount)) {
      throw new AppError("INVALID_LOAN_AMOUNT");
    }

    const requiredAmount =
      body.required_amount;

    if (
      requiredAmount ===
        undefined ||
      requiredAmount === null ||
      String(requiredAmount)
          .trim() === ""
    ) {
      throw new AppError(
        "MISSING_REQUIRED_FIELDS",
      );
    }

    /*
     * Fetch the authenticated user's trusted wallet context.
     *
     * The database checks:
     * - authentication
     * - the required user role
     * - active user status
     * - wallet configuration
     * - country configuration
     */
    const {
      data: contextData,
      error: contextError,
    } = await rpcClient.rpc(
      "fetch_my_loan_preview_context",
    );

    if (contextError) {
      console.error(
        "LOAN_PREVIEW_CONTEXT_FAILED",
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
          "LOAN_PREVIEW_CONTEXT_FAILED",
      );
    }

    const contextRows =
      contextData as
        LoanPreviewContext[] | null;

    const context =
      contextRows?.[0];

    if (!context) {
      throw new AppError(
        "LOAN_PREVIEW_CONTEXT_NOT_FOUND",
      );
    }

    if (!context.wallet_address) {
      throw new AppError(
        "USER_WALLET_NOT_CONFIGURED",
      );
    }

    if (!context.country_code) {
      throw new AppError(
        "USER_COUNTRY_NOT_CONFIGURED",
      );
    }

    /*
     * Fetch the user's current on-chain Gold balance.
     */
      const { data: configData, error: configError } =
        await rpcClient.rpc("fetch_active_supported_blockchains");

      if (configError) {
        throw new AppError(configError.message || "LOAN_PREVIEW_BLOCKCHAIN_CONFIG_FAILED");
      }
      if (!Array.isArray(configData)) {
        throw new AppError("INVALID_LOAN_BLOCKCHAIN_CONFIG");
      }

      const codes = new Set<string>();
      let totalGoldUnits = 0n;
      for (const rawConfig of configData) {
        if (!rawConfig || typeof rawConfig !== "object" ||
            typeof rawConfig.code !== "string" ||
            !/^[a-z0-9_-]+$/.test(rawConfig.code) ||
            codes.has(rawConfig.code)) {
          throw new AppError("INVALID_LOAN_BLOCKCHAIN_CONFIG");
        }
        codes.add(rawConfig.code);
        const chainId = Number(rawConfig.chain_id);
        if (!Number.isSafeInteger(chainId) || chainId <= 0) {
          throw new AppError("INVALID_BLOCKCHAIN_CHAIN_ID");
        }
        const blockchain = {
          ...rawConfig,
          chain_id: chainId,
        } as SupportedBlockchainConfig;

        // Read every active chain. Any failed read stops the preview.
        const balances = await getBlockchainWalletBalances(
          blockchain,
          context.wallet_address,
        );
        const tokenBalance = balances.token_balance;
        if (typeof tokenBalance !== "string" ||
            !/^\d+(?:\.\d+)?$/.test(tokenBalance)) {
          throw new AppError("INVALID_BLOCKCHAIN_TOKEN_BALANCE");
        }
        // Integer arithmetic avoids floating-point rounding. Truncate each
        // chain to Ngoda's six GOLD decimals before adding its balance.
        const [whole, fraction = ""] = tokenBalance.split(".");
        const onChainUnits = BigInt(whole) * 1_000_000n +
          BigInt((fraction + "000000").slice(0, 6));
        totalGoldUnits += onChainUnits;
      }
      const tokenBalance = formatUnits(totalGoldUnits, 6);

    /*
     * PostgreSQL performs all loan calculations using numeric
     * values. Passing the amount as text avoids JavaScript
     * floating-point conversion.
     */
    const {
      data: previewData,
      error: previewError,
    } = await rpcClient.rpc(
      "preview_my_loan",
      {
        p_requested_amount:
          String(requiredAmount),

        p_token_balance:
          tokenBalance,

        p_currency_code:
          "usd",
      },
    );

    if (previewError) {
      console.error(
        "LOAN_PREVIEW_RPC_FAILED",
        {
          code:
            previewError.code,

          message:
            previewError.message,

          details:
            previewError.details,

          hint:
            previewError.hint,

          walletAddress:
            context.wallet_address,

          countryCode:
            context.country_code,
        },
      );

      throw new AppError(
        previewError.message ||
          "LOAN_PREVIEW_FAILED",
      );
    }

    if (!previewData) {
      throw new AppError(
        "LOAN_PREVIEW_NOT_FOUND",
      );
    }

    return successResponse(
      previewData,
    );
  } catch (error) {
    console.error(
      "LOAN_PREVIEW_ERROR",
      {
        error:
          getErrorMessage(
            error,
            "LOAN_PREVIEW_FAILED",
          ),
      },
    );

    return errorResponse(
      error,
      "LOAN_PREVIEW_FAILED",
    );
  }
});
