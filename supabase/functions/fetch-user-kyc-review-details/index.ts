import {
  errorResponse,
  successResponse,
} from "../../_shared/api-response.ts";

import {
  AppError,
} from "../../_shared/app-error.ts";

import {
  authenticateRequest,
  createSupabaseServiceClient,
} from "../../_shared/supabase-client.ts";


type FetchKycReviewBody = {
  userId?: unknown;
};


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
    // AUTHENTICATE COMPLIANCE USER
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
      FetchKycReviewBody;


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


    const userId =
      parseRequiredString(
        body.userId,
        "USER_ID_MISSING",
      );


    // ========================================================
    // FETCH KYC REVIEW
    //
    // Use the authenticated client.
    //
    // This is important because the SQL function checks
    // auth.uid() and has_role().
    // ========================================================

    const {
      data,
      error,
    } =
      await supabase.rpc(
        "fetch_user_kyc_review",
        {
          p_user_id:
            userId,
        },
      );


    if (error) {
      console.error(
        "FETCH_KYC_REVIEW_FAILED",
        {
          reviewerId,
          userId,

          code:
            error.code,

          message:
            error.message,
        },
      );


      throw new AppError(
        error.message ||
          "FETCH_KYC_REVIEW_FAILED",
        400,
      );
    }


    if (!data) {
      throw new AppError(
        "KYC_REVIEW_NOT_FOUND",
        404,
      );
    }


    // ========================================================
    // SIGNED DOCUMENT URLS
    //
    // user_verification_document.url stores the private
    // Storage object path.
    //
    // Compliance needs temporary signed URLs to actually view
    // the documents.
    // ========================================================

    const serviceSupabase =
      createSupabaseServiceClient();


    const response =
      structuredClone(data);


    const documents =
      response
        ?.verification_documents;


    if (documents) {

      const documentKeys = [
        "id_front",
        "id_back",
        "proof_of_address",
        "selfie",
      ];


      for (
        const documentKey
        of documentKeys
      ) {

        const document =
          documents[documentKey];


        if (
          !document ||
          !document.url
        ) {
          continue;
        }


        const {
          data: signedUrlData,
          error: signedUrlError,
        } =
          await serviceSupabase
            .storage
            .from(
              "user-verification",
            )
            .createSignedUrl(
              document.url,
              60 * 10,
            );


        if (signedUrlError) {

          console.error(
            "KYC_DOCUMENT_SIGNED_URL_FAILED",
            {
              reviewerId,
              userId,
              documentId:
                document.id,

              documentType:
                document.document_type,

              message:
                signedUrlError.message,
            },
          );


          /*
           * Do not fail the entire review merely because one
           * document could not obtain a signed URL.
           */
          document.signed_url =
            null;

          continue;
        }


        document.signed_url =
          signedUrlData.signedUrl;

      }

    }


    // ========================================================
    // SUCCESS
    // ========================================================

    return successResponse(
      response,
    );


  } catch (error) {

    console.error(
      "FETCH_KYC_REVIEW_ERROR",
      {
        error:
          error instanceof Error
            ? error.message
            : String(error),
      },
    );


    return errorResponse(
      error,
      "FETCH_KYC_REVIEW_FAILED",
    );

  }
});