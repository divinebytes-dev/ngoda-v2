import {
  createSupabaseServiceClient,
} from "./supabase-client.ts";

import {
  AppError,
} from "./app-error.ts";

export async function fetchCountryCallingCode(
  countryCode: string,
): Promise<string> {
  const supabase =
    createSupabaseServiceClient();

  const {
    data,
    error,
  } = await supabase.rpc(
    "fetch_country_calling_code",
    {
      p_country_code:
        countryCode.toLowerCase(),
    },
  );

  if (error) {
    console.error(
      "FETCH_COUNTRY_CALLING_CODE_FAILED",
      {
        countryCode,

        code:
          error.code,

        message:
          error.message,

        details:
          error.details,

        hint:
          error.hint,
      },
    );

    throw new AppError(
      error.message ||
        "COUNTRY_CALLING_CODE_FETCH_FAILED",
    );
  }

  if (
    typeof data !== "string" ||
    !data.trim()
  ) {
    throw new AppError(
      "COUNTRY_CALLING_CODE_NOT_CONFIGURED",
    );
  }

  return data.trim().replace(
    /^\+/,
    "",
  );
}