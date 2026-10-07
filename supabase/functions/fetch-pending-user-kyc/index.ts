import {
  errorResponse,
  successResponse,
} from "../../_shared/api-response.ts";

import {
  AppError,
} from "../../_shared/app-error.ts";

import {
  authenticateRequest,
} from "../../_shared/supabase-client.ts";


type KycReviewQueueItem = {

  // ==========================================================
  // USER
  // ==========================================================

  user_id: string;

  first_name: string | null;
  middle_name: string | null;
  surname: string | null;

  email: string | null;
  phone: string | null;


  // ==========================================================
  // COUNTRY
  // ==========================================================

  country_code: string;
  country_name: string;


  // ==========================================================
  // ROLE
  // ==========================================================

  role_id: string;
  role: string;


  // ==========================================================
  // KYC
  //
  // NULL means the user has not started KYC.
  // ==========================================================

  kyc_id: string | null;
  kyc_status: string | null;

  kyc_started_at: string | null;
  kyc_updated_at: string | null;
};


type KycReviewQueueResult = {

  // ==========================================================
  // FILTER
  //
  // NULL means this response contains all countries.
  // ==========================================================

  country_code: string | null;


  // ==========================================================
  // PAGINATION
  // ==========================================================

  page: number;
  page_size: number;

  total_entries: number;
  total_pages: number;

  has_previous: boolean;
  has_next: boolean;


  // ==========================================================
  // DATA
  // ==========================================================

  data: KycReviewQueueItem[];
};


/*
 * ============================================================
 * POSITIVE INTEGER
 * ============================================================
 */
function parsePositiveInteger(
  value: string | null,
  defaultValue: number,
  errorMessage: string,
): number {

  if (
    value === null ||
    value.trim() === ""
  ) {
    return defaultValue;
  }


  const parsed =
    Number(
      value,
    );


  if (
    !Number.isInteger(
      parsed,
    ) ||
    parsed < 1
  ) {
    throw new AppError(
      errorMessage,
      400,
    );
  }


  return parsed;
}


/*
 * ============================================================
 * OPTIONAL COUNTRY CODE
 *
 * Flutter:
 *
 * countryCode omitted/null
 *     -> all countries
 *
 * countryCode=zw
 *     -> Zimbabwe only
 * ============================================================
 */
function parseOptionalCountryCode(
  value: string | null,
): string | null {

  if (
    value === null ||
    value.trim() === ""
  ) {
    return null;
  }


  return value
    .trim()
    .toLowerCase();
}


Deno.serve(async (request: Request) => {
  try {

    // ========================================================
    // METHOD
    // ========================================================

    if (request.method !== "GET") {
      throw new AppError(
        "METHOD_NOT_ALLOWED",
        405,
      );
    }


    // ========================================================
    // AUTHENTICATION
    //
    // SQL performs the compliance role authorization.
    // ========================================================

    const {
      supabase,
      userId: reviewerId,
    } =
      await authenticateRequest(
        request,
      );


    // ========================================================
    // QUERY PARAMETERS
    //
    // ALL COUNTRIES:
    //
    // ?page=1&pageSize=20
    //
    // COUNTRY:
    //
    // ?page=1&pageSize=20&countryCode=zw
    // ========================================================

    const url =
      new URL(
        request.url,
      );


    // ========================================================
    // PAGE
    // ========================================================

    const page =
      parsePositiveInteger(
        url.searchParams.get(
          "page",
        ),
        1,
        "INVALID_PAGE",
      );


    // ========================================================
    // PAGE SIZE
    // ========================================================

    const pageSize =
      parsePositiveInteger(
        url.searchParams.get(
          "pageSize",
        ),
        20,
        "INVALID_PAGE_SIZE",
      );


    if (pageSize > 100) {
      throw new AppError(
        "INVALID_PAGE_SIZE",
        400,
      );
    }


    // ========================================================
    // COUNTRY
    // ========================================================

    const countryCode =
      parseOptionalCountryCode(
        url.searchParams.get(
          "countryCode",
        ),
      );


    // ========================================================
    // FETCH KYC REVIEW QUEUE
    // ========================================================

    const {
      data,
      error,
    } =
      await supabase.rpc(
        "fetch_kyc_review_queue",
        {
          p_page:
            page,

          p_page_size:
            pageSize,

          p_country_code:
            countryCode,
        },
      );


    // ========================================================
    // RPC ERROR
    // ========================================================

    if (error) {

      console.error(
        "FETCH_KYC_REVIEW_QUEUE_RPC_FAILED",
        {
          reviewerId,

          countryCode,

          page,

          pageSize,

          code:
            error.code,

          message:
            error.message,
        },
      );


      throw new AppError(
        error.message ||
          "FETCH_KYC_REVIEW_QUEUE_FAILED",
        400,
      );

    }


    // ========================================================
    // RESULT
    // ========================================================

    if (!data) {
      throw new AppError(
        "FETCH_KYC_REVIEW_QUEUE_FAILED",
        500,
      );
    }


    const result =
      data as
        KycReviewQueueResult;


    // ========================================================
    // SUCCESS
    // ========================================================

    return successResponse(
      result,
    );


  } catch (error) {

    console.error(
      "FETCH_KYC_REVIEW_QUEUE_ERROR",
      {
        error:
          error instanceof Error
            ? error.message
            : String(error),
      },
    );


    return errorResponse(
      error,
      "FETCH_KYC_REVIEW_QUEUE_FAILED",
    );

  }
});