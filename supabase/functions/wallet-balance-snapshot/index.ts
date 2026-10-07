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

import type {
  Database,
} from "../../_shared/database.types.ts";

type WalletOwnerType =
  Database["public"]["Enums"]["WalletOwnerType"];

type WalletBalanceSnapshotRequest = {
  currency_code?: string;
  wallet_owner?: WalletOwnerType;
};

const walletOwnerTypes:
  readonly WalletOwnerType[] = [
    "customer",
    "agent",
    "treasury",
    "employee",
    "merchant",
  ];

Deno.serve(async (request: Request) => {
  try {
    if (request.method !== "POST") {
      throw new AppError(
        "METHOD_NOT_ALLOWED",
      );
    }

    const authSupabase =
      createSupabaseClient(request);

    let body: WalletBalanceSnapshotRequest;

    try {
      body =
        await request.json() as
          WalletBalanceSnapshotRequest;
    } catch {
      throw new AppError(
        "INVALID_REQUEST_BODY",
      );
    }

    const currencyCode =
      body.currency_code
        ?.trim()
        .toLowerCase();

    if (!currencyCode) {
      throw new AppError(
        "CURRENCY_IS_REQUIRED",
      );
    }

    const walletOwner =
      body.wallet_owner;

    if (!walletOwner) {
      throw new AppError(
        "WALLET_OWNER_IS_REQUIRED",
      );
    }

    if (
      !walletOwnerTypes.includes(
        walletOwner,
      )
    ) {
      throw new AppError(
        "INVALID_WALLET_OWNER",
      );
    }

    const {
      data: snapshot,
      error: snapshotError,
    } = await authSupabase.rpc(
      "get_my_wallet_balance_snapshot",
      {
        p_currency_code:
          currencyCode,

        p_wallet_owner:
          walletOwner,
      },
    );

    if (snapshotError) {
      console.error(
        "Wallet balance snapshot RPC failed",
        {
          code: snapshotError.code,
          message:
            snapshotError.message,
          details:
            snapshotError.details,
          hint:
            snapshotError.hint,
        },
      );

      throw new AppError(
        snapshotError.message ||
          "WALLET_BALANCE_SNAPSHOT_FAILED",
      );
    }

    return successResponse(
      snapshot,
    );
  } catch (error) {
    console.error(
      "WALLET_BALANCE_SNAPSHOT_ERROR",
      error,
    );

    return errorResponse(error);
  }
});