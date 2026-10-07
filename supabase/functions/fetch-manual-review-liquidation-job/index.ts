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


function parseJobId(
  value: string | null,
): string {
  if (
    value === null ||
    value.trim() === ""
  ) {
    throw new AppError(
      "LIQUIDATION_JOB_ID_REQUIRED",
      400,
    );
  }

  const jobId =
    value.trim();

  if (
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      .test(jobId)
  ) {
    throw new AppError(
      "INVALID_LIQUIDATION_JOB_ID",
      400,
    );
  }

  return jobId;
}


Deno.serve(async (request: Request) => {
  try {
    if (request.method !== "GET") {
      throw new AppError(
        "METHOD_NOT_ALLOWED",
        405,
      );
    }

    const url =
      new URL(request.url);

    const jobId =
      parseJobId(
        url.searchParams.get("jobId") ??
          url.searchParams.get("job_id") ??
          url.searchParams.get(
            "liquidationJobId",
          ),
      );

    /*
     * The authenticated database RPC performs the
     * Accounts/Finance role check and country restriction.
     */
    const supabase =
      createSupabaseClient(request);

    const {
      data,
      error,
    } = await supabase.rpc(
      "fetch_my_manual_review_liquidation_job",
      {
        p_job_id:
          jobId,
      },
    );

    if (error) {
      console.error(
        "FETCH_MANUAL_REVIEW_LIQUIDATION_JOB_RPC_FAILED",
        {
          code:
            error.code,

          message:
            error.message,

          details:
            error.details,

          hint:
            error.hint,

          jobId,
        },
      );

      throw new AppError(
        error.message ||
          "FETCH_MANUAL_REVIEW_LIQUIDATION_JOB_FAILED",
      );
    }

    if (
      data === null ||
      typeof data !== "object" ||
      Array.isArray(data)
    ) {
      throw new AppError(
        "MANUAL_REVIEW_LIQUIDATION_JOB_NOT_FOUND",
        404,
      );
    }

    return successResponse(data);
  } catch (error) {
    console.error(
      "FETCH_MANUAL_REVIEW_LIQUIDATION_JOB_ERROR",
      {
        error:
          error instanceof Error
            ? error.message
            : String(error),
      },
    );

    return errorResponse(
      error,
      "FETCH_MANUAL_REVIEW_LIQUIDATION_JOB_FAILED",
    );
  }
});
