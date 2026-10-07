import {
  createSupabaseServiceClient,
} from "../../_shared/supabase-client.ts";

import {
  claimLiquidationAccountingJobs,
} from "../../_shared/process-loan-liquidations/claim-liquidation-accounting-jobs.ts";

import {
  claimLiquidationBlockchainJobs,
} from "../../_shared/process-loan-liquidations/claim-liquidation-blockchain-jobs.ts";

import {
  detectUnhealthyPositions,
} from "../../_shared/process-loan-liquidations/detect-unhealthy-positions.ts";

import {
  fetchActiveOperationalCountries,
} from "../../_shared/process-loan-liquidations/fetch-active-operational-countries.ts";

import {
  fetchGoldPricePerGram,
} from "../../_shared/process-loan-liquidations/fetch-gold-price-per-gram.ts";

import {
  prepareLiquidationBlockchainJobs,
} from "../../_shared/process-loan-liquidations/prepare-liquidation-blockchain-jobs.ts";

import {
  processLiquidationAccountingJobs,
} from "../../_shared/process-loan-liquidations/process-liquidation-accounting-jobs.ts";

import {
  processLiquidationBlockchainJob,
} from "../../_shared/process-loan-liquidations/blockchain-transfer.ts";


const DEFAULT_BATCH_SIZE = 10;
const MAXIMUM_BATCH_SIZE = 50;

/*
 * Blockchain transfers are processed sequentially. Claiming
 * one job at a time also limits how long another claimed job
 * can remain waiting while its processing lease is running.
 */
const BLOCKCHAIN_BATCH_SIZE = 1;


type StageError = {
  stage: string;
  error: string;
};


type CountryLiquidationResult = {
  country_code: string;

  detection:
    unknown | null;

  queue_preparation:
    unknown | null;

  blockchain: {
    claimed: number;
    succeeded: number;
    failed: number;
    results: unknown[];
  };

  accounting: {
    claimed: number;
    processed: number;
    succeeded: number;
    failed: number;
    results: unknown[];
  };

  errors: StageError[];
};


function getErrorMessage(
  error: unknown,
): string {
  if (error instanceof Error) {
    return (
      error.message.trim() ||
      "UNKNOWN_LIQUIDATION_ERROR"
    );
  }

  if (
    typeof error === "object" &&
    error !== null &&
    "message" in error &&
    typeof error.message === "string"
  ) {
    return (
      error.message.trim() ||
      "UNKNOWN_LIQUIDATION_ERROR"
    );
  }

  return (
    String(error).trim() ||
    "UNKNOWN_LIQUIDATION_ERROR"
  );
}


function jsonResponse(
  body: unknown,
  status = 200,
): Response {
  return new Response(
    JSON.stringify(body),
    {
      status,

      headers: {
        "Content-Type":
          "application/json",
      },
    },
  );
}


function fetchBatchSize(): number {
  const configuredValue =
    Deno.env
      .get("LIQUIDATION_BATCH_SIZE")
      ?.trim();

  if (!configuredValue) {
    return DEFAULT_BATCH_SIZE;
  }

  if (
    !/^\d+$/.test(
      configuredValue,
    )
  ) {
    throw new Error(
      "INVALID_LIQUIDATION_BATCH_SIZE_CONFIGURATION",
    );
  }

  const batchSize =
    Number(configuredValue);

  if (
    !Number.isSafeInteger(batchSize) ||
    batchSize < 1 ||
    batchSize > MAXIMUM_BATCH_SIZE
  ) {
    throw new Error(
      "INVALID_LIQUIDATION_BATCH_SIZE_CONFIGURATION",
    );
  }

  return batchSize;
}


function addStageError(
  result: CountryLiquidationResult,
  stage: string,
  error: unknown,
): void {
  const message =
    getErrorMessage(
      error,
    );

  result.errors.push({
    stage,
    error:
      message,
  });

  console.error(
    "COUNTRY_LIQUIDATION_STAGE_FAILED",
    {
      countryCode:
        result.country_code,

      stage,

      error:
        message,
    },
  );
}


function countryHasFailure(
  country: CountryLiquidationResult,
): boolean {
  return (
    country.errors.length > 0 ||
    country.blockchain.failed > 0 ||
    country.accounting.failed > 0
  );
}


