import { formatUnits } from "ethers";
import type {
  SupportedBlockchainConfig,
} from "../../_shared/types/supported_blockchain_config.ts";

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
  TransactionData,
  TransactionVerificationService,
} from "../../_shared/transaction-verification-service.ts";

import {
  getBlockchainWalletBalances,
} from "../../_shared/blockchain/balances.ts";


type AdditionalCollateralContext = {
  user_id: string;
  country_code: string;
  user_wallet_address: string;
};


type AdditionalCollateralResult = {
  success: boolean;
  collateral_required: boolean;
  requested_collateral: string;
  collateral_added: string;
  unused_collateral: string;
  remaining_required_collateral: string;
  previous_locked_collateral: string;
  new_locked_collateral: string;
  loans_adjusted: number;
};


Deno.serve(async (request: Request) => {
  try {
    /*
     * ======================================================
     * HTTP METHOD
     * ======================================================
     */
    if (request.method !== "POST") {
      throw new AppError(
        "METHOD_NOT_ALLOWED",
        405,
      );
    }


    /*
     * ======================================================
     * AUTHENTICATED CLIENT
     * ======================================================
     */
    const authSupabase =
      createSupabaseClient(
        request,
      );


    /*
     * ======================================================
     * REQUEST BODY
     * ======================================================
     *
     * Additional collateral is a single-party operation.
     *
     * There is therefore:
     *
     * - transaction
     * - no sender approval
     * - no receiver approval
     * - no transaction state
     */
    let body: {
      transaction?: TransactionData;
    };


    try {
      body =
        await request.json();
    } catch {
      throw new AppError(
        "INVALID_REQUEST_BODY",
        400,
      );
    }


    if (!body || typeof body !== "object" || Array.isArray(body)) {
      throw new AppError("INVALID_REQUEST_BODY", 400);
    }

    const transaction =
      body.transaction;


    if (!transaction || typeof transaction !== "object" ||
        Array.isArray(transaction)) {
      throw new AppError(
        "TRANSACTION_DATA_MISSING",
        400,
      );
    }


    /*
     * ======================================================
     * TRUSTED USER CONTEXT
     * ======================================================
     *
     * PostgreSQL derives the caller from auth.uid().
     *
     * The wallet address supplied here is therefore trusted
     * and is used for signature verification and blockchain
     * balance lookup.
     */
    const {
      data: contextRows,
      error: contextError,
    } = await authSupabase.rpc(
      "fetch_my_additional_collateral_context",
    );


    if (contextError) {
      console.error(
        "ADDITIONAL_COLLATERAL_CONTEXT_FAILED",
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
          "ADDITIONAL_COLLATERAL_CONTEXT_FAILED",
      );
    }


    const context =
      (
        contextRows as unknown as
          AdditionalCollateralContext[] | null
      )?.[0];


    if (!context) {
      throw new AppError(
        "ADDITIONAL_COLLATERAL_CONTEXT_NOT_FOUND",
      );
    }


    if (!context.user_id) {
      throw new AppError(
        "USER_NOT_FOUND",
      );
    }


    if (!context.country_code) {
      throw new AppError(
        "USER_COUNTRY_NOT_CONFIGURED",
      );
    }


    if (!context.user_wallet_address) {
      throw new AppError(
        "USER_WALLET_ADDRESS_NOT_FOUND",
      );
    }


    /*
     * ======================================================
     * VERIFY USER SIGNATURE
     * ======================================================
     *
     * This is a single-party operation.
     *
     * transaction.ms is the user's signature.
     *
     * Always verify the signed payload BEFORE interpreting
     * transaction.a as the requested collateral amount.
     */
    const signatureValid =
      TransactionVerificationService
        .verifyTransactionSignature(
          transaction,
          context.user_wallet_address,
        );


    if (!signatureValid) {
      throw new AppError(
        "TRANSACTION_SIGNATURE_VERIFICATION_FAILED",
      );
    }


    /*
     * ======================================================
     * VALIDATE TRANSACTION STRUCTURE
     * ======================================================
     *
     * There is intentionally:
     *
     * - no transaction version restriction;
     * - no transaction timestamp validation.
     */
    TransactionVerificationService
      .validateTransactionFields(
        transaction,
      );


    /*
     * ======================================================
     * CURRENCY
     * ======================================================
     */
    const currency =
      String(
        transaction.c,
      )
        .trim()
        .toLowerCase();


    if (currency !== "gold") {
      throw new AppError(
        "INVALID_COLLATERAL_CURRENCY",
      );
    }


    /*
     * ======================================================
     * SIGNED COLLATERAL AMOUNT
     * ======================================================
     *
     * transaction.a is signed in minor units.
     *
     * Example:
     *
     * transaction.a = 10
     *
     * becomes:
     *
     * 0.10 gold
     *
     * Conversion is deliberately performed only AFTER
     * signature verification.
     */
    const signedAmount =
      Number(
        transaction.a,
      );


    if (
      !Number.isSafeInteger(
        signedAmount,
      ) ||
      signedAmount <= 0
    ) {
      throw new AppError(
        "INVALID_COLLATERAL_AMOUNT",
      );
    }


    // Preserve the existing signed convention: transaction.a / 100 grams.
    // Convert with integer arithmetic after signature verification.
    const requestedCollateralText = formatUnits(BigInt(signedAmount), 2);

    /*
     * ======================================================
     * REFERENCE
     * ======================================================
     */
    const reference =
      String(
        transaction.r,
      ).trim();


    if (!reference) {
      throw new AppError(
        "REFERENCE_REQUIRED",
      );
    }


    /*
     * ======================================================
     * BLOCKCHAIN GOLD BALANCE
     * ======================================================
     *
     * The user's available token balance must come directly
     * from the blockchain.
     *
     * Flutter must not provide the authoritative balance.
     */
      const { data: configData, error: configError } =
        await authSupabase.rpc("fetch_active_supported_blockchains");

      if (configError) {
        throw new AppError(configError.message || "ADDITIONAL_COLLATERAL_BLOCKCHAIN_CONFIG_FAILED");
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

        // Read every active chain. Any failed read stops the top-up.
        const balances = await getBlockchainWalletBalances(
          blockchain,
          context.user_wallet_address,
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
     * ======================================================
     * EXECUTE COLLATERAL ALLOCATION
     * ======================================================
     *
     * PostgreSQL determines how much of the authorised
     * amount is actually required.
     *
     * Example:
     *
     * user authorises 0.100000
     * loans only require 0.050000
     *
     * actual collateral added = 0.050000
     * unused collateral       = 0.050000
     */
    const {
      data,
      error: collateralError,
    } = await authSupabase.rpc(
      "execute_my_additional_collateral",
      {
        p_requested_collateral:
          requestedCollateralText,

        p_token_balance:
          tokenBalance.trim(),

        p_reference:
          reference,
      },
    );

    if (collateralError) {
      console.error(
        "ADDITIONAL_COLLATERAL_FAILED",
        {
          code:
            collateralError.code,

          message:
            collateralError.message,

          details:
            collateralError.details,

          hint:
            collateralError.hint,

          userId:
            context.user_id,

          reference,

          requestedCollateral:
            requestedCollateralText,

          tokenBalance:
            tokenBalance.trim(),
        },
      );


      if (collateralError.message.includes(
        "LOAN_POSITION_LIQUIDATION_IN_PROGRESS",
      )) {
        throw new AppError("LOAN_POSITION_LIQUIDATION_IN_PROGRESS", 409);
      }

      if (
        collateralError.code === "23505" ||
        collateralError.message.includes(
          "TRANSACTION_REPLAY",
        )
      ) {
        throw new AppError(
          "TRANSACTION_REPLAY",
          409,
        );
      }


      throw new AppError(
        collateralError.message ||
          "ADDITIONAL_COLLATERAL_FAILED",
      );
    }


    /*
     * execute_my_additional_collateral RETURNS TABLE,
     * therefore Supabase returns an array.
     */
    const result =
      (
        data as unknown as
          AdditionalCollateralResult[] | null
      )?.[0];


    if (!result) {
      throw new AppError(
        "ADDITIONAL_COLLATERAL_RESULT_NOT_FOUND",
      );
    }


    if (!result.success) {
      throw new AppError(
        "ADDITIONAL_COLLATERAL_FAILED",
      );
    }


    /*
     * ======================================================
     * RESPONSE
     * ======================================================
     *
     * No transaction state exists for this operation.
     *
     * The HTTP response itself is the operation result.
     */
    return successResponse({
      success:
        result.success,

      reference,

      currency:
        "gold",

      collateral_required:
        result.collateral_required,

      requested_collateral:
        result.requested_collateral,

      collateral_added:
        result.collateral_added,

      unused_collateral:
        result.unused_collateral,

      remaining_required_collateral:
        result
          .remaining_required_collateral,

      previous_locked_collateral:
        result
          .previous_locked_collateral,

      new_locked_collateral:
        result
          .new_locked_collateral,

      loans_adjusted:
        result.loans_adjusted,
    });
  } catch (error) {
    return errorResponse(
      error,
      "ADDITIONAL_COLLATERAL_FAILED",
    );
  }
});
