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


type UpsertOperationalCountryBody = {
  country_code?: unknown;
  name?: unknown;
  calling_code?: unknown;
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

    /*
     * User-scoped Supabase client.
     *
     * The authenticated user's JWT is passed through,
     * therefore auth.uid() inside PostgreSQL resolves
     * to the current administrator.
     */
    const supabase =
      createSupabaseClient(req);

    /*
     * Authentication
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
     * Parse request.
     */
    let body: UpsertOperationalCountryBody;

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

    const name =
      parseRequiredString(
        body.name,
        "COUNTRY_NAME_REQUIRED",
      );

    const callingCode =
      parseRequiredString(
        body.calling_code,
        "CALLING_CODE_REQUIRED",
      );

    const isActive =
      parseBoolean(
        body.is_active,
        "IS_ACTIVE_REQUIRED",
      );

    /*
     * Basic country-code validation.
     *
     * operational_country currently uses ISO-style
     * two-character country codes such as:
     *
     * bw
     * za
     * zw
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
     * Calling code is stored without "+".
     *
     * Example:
     * Botswana -> 267
     */
    if (
      !/^[0-9]{1,4}$/.test(callingCode)
    ) {
      throw new AppError(
        "INVALID_CALLING_CODE",
        400,
      );
    }

    /*
     * PostgreSQL performs the final authorization
     * and upsert.
     */
    const {
      data,
      error,
    } = await supabase.rpc(
      "upsert_operational_country",
      {
        p_country_code: countryCode,
        p_name: name,
        p_calling_code: callingCode,
        p_is_active: isActive,
      },
    );

    if (error) {
      console.error(
        "upsert_operational_country failed:",
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

      throw new AppError(
        error.message ||
          "COUNTRY_UPSERT_FAILED",
        400,
      );
    }

    return successResponse(data);
  } catch (error) {
    console.error(
      "Upsert operational country error:",
      error,
    );

    return errorResponse(error);
  }
});