async function processCountryLiquidations(
  input: {
    supabase: ReturnType<
      typeof createSupabaseServiceClient
    >;

    countryCode: string;
    goldPricePerGram: string | null;
    goldPriceError: string | null;
    batchSize: number;
  },
): Promise<CountryLiquidationResult> {
  const result: CountryLiquidationResult = {
    country_code:
      input.countryCode,

    detection:
      null,

    queue_preparation:
      null,

    blockchain: {
      claimed:
        0,

      succeeded:
        0,

      failed:
        0,

      results:
        [],
    },

    accounting: {
      claimed:
        0,

      processed:
        0,

      succeeded:
        0,

      failed:
        0,

      results:
        [],
    },

    errors:
      [],
  };

  /*
   * A failed Gold-price refresh blocks only the detection
   * of new unhealthy positions.
   *
   * Existing queue and accounting jobs must continue.
   */
  if (input.goldPricePerGram) {
    try {
      result.detection =
        await detectUnhealthyPositions({
          supabase:
            input.supabase,

          countryCode:
            input.countryCode,

          goldPricePerGram:
            input.goldPricePerGram,
        });
    } catch (error) {
      addStageError(
        result,
        "detection",
        error,
      );
    }
  } else {
    addStageError(
      result,
      "gold_price",
      input.goldPriceError ||
        "GOLD_PRICE_NOT_AVAILABLE",
    );
  }

  /*
   * Convert newly detected pending jobs into immutable
   * blockchain queue instructions.
   *
   * The SQL function must return immediately without
   * fetching treasury or document configuration when no
   * pending liquidation job exists.
   */
  try {
    result.queue_preparation =
      await prepareLiquidationBlockchainJobs({
        supabase:
          input.supabase,

        countryCode:
          input.countryCode,

        batchSize:
          input.batchSize,
      });
  } catch (error) {
    addStageError(
      result,
      "queue_preparation",
      error,
    );
  }

  /*
   * Claim only one blockchain job at a time.
   *
   * Every job is isolated so an unexpected failure on one
   * transfer does not prevent another country stage from
   * continuing.
   */
  try {
    const blockchainJobs =
      await claimLiquidationBlockchainJobs({
        supabase:
          input.supabase,

        countryCode:
          input.countryCode,

        batchSize:
          BLOCKCHAIN_BATCH_SIZE,
      });

    result.blockchain.claimed =
      blockchainJobs.claimed;

    for (
      const job of
      blockchainJobs.jobs
    ) {
      try {
        const jobResult =
          await processLiquidationBlockchainJob({
            supabase:
              input.supabase,

            job,
          });

        result.blockchain.results.push(
          jobResult,
        );

        if (jobResult.success) {
          result.blockchain.succeeded +=
            1;
        } else {
          result.blockchain.failed +=
            1;
        }
      } catch (error) {
        /*
         * processLiquidationBlockchainJob normally returns a
         * failed result after recording the queue failure.
         *
         * Reaching this catch means the failure state itself
         * may not have been recorded. Surface it explicitly.
         */
        result.blockchain.failed +=
          1;

        const message =
          getErrorMessage(
            error,
          );

        result.blockchain.results.push({
          queue_id:
            job.queue_id,

          liquidation_job_id:
            job.liquidation_job_id,

          success:
            false,

          database_confirmed:
            false,

          tx_hash:
            job.tx_hash,

          error:
            message,
        });

        addStageError(
          result,
          `blockchain_job_${job.queue_id}`,
          error,
        );
      }
    }
  } catch (error) {
    addStageError(
      result,
      "blockchain_claim",
      error,
    );
  }

  /*
   * Accounting jobs are only claimable after their
   * blockchain queue has status confirmed and a tx_hash.
   */
  try {
    const accountingJobs =
      await claimLiquidationAccountingJobs({
        supabase:
          input.supabase,

        countryCode:
          input.countryCode,

        batchSize:
          input.batchSize,
      });

    result.accounting.claimed =
      accountingJobs.claimed;

    const accountingResult =
      await processLiquidationAccountingJobs({
        supabase:
          input.supabase,

        jobs:
          accountingJobs.jobs,
      });

    result.accounting.processed =
      accountingResult.processed;

    result.accounting.succeeded =
      accountingResult.succeeded;

    result.accounting.failed =
      accountingResult.failed;

    result.accounting.results =
      accountingResult.results;
  } catch (error) {
    addStageError(
      result,
      "accounting",
      error,
    );
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
          success:
            false,

          message:
            "METHOD_NOT_ALLOWED",
        },
        405,
      );
    }

    const configuredSecret =
      Deno.env
        .get(
          "LIQUIDATION_CRON_SECRET",
        )
        ?.trim();

    if (!configuredSecret) {
      console.error(
        "LIQUIDATION_CRON_SECRET_NOT_CONFIGURED",
      );

      return jsonResponse(
        {
          success:
            false,

          message:
            "CRON_CONFIGURATION_MISSING",
        },
        500,
      );
    }

    const suppliedSecret =
      request.headers
        .get(
          "x-cron-secret",
        )
        ?.trim();

    if (
      !suppliedSecret ||
      suppliedSecret !==
        configuredSecret
    ) {
      console.warn(
        "UNAUTHORIZED_LIQUIDATION_CRON_REQUEST",
      );

      return jsonResponse(
        {
          success:
            false,

          message:
            "UNAUTHORIZED",
        },
        401,
      );
    }

    try {
      console.log(
        "Starting scheduled loan liquidation",
      );

      const batchSize =
        fetchBatchSize();

      const serviceSupabase =
        createSupabaseServiceClient();

      /*
       * Countries must still be available when the external
       * Gold-price API fails because existing blockchain and
       * accounting work must continue.
       */
      const countryCodes =
        await fetchActiveOperationalCountries(
          serviceSupabase,
        );

      let goldPricePerGram:
        string | null =
          null;

      let goldPriceError:
        string | null =
          null;

      try {
        goldPricePerGram =
          await fetchGoldPricePerGram(
            serviceSupabase,
          );
      } catch (error) {
        goldPriceError =
          getErrorMessage(
            error,
          );

        console.error(
          "GOLD_PRICE_REFRESH_FAILED",
          {
            error:
              goldPriceError,
          },
        );
      }

      const countryResults:
        CountryLiquidationResult[] =
          [];

      /*
       * Process countries sequentially because all physical
       * Gold transfers use the same global blockchain
       * treasury and relayer infrastructure.
       */
      for (
        const countryCode of
        countryCodes
      ) {
        const countryResult =
          await processCountryLiquidations({
            supabase:
              serviceSupabase,

            countryCode,

            goldPricePerGram,

            goldPriceError,

            batchSize,
          });

        countryResults.push(
          countryResult,
        );
      }

      const failedCountries =
        countryResults.filter(
          countryHasFailure,
        ).length;

      const blockchainSucceeded =
        countryResults.reduce(
          (
            total,
            country,
          ) =>
            total +
            country.blockchain.succeeded,
          0,
        );

      const blockchainFailed =
        countryResults.reduce(
          (
            total,
            country,
          ) =>
            total +
            country.blockchain.failed,
          0,
        );

      const accountingSucceeded =
        countryResults.reduce(
          (
            total,
            country,
          ) =>
            total +
            country.accounting.succeeded,
          0,
        );

      const accountingFailed =
        countryResults.reduce(
          (
            total,
            country,
          ) =>
            total +
            country.accounting.failed,
          0,
        );

      const allCountriesSuccessful =
        failedCountries === 0 &&
        blockchainFailed === 0 &&
        accountingFailed === 0;

      const result = {
        completed:
          true,

        all_countries_successful:
          allCountriesSuccessful,

        gold_price_per_gram:
          goldPricePerGram,

        gold_price_error:
          goldPriceError,

        batch_size:
          batchSize,

        blockchain_batch_size:
          BLOCKCHAIN_BATCH_SIZE,

        total_countries:
          countryCodes.length,

        failed_countries:
          failedCountries,

        blockchain: {
          succeeded:
            blockchainSucceeded,

          failed:
            blockchainFailed,
        },

        accounting: {
          succeeded:
            accountingSucceeded,

          failed:
            accountingFailed,
        },

        countries:
          countryResults,
      };

      if (!allCountriesSuccessful) {
        console.error(
          "LIQUIDATION_PARTIAL_FAILURE",
          result,
        );

        return jsonResponse(
          {
            success:
              false,

            message:
              "LIQUIDATION_PARTIAL_FAILURE",

            result,

            processed_at:
              new Date().toISOString(),
          },
          500,
        );
      }

      console.log(
        "Loan liquidation completed",
        result,
      );

      return jsonResponse(
        {
          success:
            true,

          result,

          processed_at:
            new Date().toISOString(),
        },
        200,
      );
    } catch (error: unknown) {
      const message =
        getErrorMessage(
          error,
        );

      console.error(
        "LOAN_LIQUIDATION_CRON_FAILED",
        {
          error:
            message,
        },
      );

      return jsonResponse(
        {
          success:
            false,

          message:
            "LOAN_LIQUIDATION_CRON_FAILED",

          error:
            message,

          processed_at:
            new Date().toISOString(),
        },
        500,
      );
    }
  },
);