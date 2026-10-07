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
  const rawAmount = responseData.data?.amount;

  if (rawAmount == null) {
    throw new Error(
      `INVALID_PRICE_RESPONSE_${currencyCode}`,
    );
  }

  /*
   * Preserve the original decimal representation.
   * PostgreSQL numeric accepts decimal values as strings.
   */
  const price = String(rawAmount);
  const numericPrice = Number(price);

  if (
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
    currency.currency_code.toLowerCase();

  /*
   * USD is the base currency.
   * Its rate to USD is always 1, so it must not
   * be fetched from an external rate API.
   */
  if (currencyCode === BASE_CURRENCY) {
    console.log(
      `Skipping ${currencyCode}: base currency`,
    );

    return {
      currency: currencyCode,
      status: "skipped",
    };
  }

  if (!currency.rate_api) {
    console.log(
      `Skipping ${currencyCode}: rate_api is missing`,
    );

    return {
      currency: currencyCode,
      status: "skipped",
    };
  }

  const response = await fetch(
    currency.rate_api,
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

  const {
    data: updatedRate,
    error: updateError,
  } = await supabase
    .from("current_rates")
    .update({
      /*
       * PostgreSQL numeric values can be sent as strings.
       * The cast is required when generated Supabase types
       * represent the column as a number.
       */
      rate_to_usd:
        price as unknown as number,
      updated_at:
        new Date().toISOString(),
    })
    .eq("code", currencyCode)
    .select("code")
    .maybeSingle();

  if (updateError) {
    throw new Error(
      `PRICE_UPDATE_FAILED_${currencyCode}_${updateError.message}`,
    );
  }

  if (!updatedRate) {
    throw new Error(
      `CURRENT_RATE_NOT_FOUND_${currencyCode}`,
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

  const {
    data: fiatCurrencyData,
    error: currencyError,
  } = await supabase
    .from("supported_currency")
    .select("currency_code, rate_api")
    .eq("is_active", true)
    .eq("currency_category", "fiat")
    /*
     * USD is the base currency and is not fetched.
     */
    .neq("currency_code", BASE_CURRENCY);

  if (currencyError) {
    throw new Error(
      `FIAT_CURRENCIES_FETCH_FAILED_${currencyError.message}`,
    );
  }

  /*
   * Cast the query result before map so the callback
   * parameter is inferred as FiatCurrency instead of any.
   */
  const currencyRows =
    (fiatCurrencyData ?? []) as FiatCurrency[];

  const currencies: FiatCurrency[] =
    currencyRows.map(
      (
        currency: FiatCurrency,
      ): FiatCurrency => ({
        currency_code:
          currency.currency_code.toLowerCase(),
        rate_api: currency.rate_api,
      }),
    );

  console.log(
    `Found ${currencies.length} fiat currencies to update`,
  );

  const updateTasks:
    Promise<FiatCurrencyUpdate>[] =
      currencies.map(
        (
          currency: FiatCurrency,
        ): Promise<FiatCurrencyUpdate> =>
          updateCurrencyRate(
            supabase,
            currency,
          ),
      );

  const settledResults:
    PromiseSettledResult<FiatCurrencyUpdate>[] =
      await Promise.allSettled(
        updateTasks,
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
    const settledItem =
      settledResults[index];

    const currency =
      currencies[index];

    if (!currency) {
      console.error(
        `Missing currency for result index ${index}`,
      );

      continue;
    }

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
        currency:
          currency.currency_code,
        error: errorMessage,
      });

      continue;
    }

    if (
      settledItem.value.status ===
        "updated"
    ) {
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
      Deno.env.get(
        "FIAT_PRICE_CRON_SECRET",
      );

    if (!configuredSecret) {
      console.error(
        "FIAT_PRICE_CRON_SECRET_NOT_CONFIGURED",
      );

      return jsonResponse(
        {
          success: false,
          message:
            "CRON_CONFIGURATION_MISSING",
        },
        500,
      );
    }

    const suppliedSecret =
      request.headers.get(
        "x-cron-secret",
      );

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

      const result =
        await fetchFiatPrices();

      if (result.failed.length > 0) {
        console.error(
          "FIAT_PRICE_PARTIAL_FAILURE",
          result.failed,
        );

        return jsonResponse(
          {
            success: false,
            message:
              "FIAT_PRICE_UPDATE_PARTIAL_FAILURE",
            result,
            processed_at:
              new Date().toISOString(),
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
          processed_at:
            new Date().toISOString(),
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
          message:
            "PRICE_UPDATE_FAIL",
          error: errorMessage,
        },
        500,
      );
    }
  },
);