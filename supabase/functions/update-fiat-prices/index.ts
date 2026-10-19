import {
  createSupabaseServiceClient,
} from "../../_shared/supabase-client.ts";

type ServiceClient = ReturnType<
  typeof createSupabaseServiceClient
>;

type FiatCurrency = {
  currency_code: string;
  rate_api: string | null;
};

type FiatPriceApiResponse = {
  data?: {
    amount?: string | number;
  };
};

type FiatCurrencyUpdate = {
  currency: string;
  status: "updated" | "skipped";
  price?: string;
};

type FiatPriceFailure = {
  currency: string;
  error: string;
};

type FiatPriceResult = {
  updated: string[];
  skipped: string[];
  failed: FiatPriceFailure[];
};

const BASE_CURRENCY = "usd";
const REQUEST_TIMEOUT_MS = 15_000;

function jsonResponse(
  body: unknown,
  status = 200,
): Response {
  return new Response(
    JSON.stringify(body),
    {
      status,
      headers: {
        "Content-Type": "application/json",
      },
    },
  );
}

function extractPrice(
  responseData: FiatPriceApiResponse,
  currencyCode: string,
): string {
  const rawAmount = responseData?.data?.amount;

  if (
    typeof rawAmount !== "string" &&
    typeof rawAmount !== "number"
  ) {
    throw new Error(
      `INVALID_PRICE_RESPONSE_${currencyCode}`,
    );
  }

  /*
   * Preserve the API's decimal representation.
   * PostgreSQL numeric accepts the value as a string.
   */
  const price = String(rawAmount).trim();
  const numericPrice = Number(price);

  if (
    !price ||
    !Number.isFinite(numericPrice) ||
    numericPrice <= 0
  ) {
    throw new Error(
      `INVALID_PRICE_RESPONSE_${currencyCode}`,
    );
  }

  return price;
}

async function updateCurrencyRate(
  supabase: ServiceClient,
  currency: FiatCurrency,
): Promise<FiatCurrencyUpdate> {
  const currencyCode =
    currency.currency_code.trim().toLowerCase();

  /*
   * The SQL fetch function manages USD at 1.
   * This guard prevents an external USD API request.
   */
  if (currencyCode === BASE_CURRENCY) {
    return {
      currency: currencyCode,
      status: "skipped",
    };
  }

  const rateApi = currency.rate_api?.trim();

  if (!rateApi) {
    console.log(
      `Skipping ${currencyCode}: rate_api is missing`,
    );

    return {
      currency: currencyCode,
      status: "skipped",
    };
  }

  const response = await fetch(
    rateApi,
    {
      method: "GET",
      headers: {
        Accept: "application/json",
      },
      signal: AbortSignal.timeout(
        REQUEST_TIMEOUT_MS,
      ),
    },
  );

  if (!response.ok) {
    throw new Error(
      `PRICE_API_HTTP_${response.status}_${currencyCode}`,
    );
  }

  const responseData =
    await response.json() as FiatPriceApiResponse;

  const price = extractPrice(
    responseData,
    currencyCode,
  );

  /*
   * The SQL function:
   * - Requires service_role.
   * - Rechecks that the currency is active fiat.
   * - Validates the rate.
   * - Inserts missing rows or updates existing rows.
   */
  const {
    error: updateError,
  } = await supabase.rpc(
    "upsert_fiat_currency_rate",
    {
      p_currency_code: currencyCode,

      /*
       * This TypeScript cast does not convert the value.
       * The decimal string is sent to PostgreSQL numeric.
       */
      p_rate_to_usd:
        price as unknown as number,
    },
  );

  if (updateError) {
    throw new Error(
      `PRICE_UPDATE_FAILED_${currencyCode}_${updateError.message}`,
    );
  }

  console.log(
    `Updated ${currencyCode}: ${price}`,
  );

  return {
    currency: currencyCode,
    status: "updated",
    price,
  };
}

