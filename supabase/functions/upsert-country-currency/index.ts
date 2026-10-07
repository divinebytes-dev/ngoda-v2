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


type UpsertCountryCurrencyBody = {
  country_code?: unknown;
  currency_code?: unknown;
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
     * Parse request body.
     */
    let body: UpsertCountryCurrencyBody;

    try {
      body = await req.json();
    } catch {
      throw new AppError(
        "INVALID_REQUEST_BODY",
        400,
      );
    }

    const countryCode =
      parseRequiredString(
        body.country_code,
        "COUNTRY_CODE_REQUIRED",
      ).toLowerCase();

    const currencyCode =
      parseRequiredString(
        body.currency_code,
        "CURRENCY_CODE_REQUIRED",
      ).toLowerCase();

    const isActive =
      parseBoolean(
        body.is_active,
        "IS_ACTIVE_REQUIRED",
      );

    /*
     * ISO-style country code.
     */
    if (
      !/^[a-z]{2}$/.test(countryCode)
    ) {
      throw new AppError(
        "INVALID_COUNTRY_CODE",
        400,
      );
    }

    /*
     * Currency codes currently use ISO-style
     * 3-character values:
     *
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

    /*
     * PostgreSQL performs authorization and upsert.
     */
    const {
      data,
      error,
    } = await supabase.rpc(
      "upsert_country_currency",
      {
        p_country_code: countryCode,
        p_currency_code: currencyCode,
        p_is_active: isActive,
      },
    );

    if (error) {
      console.error(
        "upsert_country_currency failed:",
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
        error.message === "COUNTRY_NOT_FOUND"
      ) {
        throw new AppError(
          "COUNTRY_NOT_FOUND",
          400,
        );
      }

      if (
        error.message === "CURRENCY_NOT_FOUND"
      ) {
        throw new AppError(
          "CURRENCY_NOT_FOUND",
          400,
        );
      }

      throw new AppError(
        error.message ||
          "FAILED_TO_UPDATE_COUNTRY_CURRENCIES",
        400,
      );
    }

    return successResponse(data);
  } catch (error) {
    console.error(
      "Upsert country currency error:",
      error,
    );

    return errorResponse(error);
  }
});