import {
  AppError,
} from "../app-error.ts";

import {
  createSupabaseServiceClient,
} from "../supabase-client.ts";


type GoldRateApiRow = {
  rate_api: string | null;
};


type GoldPriceResponse = {
  price?: string | number;
};


function isPositiveDecimal(
  value: unknown,
): boolean {
  if (
    typeof value !== "string" &&
    typeof value !== "number"
  ) {
    return false;
  }

  const normalizedValue =
    value
      .toString()
      .trim();

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


function isGoldRateApiRow(
  value: unknown,
): value is GoldRateApiRow {
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
    row.rate_api === null ||
    typeof row.rate_api === "string"
  );
}


export async function fetchGoldPricePerGram(
  supabase: ReturnType<
    typeof createSupabaseServiceClient
  >,
): Promise<string> {
  /*
   * Fetch the configured Gold API from
   * supported_currency.rate_api.
   */
  const {
    data: configurationRows,
    error: configurationError,
  } = await supabase.rpc(
    "fetch_gold_rate_api",
  );

  if (configurationError) {
    console.error(
      "FETCH_GOLD_RATE_API_RPC_FAILED",
      {
        code:
          configurationError.code,

        message:
          configurationError.message,

        details:
          configurationError.details,

        hint:
          configurationError.hint,
      },
    );

    throw new AppError(
      configurationError.message ||
        "FAILED_TO_FETCH_GOLD_RATE_API",
    );
  }

  if (
    !Array.isArray(
      configurationRows,
    ) ||
    configurationRows.length === 0 ||
    !configurationRows.every(
      isGoldRateApiRow,
    )
  ) {
    throw new AppError(
      "INVALID_GOLD_RATE_API_RESPONSE",
    );
  }

  const rateApi =
    configurationRows[0]
      .rate_api
      ?.trim();

  if (!rateApi) {
    throw new AppError(
      "GOLD_RATE_API_NOT_CONFIGURED",
    );
  }

  let rateUrl: URL;

  try {
    rateUrl =
      new URL(
        rateApi,
      );
  } catch {
    throw new AppError(
      "INVALID_GOLD_RATE_API_URL",
    );
  }

  if (
    rateUrl.protocol !== "https:"
  ) {
    throw new AppError(
      "INVALID_GOLD_RATE_API_PROTOCOL",
    );
  }

  let response: Response;

  try {
    response =
      await fetch(
        rateUrl.toString(),
        {
          method:
            "GET",

          headers: {
            "Accept":
              "application/json",
          },

          signal:
            AbortSignal.timeout(
              15_000,
            ),
        },
      );
  } catch (error) {
    console.error(
      "GOLD_PRICE_API_REQUEST_FAILED",
      {
        url:
          rateUrl.toString(),

        error:
          error instanceof Error
            ? error.message
            : String(error),
      },
    );

    throw new AppError(
      "FAILED_TO_FETCH_GOLD_PRICE",
    );
  }

  if (!response.ok) {
    console.error(
      "GOLD_PRICE_API_FAILED",
      {
        status:
          response.status,

        statusText:
          response.statusText,
      },
    );

    throw new AppError(
      "FAILED_TO_FETCH_GOLD_PRICE",
    );
  }

  let responseData:
    GoldPriceResponse;

  try {
    responseData =
      await response.json() as
        GoldPriceResponse;
  } catch {
    throw new AppError(
      "INVALID_GOLD_PRICE_RESPONSE",
    );
  }

const pricePerOunce =
  responseData.price
    ?.toString()
    .trim() ??
  "";

if (
  !isPositiveDecimal(
    pricePerOunce,
  )
) {
  throw new AppError(
    "INVALID_GOLD_PRICE_RESPONSE",
  );
}

  /*
   * PostgreSQL converts ounces to grams and updates:
   *
   * current_rates.rate_to_usd
   * current_rates.updated_at
   */
  const {
    data: pricePerGram,
    error: updateError,
  } = await supabase.rpc(
    "update_gold_rate_from_ounce_price",
    {
      /*
       * Keep only the numeric SQL overload:
       *
       * update_gold_rate_from_ounce_price(numeric)
       */
      p_price_per_ounce:
        Number(
          pricePerOunce,
        ),
    },
  );

  if (updateError) {
    console.error(
      "UPDATE_GOLD_RATE_RPC_FAILED",
      {
        code:
          updateError.code,

        message:
          updateError.message,

        details:
          updateError.details,

        hint:
          updateError.hint,

        pricePerOunce,
      },
    );

    throw new AppError(
      updateError.message ||
        "FAILED_TO_UPDATE_GOLD_RATE",
    );
  }

  if (
    !isPositiveDecimal(
      pricePerGram,
    )
  ) {
    throw new AppError(
      "INVALID_GOLD_PRICE_PER_GRAM",
    );
  }

  return pricePerGram
    .toString()
    .trim();
}