async function fetchFiatPrices():
  Promise<FiatPriceResult> {
  const supabase =
    createSupabaseServiceClient();

  /*
   * Returns active fiat currencies excluding USD.
   * Also initializes/maintains active USD at rate 1.
   */
  const {
    data: fiatCurrencyData,
    error: currencyError,
  } = await supabase.rpc(
    "fetch_fiat_price_update_currencies",
  );

  if (currencyError) {
    throw new Error(
      `FIAT_CURRENCIES_FETCH_FAILED_${currencyError.message}`,
    );
  }

  const currencyRows =
    (fiatCurrencyData ?? []) as FiatCurrency[];

  const currencies: FiatCurrency[] =
    currencyRows.map(
      (currency: FiatCurrency): FiatCurrency => ({
        currency_code:
          currency.currency_code.trim().toLowerCase(),
        rate_api: currency.rate_api,
      }),
    );

  console.log(
    `Found ${currencies.length} fiat currencies to update`,
  );

  const settledResults =
    await Promise.allSettled(
      currencies.map(
        (currency) =>
          updateCurrencyRate(
            supabase,
            currency,
          ),
      ),
    );

  const result: FiatPriceResult = {
    updated: [],
    skipped: [],
    failed: [],
  };

  for (
    let index = 0;
    index < settledResults.length;
    index++
  ) {
    const currency = currencies[index]!;
    const settledItem = settledResults[index]!;

    if (settledItem.status === "rejected") {
      const errorMessage =
        settledItem.reason instanceof Error
          ? settledItem.reason.message
          : String(settledItem.reason);

      console.error(
        `Failed to update ${currency.currency_code}:`,
        errorMessage,
      );

      result.failed.push({
        currency: currency.currency_code,
        error: errorMessage,
      });

      continue;
    }

    if (settledItem.value.status === "updated") {
      result.updated.push(
        settledItem.value.currency,
      );
    } else {
      result.skipped.push(
        settledItem.value.currency,
      );
    }
  }

  return result;
}

Deno.serve(
  async (
    request: Request,
  ): Promise<Response> => {
    if (request.method !== "POST") {
      return jsonResponse(
        {
          success: false,
          message: "METHOD_NOT_ALLOWED",
        },
        405,
      );
    }

    const configuredSecret =
      Deno.env.get("FIAT_PRICE_CRON_SECRET");

    if (!configuredSecret) {
      console.error(
        "FIAT_PRICE_CRON_SECRET_NOT_CONFIGURED",
      );

      return jsonResponse(
        {
          success: false,
          message: "CRON_CONFIGURATION_MISSING",
        },
        500,
      );
    }

    const suppliedSecret =
      request.headers.get("x-cron-secret");

    if (
      !suppliedSecret ||
      suppliedSecret !== configuredSecret
    ) {
      console.warn(
        "UNAUTHORIZED_FIAT_PRICE_CRON_REQUEST",
      );

      return jsonResponse(
        {
          success: false,
          message: "UNAUTHORIZED",
        },
        401,
      );
    }

    try {
      console.log(
        "Starting scheduled fiat price update",
      );

      const result = await fetchFiatPrices();

      if (result.failed.length > 0) {
        console.error(
          "FIAT_PRICE_PARTIAL_FAILURE",
          result.failed,
        );

        return jsonResponse(
          {
            success: false,
            message: "FIAT_PRICE_UPDATE_PARTIAL_FAILURE",
            result,
            processed_at: new Date().toISOString(),
          },
          500,
        );
      }

      console.log(
        "Fiat price update completed",
        result,
      );

      return jsonResponse(
        {
          success: true,
          result,
          processed_at: new Date().toISOString(),
        },
        200,
      );
    } catch (error: unknown) {
      const errorMessage =
        error instanceof Error
          ? error.message
          : String(error);

      console.error(
        "FIAT_PRICE_UPDATE_FAILED",
        errorMessage,
      );

      return jsonResponse(
        {
          success: false,
          message: "PRICE_UPDATE_FAIL",
          error: errorMessage,
        },
        500,
      );
    }
  },
);