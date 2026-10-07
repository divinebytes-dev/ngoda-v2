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


type UpsertSupportedCurrencyBody = {
  currency_code?: unknown;
  name?: unknown;
  decimals?: unknown;
  symbol?: unknown;
  rate_url?: unknown;
  is_active?: unknown;
};


function parseRequiredString(
  value: unknown,
  errorMessage: string,
): string {
  if (
    typeof value !== "string" ||
    value.trim() === ""
  ) {
    throw new AppError(
      errorMessage,
      400,
    );
  }

  return value.trim();
}


function parseInteger(
  value: unknown,
  errorMessage: string,
): number {
  if (
    typeof value !== "number" ||
    !Number.isInteger(value)
  ) {
    throw new AppError(
      errorMessage,
      400,
    );
  }

  return value;
}


function parseBoolean(
  value: unknown,
  errorMessage: string,
): boolean {
  if (typeof value !== "boolean") {
    throw new AppError(
      errorMessage,
      400,
    );
  }

  return value;
}


Deno.serve(async (req: Request) => {
  try {
    if (req.method !== "POST") {
      throw new AppError(
        "METHOD_NOT_ALLOWED",
        405,
      );
    }

    const supabase =
      createSupabaseClient(req);

    /*
     * Authentication.
     */
    const {
      data: {
        user,
      },
      error: userError,
    } = await supabase.auth.getUser();

    if (
      userError ||
      !user
    ) {
      throw new AppError(
        "UNAUTHORIZED",
        401,
      );
    }

    /*
     * Parse body.
     */
    let body: UpsertSupportedCurrencyBody;

    try {
      body = await req.json();
    } catch {
      throw new AppError(
        "INVALID_REQUEST_BODY",
        400,
      );
    }

    const currencyCode =
      parseRequiredString(
        body.currency_code,
        "CURRENCY_CODE_REQUIRED",
      ).toLowerCase();

    const name =
      parseRequiredString(
        body.name,
        "CURRENCY_NAME_REQUIRED",
      );

    const symbol =
      parseRequiredString(
        body.symbol,
        "CURRENCY_SYMBOL_REQUIRED",
      );

    const decimals =
      parseInteger(
        body.decimals,
        "DECIMALS_REQUIRED",
      );

    const rateUrl =
      parseRequiredString(
        body.rate_url,
        "RATE_URL_REQUIRED",
      );

    const isActive =
      parseBoolean(
        body.is_active,
        "IS_ACTIVE_REQUIRED",
      );

    /*
     * ISO-style currency code.
     *
     * Examples:
     * usd
     * zar
     * bwp
     * zig
     */
    if (
      !/^[a-z]{3}$/.test(currencyCode)
    ) {
      throw new AppError(
        "INVALID_CURRENCY_CODE",
        400,
      );
    }

    if (
      decimals < 0 ||
      decimals > 18
    ) {
      throw new AppError(
        "INVALID_DECIMALS",
        400,
      );
    }

    /*
     * Basic URL validation.
     */
    try {
      new URL(rateUrl);
    } catch {
      throw new AppError(
        "INVALID_RATE_URL",
        400,
      );
    }

    /*
     * Execute protected RPC.
     */
    const {
      data,
      error,
    } = await supabase.rpc(
      "upsert_supported_currency",
      {
        p_currency_code: currencyCode,
        p_name: name,
        p_symbol: symbol,
        p_decimals: decimals,
        p_rate_url: rateUrl,
        p_is_active: isActive,
      },
    );

    if (error) {
      console.error(
        "upsert_supported_currency failed:",
        error,
      );

      if (
        error.code === "42501" &&
        error.message === "UNAUTHORIZED"
      ) {
        throw new AppError(
          "UNAUTHORIZED",
          401,
        );
      }

      if (
        error.code === "42501" &&
        error.message === "FORBIDDEN"
      ) {
        throw new AppError(
          "FORBIDDEN",
          403,
        );
      }

      if (
        error.message === "INVALID_DECIMALS"
      ) {
        throw new AppError(
          "INVALID_DECIMALS",
          400,
        );
      }

      throw new AppError(
        error.message ||
          "FAILED_TO_UPDATE_SUPPORTED_CURRENCY",
        400,
      );
    }

    return successResponse(data);
  } catch (error) {
    console.error(
      "Upsert supported currency error:",
      error,
    );

    return errorResponse(error);
  }
});