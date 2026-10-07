import {
  AppError,
} from "../app-error.ts";

import {
  createSupabaseServiceClient,
} from "../supabase-client.ts";


type OperationalCountryRow = {
  country_code: string;
};


function isOperationalCountryRow(
  value: unknown,
): value is OperationalCountryRow {
  if (
    typeof value !== "object" ||
    value === null ||
    Array.isArray(value)
  ) {
    return false;
  }

  const row =
    value as
      Record<string, unknown>;

  return (
    typeof row.country_code === "string" &&
    row.country_code.trim() !== ""
  );
}


export async function fetchActiveOperationalCountries(
  supabase: ReturnType<
    typeof createSupabaseServiceClient
  >,
): Promise<string[]> {
  const {
    data,
    error,
  } = await supabase.rpc(
    "fetch_active_operational_countries",
  );

  if (error) {
    console.error(
      "FETCH_ACTIVE_OPERATIONAL_COUNTRIES_RPC_FAILED",
      {
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
        "FAILED_TO_FETCH_ACTIVE_OPERATIONAL_COUNTRIES",
    );
  }

  if (
    !Array.isArray(data)
  ) {
    throw new AppError(
      "INVALID_ACTIVE_OPERATIONAL_COUNTRIES_RESPONSE",
    );
  }

  if (
    !data.every(
      isOperationalCountryRow,
    )
  ) {
    throw new AppError(
      "INVALID_ACTIVE_OPERATIONAL_COUNTRY_ROW",
    );
  }

  const countries =
    new Set<string>();

  for (const row of data) {
    countries.add(
      row.country_code
        .trim()
        .toLowerCase(),
    );
  }

  if (
    countries.size === 0
  ) {
    throw new AppError(
      "ACTIVE_OPERATIONAL_COUNTRIES_NOT_FOUND",
    );
  }

  return [
    ...countries,
  ].sort();
}