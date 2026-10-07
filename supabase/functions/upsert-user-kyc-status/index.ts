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


type VerifyUserKycBody = {
  userId?: unknown;
  decision?: unknown;
  comments?: unknown;
};


type VerifyUserKycResult = {
  user_id: string;
  kyc_id: string;
  decision: string;
  comments: string | null;
  verified_by: string;
  verified_at: string;
};


/*
 * ============================================================
 * REQUIRED STRING
 * ============================================================
 */
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


/*
 * ============================================================
 * OPTIONAL STRING
 * ============================================================
 */
function parseOptionalString(
  value: unknown,
): string | null {

  if (
    value === undefined ||
    value === null
  ) {
    return null;
  }


  if (typeof value !== "string") {
    throw new AppError(
      "INVALID_COMMENTS",
      400,
    );
  }


  const result =
    value.trim();


  return result === ""
    ? null
    : result;
}


/*
 * ============================================================
 * KYC DECISION
 *
 * Keep this aligned with public."KycStatus".
 *
 * Compliance can make only a final review decision through
 * this endpoint.
 * ============================================================
 */
function parseDecision(
  value: unknown,
): string {

  const decision =
    parseRequiredString(
      value,
      "KYC_DECISION_MISSING",
    ).toLowerCase();


  if (
    decision !== "verified" &&
    decision !== "rejected"
  ) {
    throw new AppError(
      "INVALID_KYC_DECISION",
      400,
    );
  }


  return decision;
}


Deno.serve(async (request: Request) => {
  try {

    // ========================================================
    // METHOD
    // ========================================================

    if (request.method !== "POST") {
      throw new AppError(
        "METHOD_NOT_ALLOWED",
        405,
      );
    }


    // ========================================================
    // AUTHENTICATION
    //
    // authenticateRequest validates the incoming Supabase
    // access token and creates the user-scoped client.
    //
    // SQL performs the final compliance role check.
    // ========================================================

    const {
      supabase,
      userId: reviewerId,
    } =
      await authenticateRequest(
        request,
      );


    // ========================================================
    // BODY
    // ========================================================

    let body:
      VerifyUserKycBody;


    try {
      body =
        await request.json();
    } catch {
      throw new AppError(
        "INVALID_REQUEST_BODY",
        400,
      );
    }


    if (
      body === null ||
      typeof body !== "object" ||
      Array.isArray(body)
    ) {
      throw new AppError(
        "INVALID_REQUEST_BODY",
        400,
      );
    }


    // ========================================================
    // USER ID
    // ========================================================

    const userId =
      parseRequiredString(
        body.userId,
        "USER_ID_MISSING",
      );


    // ========================================================
    // DECISION
    // ========================================================

    const decision =
      parseDecision(
        body.decision,
      );


    // ========================================================
    // COMMENTS
    // ========================================================

    const comments =
      parseOptionalString(
        body.comments,
      );


    // ========================================================
    // REJECTION REQUIRES COMMENTS
    //
    // SQL validates this again.
    // ========================================================

    if (
      decision === "rejected" &&
      comments === null
    ) {
      throw new AppError(
        "KYC_REJECTION_COMMENTS_REQUIRED",
        400,
      );
    }


    // ========================================================
    // VERIFY KYC
    //
    // Important:
    //
    // Use the authenticated client rather than the service
    // client because verify_user_kyc() checks:
    //
    // auth.uid()
    // has_role(['compliance'])
    // ========================================================

    const {
      data,
      error,
    } =
      await supabase.rpc(
        "verify_user_kyc",
        {
          p_user_id:
            userId,

          p_decision:
            decision,

          p_comments:
            comments,
        },
      );


    if (error) {

      console.error(
        "VERIFY_USER_KYC_RPC_FAILED",
        {
          reviewerId,
          userId,
          decision,

          code:
            error.code,

          message:
            error.message,
        },
      );


      throw new AppError(
        error.message ||
          "VERIFY_USER_KYC_FAILED",
        400,
      );

    }


    if (!data) {
      throw new AppError(
        "VERIFY_USER_KYC_FAILED",
        500,
      );
    }


    const result =
      data as
        VerifyUserKycResult;


    // ========================================================
    // ADDITIONAL IDENTITY CHECK
    //
    // SQL reports who performed the verification. It should
    // always match the authenticated reviewer.
    // ========================================================

    if (
      result.verified_by !==
        reviewerId
    ) {

      console.error(
        "KYC_REVIEWER_MISMATCH",
        {
          authenticatedReviewerId:
            reviewerId,

          returnedReviewerId:
            result.verified_by,

          userId,
        },
      );


      throw new AppError(
        "VERIFY_USER_KYC_FAILED",
        500,
      );

    }


    // ========================================================
    // SUCCESS
    // ========================================================

    return successResponse(
      result,
    );


  } catch (error) {

    console.error(
      "VERIFY_USER_KYC_ERROR",
      {
        error:
          error instanceof Error
            ? error.message
            : String(error),
      },
    );


    return errorResponse(
      error,
      "VERIFY_USER_KYC_FAILED",
    );

  }
});