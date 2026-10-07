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

type WalletPeriodEntriesRequest = {
  currency?: string;
  currency_code?: string;

  wallet_owner?: WalletOwnerType;
  walletOwner?: WalletOwnerType;

  fiscal_year?: number;
  fiscalYear?: number;

  period?: number;

  page?: number;

  page_size?: number;
  pageSize?: number;
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

    let body: WalletPeriodEntriesRequest;

    try {
      body =
        await request.json() as
          WalletPeriodEntriesRequest;
    } catch {
      throw new AppError(
        "INVALID_REQUEST_BODY",
      );
    }

    const currencyCode =
      (
        body.currency_code ??
        body.currency
      )
        ?.trim()
        .toLowerCase();

    if (!currencyCode) {
      throw new AppError(
        "CURRENCY_IS_REQUIRED",
      );
    }

    const walletOwner =
      body.wallet_owner ??
      body.walletOwner;

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

    const fiscalYear =
      Number(
        body.fiscal_year ??
          body.fiscalYear,
      );

    if (!Number.isInteger(fiscalYear)) {
      throw new AppError(
        "INVALID_FISCAL_YEAR",
      );
    }

    const period =
      Number(body.period);

    if (
      !Number.isInteger(period) ||
      period < 1 ||
      period > 12
    ) {
      throw new AppError(
        "INVALID_PERIOD",
      );
    }

    const page =
      Number(body.page ?? 1);

    if (
      !Number.isInteger(page) ||
      page < 1
    ) {
      throw new AppError(
        "INVALID_PAGE",
      );
    }

    const pageSize =
      Number(
        body.page_size ??
          body.pageSize ??
          50,
      );

    if (
      !Number.isInteger(pageSize) ||
      pageSize < 1 ||
      pageSize > 100
    ) {
      throw new AppError(
        "INVALID_PAGE_SIZE",
      );
    }

    const {
      data: result,
      error: resultError,
    } = await authSupabase.rpc(
      "get_my_wallet_period_entries",
      {
        p_currency_code:
          currencyCode,

        p_wallet_owner:
          walletOwner,

        p_fiscal_year:
          fiscalYear,

        p_period:
          period,

        p_page:
          page,

        p_page_size:
          pageSize,
      },
    );

    if (resultError) {
      console.error(
        "Wallet period entries RPC failed",
        {
          code: resultError.code,
          message:
            resultError.message,
          details:
            resultError.details,
          hint:
            resultError.hint,
        },
      );

      throw new AppError(
        resultError.message ||
          "WALLET_PERIOD_ENTRIES_FAILED",
      );
    }

    return successResponse(
      result,
    );
  } catch (error) {
    console.error(
      "WALLET_PERIOD_ENTRIES_ERROR",
      error,
    );

    return errorResponse(error);
  }
});