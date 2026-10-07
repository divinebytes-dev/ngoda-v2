import {
  AppError,
} from "../app-error.ts";

import {
  createSupabaseServiceClient,
} from "../supabase-client.ts";

import type {
  LiquidationDetectionResult,
} from "../types/liquidation-detection-result.ts";


function isNonNegativeInteger(
  value: unknown,
): value is number {
  return (
    Number.isSafeInteger(value) &&
    Number(value) >= 0
  );
}


function isPositiveDecimalString(
  value: unknown,
): value is string {
  if (
    typeof value !== "string"
  ) {
    return false;
  }

  const normalizedValue =
    value.trim();

  const numericValue =
    Number(normalizedValue);

  return (
    /^\d+(\.\d+)?$/.test(
      normalizedValue,
    ) &&
    Number.isFinite(
      numericValue,
    ) &&
    numericValue > 0
  );
}


export async function detectUnhealthyPositions(
  input: {
    supabase: ReturnType<
      typeof createSupabaseServiceClient
    >;

    countryCode: string;
    goldPricePerGram: string;
  },
): Promise<LiquidationDetectionResult> {
  const countryCode =
    input.countryCode
      .trim()
      .toLowerCase();

  if (!countryCode) {
    throw new AppError(
      "COUNTRY_CODE_REQUIRED",
    );
  }

  const goldPricePerGram =
    input.goldPricePerGram
      .trim();

  if (
    !isPositiveDecimalString(
      goldPricePerGram,
    )
  ) {
    throw new AppError(
      "INVALID_GOLD_PRICE_PER_GRAM",
    );
  }

  const {
    data,
    error,
  } = await input.supabase.rpc(
    "detect_unhealthy_loan_positions",
    {
      p_country_code:
        countryCode,

      p_gold_price_per_gram:
        goldPricePerGram,
    },
  );

  if (error) {
    console.error(
      "DETECT_UNHEALTHY_LOAN_POSITIONS_RPC_FAILED",
      {
        code:
          error.code,

        message:
          error.message,

        details:
          error.details,

        hint:
          error.hint,

        countryCode,

        goldPricePerGram,
      },
    );

    throw new AppError(
      error.message ||
        "FAILED_TO_DETECT_UNHEALTHY_LOAN_POSITIONS",
    );
  }

  if (
    typeof data !== "object" ||
    data === null ||
    Array.isArray(data)
  ) {
    throw new AppError(
      "INVALID_LIQUIDATION_DETECTION_RESPONSE",
    );
  }

  const result =
    data as
      Partial<LiquidationDetectionResult>;

  if (
    result.success !== true ||
    typeof result.country_code !== "string" ||
    result.country_code
      .trim()
      .toLowerCase() !== countryCode ||
    !Number.isSafeInteger(
      result.fiscal_year,
    ) ||
    Number(result.fiscal_year) < 1 ||
    !Number.isSafeInteger(
      result.period,
    ) ||
    Number(result.period) < 1 ||
    !isPositiveDecimalString(
      result.gold_price,
    ) ||
    !isNonNegativeInteger(
      result.evaluated,
    ) ||
    !isNonNegativeInteger(
      result.detected,
    ) ||
    !isNonNegativeInteger(
      result.already_underway,
    ) ||
    !isNonNegativeInteger(
      result.skipped,
    )
  ) {
    throw new AppError(
      "INVALID_LIQUIDATION_DETECTION_RESPONSE",
    );
  }

  return {
    success:
      true,

    country_code:
      countryCode,

    fiscal_year: Number(result.fiscal_year),

    period: Number(result.period),

    gold_price:
      result.gold_price,

    evaluated:
      result.evaluated,

    detected:
      result.detected,

    already_underway:
      result.already_underway,

    skipped:
      result.skipped,
  };
}