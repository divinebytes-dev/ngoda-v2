import {
  errorResponse,
  successResponse,
} from "../../_shared/api-response.ts";

import {
  AppError,
} from "../../_shared/app-error.ts";

import {
  createSupabaseAnonClient,
} from "../../_shared/supabase-client.ts";


type VerifyPasswordResetOtpBody = {
  phone?: unknown;
  otp?: unknown;
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
 * PHONE
 * ============================================================
 */
function parsePhone(
  value: unknown,
): string {
  const phone =
    parseRequiredString(
      value,
      "PHONE_MISSING",
    );


  /*
   * The phone used here should already be the E.164 phone
   * returned/used by the password-reset request.
   *
   * Example:
   *
   * +263771234567
   */
  if (
    !/^\+[1-9]\d{7,14}$/.test(
      phone,
    )
  ) {
    throw new AppError(
      "INVALID_PHONE",
      400,
    );
  }


  return phone;
}


/*
 * ============================================================
 * OTP
 * ============================================================
 */
function parseOtp(
  value: unknown,
): string {
  const otp =
    parseRequiredString(
      value,
      "OTP_MISSING",
    );


  /*
   * Supabase OTPs are normally numeric.
   *
   * Do not convert this to a number because an OTP may begin
   * with zero.
   */
  if (!/^\d{6}$/.test(otp)) {
    throw new AppError(
      "INVALID_OTP",
      400,
    );
  }


  return otp;
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
    // REQUEST BODY
    //
    // Flutter:
    //
    // {
    //   "phone": "+263771234567",
    //   "otp": "123456"
    // }
    // ========================================================

    let body:
      VerifyPasswordResetOtpBody;


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


    const phone =
      parsePhone(
        body.phone,
      );


    const otp =
      parseOtp(
        body.otp,
      );


    // ========================================================
    // PUBLIC SUPABASE CLIENT
    //
    // The user is not authenticated yet.
    //
    // Successful OTP verification will establish the temporary
    // authenticated session that we use for password reset.
    // ========================================================

    const supabase =
      createSupabaseAnonClient();


    // ========================================================
    // VERIFY OTP
    // ========================================================

    const {
      data,
      error,
    } =
      await supabase.auth.verifyOtp({
        phone,
        token:
          otp,
        type:
          "sms",
      });


    if (error) {
      console.warn(
        "PASSWORD_RESET_OTP_VERIFICATION_FAILED",
        {
          message:
            error.message,

          status:
            error.status,
        },
      );


      throw new AppError(
        "INVALID_OR_EXPIRED_OTP",
        400,
      );
    }


    // ========================================================
    // SESSION
    //
    // Successful OTP verification should give us:
    //
    //   data.user
    //   data.session
    //
    // We require both before allowing Flutter to proceed to
    // the new-password step.
    // ========================================================

    if (
      !data.user ||
      !data.session
    ) {
      console.error(
        "PASSWORD_RESET_OTP_SESSION_MISSING",
      );


      throw new AppError(
        "OTP_VERIFICATION_FAILED",
        400,
      );
    }


    // ========================================================
    // IDENTITY CHECK
    //
    // Make sure the authenticated identity returned by
    // Supabase is for the phone that was verified.
    // ========================================================

    if (
      !data.user.phone ||
      data.user.phone !== phone
    ) {
      console.error(
        "PASSWORD_RESET_PHONE_MISMATCH",
        {
          userId:
            data.user.id,
        },
      );


      throw new AppError(
        "OTP_VERIFICATION_FAILED",
        400,
      );
    }


    // ========================================================
    // SUCCESS
    //
    // Flutter needs this session for the next call:
    //
    // reset-password
    //
    // Flutter sends the access token as:
    //
    // Authorization: Bearer <accessToken>
    //
    // The refresh token should also be retained so Flutter can
    // restore/refresh the session if required.
    // ========================================================

    return successResponse({
      verified:
        true,

      accessToken:
        data.session.access_token,

      refreshToken:
        data.session.refresh_token,

      expiresIn:
        data.session.expires_in,

      expiresAt:
        data.session.expires_at,
    });

  } catch (error) {

    console.error(
      "VERIFY_PASSWORD_RESET_OTP_ERROR",
      {
        error:
          error instanceof Error
            ? error.message
            : String(error),
      },
    );


    return errorResponse(
      error,
      "OTP_VERIFICATION_FAILED",
    );
  }
});