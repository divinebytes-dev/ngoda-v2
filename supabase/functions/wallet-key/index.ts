import {
  errorResponse,
  successResponse,
} from "../../_shared/api-response.ts";

import {
  createSupabaseClient,
  createSupabaseServiceClient,
} from "../../_shared/supabase-client.ts";

import {
  fetchAuthenticatedUser,
  fetchUserWithId,
  requireRole,
} from "../../_shared/user-service.ts";

import {
  Role,
} from "../../_shared/enums.ts";

import {
  deriveWallet,
} from "../../_shared/blockchain/wallet.ts";


import {
  AppError,
} from "../../_shared/app-error.ts";


Deno.serve(async (request: Request) => {
  try {
    /*
     * Private-key recovery must be an authenticated action.
     */
    if (request.method !== "POST") {
      throw new AppError(
        "METHOD_NOT_ALLOWED",
      );
    }

    /*
     * Validate the caller's JWT.
     */
    const authSupabase =
      createSupabaseClient(request);

    const authUser =
      await fetchAuthenticatedUser(
        authSupabase,
      );

    /*
     * Fetch the database user through the protected
     * server-scoped client.
     */
    const serviceSupabase =
      createSupabaseServiceClient();

    const user = await fetchUserWithId(
      serviceSupabase,
      authUser.id,
    );

    requireRole(user, [
      Role.customer,
      Role.treasury,
      Role.finance,
      Role.agent,
      Role.admin,
      Role.accounts,
      Role.merchant,
      Role.vendor,
    ]);

    /*
     * Validate the wallet index before using it in the
     * derivation path.
     */
    const walletIndex =
      Number(user.wallet_index);

    if (
      !Number.isSafeInteger(walletIndex) ||
      walletIndex < 0
    ) {
      throw new AppError(
        "INVALID_WALLET_INDEX",
      );
    }

    if (!user.wallet_address) {
      throw new AppError(
        "WALLET_ADDRESS_NOT_FOUND",
      );
    }

    const mnemonic =
      Deno.env
        .get("MASTER_MNEMONIC")
        ?.trim();

    if (!mnemonic) {
      console.error(
        "Wallet recovery configuration missing",
        {
          authenticatedUserId:
            authUser.id,
        },
      );

      throw new AppError(
        "MASTER_MNEMONIC_NOT_CONFIGURED",
      );
    }

    let derivedWallet: {
      address: string;
      privateKey: string;
    };

    try {
      derivedWallet = deriveWallet(
        mnemonic,
        walletIndex,
      );
    } catch (error) {
      /*
       * Do not log the mnemonic or private key.
       */
      console.error(
        "Wallet derivation failed",
        {
          authenticatedUserId:
            authUser.id,
          message:
            error instanceof Error
              ? error.message
              : "UNKNOWN_DERIVATION_ERROR",
        },
      );

      throw new AppError(
        "WALLET_DERIVATION_FAILED",
      );
    }

    /*
     * Prevent returning a key derived from an incorrect or
     * corrupted wallet index.
     */
    if (
      derivedWallet.address.toLowerCase() !==
      user.wallet_address.toLowerCase()
    ) {
      console.error(
        "Derived wallet address mismatch",
        {
          authenticatedUserId:
            authUser.id,
          storedAddress:
            user.wallet_address,
          derivedAddress:
            derivedWallet.address,
        },
      );

      throw new AppError(
        "WALLET_ADDRESS_MISMATCH",
      );
    }

    /*
     * Preserve the old API response shape by returning the
     * private-key string directly inside successResponse.
     */
    const response =
      successResponse(
        derivedWallet.privateKey,
      );

    /*
     * Prevent browsers and intermediate systems from caching
     * the private-key response.
     */
    response.headers.set(
      "Cache-Control",
      "no-store, no-cache, must-revalidate, private",
    );

    response.headers.set(
      "Pragma",
      "no-cache",
    );

    response.headers.set(
      "Expires",
      "0",
    );

    return response;
  } catch (error) {
    /*
     * Never include the mnemonic or private key in this log.
     */
    console.error(
      "Wallet recovery failed",
      {
        message:
          error instanceof Error
            ? error.message
            : "FAILED_TO_GENERATE_KEY",
      },
    );

    const response =
      errorResponse(
        error,
        "FAILED_TO_GENERATE_KEY",
      );

    response.headers.set(
      "Cache-Control",
      "no-store",
    );

    return response;
  }
});