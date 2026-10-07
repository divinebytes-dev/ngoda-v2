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


type CompletePasswordResetBody = {
  newPassword?: unknown;
};


/*
 * ============================================================
 * REQUIRED PASSWORD
 *
 * Do not trim passwords.
 * ============================================================
 */
function parseRequiredPassword(
  value: unknown,
): string {
  if (
    typeof value !== "string" ||
    value.length === 0
  ) {
    throw new AppError(
      "NEW_PASSWORD_MISSING",
      400,
    );
  }

  return value;
}


/*
 * ============================================================
 * PASSWORD VALIDATION
 *
 * Keep aligned with:
 *
 * - registration
 * - change password
 * - reset password
 * ============================================================
 */
function validateNewPassword(
  password: string,
): void {

  if (password.length < 8) {
    throw new AppError(
      "PASSWORD_TOO_SHORT",
      400,
    );
  }


  if (!/[A-Z]/.test(password)) {
    throw new AppError(
      "PASSWORD_REQUIRES_UPPERCASE",
      400,
    );
  }


  if (!/[a-z]/.test(password)) {
    throw new AppError(
      "PASSWORD_REQUIRES_LOWERCASE",
      400,
    );
  }


  if (!/[0-9]/.test(password)) {
    throw new AppError(
      "PASSWORD_REQUIRES_NUMBER",
      400,
    );
  }


  if (
    !/[!@#$%^&*(),.?":{}|<>_\-+=]/.test(
      password,
    )
  ) {
    throw new AppError(
      "PASSWORD_REQUIRES_SPECIAL_CHARACTER",
      400,
    );
  }
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
    // AUTHENTICATE RESET SESSION
    //
    // Flutter must already have established a valid Supabase
    // session before calling this function.
    //
    // EMAIL:
    //
    // recovery link
    // -> Supabase recovery session
    // -> Flutter sends recovery access token
    //
    // PHONE:
    //
    // OTP verification
    // -> Supabase session
    // -> Flutter sends access token
    //
    // Flutter sends:
    //
    // Authorization: Bearer <access_token>
    //
    // authenticateRequest() validates that token with Supabase
    // and returns a user-scoped client.
    // ========================================================

    const {
      supabase,
      userId,
    } =
      await authenticateRequest(
        request,
      );


    // ========================================================
    // BODY
    //
    // Flutter:
    //
    // {
    //   "newPassword": "..."
    // }
    // ========================================================

    let body:
      CompletePasswordResetBody;


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
    // NEW PASSWORD
    // ========================================================

    const newPassword =
      parseRequiredPassword(
        body.newPassword,
      );


    validateNewPassword(
      newPassword,
    );


    // ========================================================
    // CHANGE PASSWORD
    //
    // supabase represents the user whose recovery/OTP session
    // Flutter supplied in the Authorization header.
    // ========================================================

    const {
      data: updateData,
      error: updateError,
    } =
      await supabase.auth.updateUser({
        password:
          newPassword,
      });


    if (
      updateError ||
      !updateData.user
    ) {
      console.error(
        "PASSWORD_RESET_UPDATE_FAILED",
        {
          userId,

          message:
            updateError?.message,

          status:
            updateError?.status,
        },
      );


      throw new AppError(
        "PASSWORD_RESET_UPDATE_FAILED",
        400,
      );
    }


    // ========================================================
    // IDENTITY CHECK
    //
    // The Auth user whose password was changed must be the
    // same user represented by the supplied access token.
    // ========================================================

    if (
      updateData.user.id !==
        userId
    ) {
      console.error(
        "PASSWORD_RESET_USER_MISMATCH",
        {
          sessionUserId:
            userId,

          updatedUserId:
            updateData.user.id,
        },
      );


      throw new AppError(
        "PASSWORD_RESET_FAILED",
        500,
      );
    }


    // ========================================================
    // SUCCESS
    //
    // Do not sign out here.
    //
    // Flutter owns the actual local Supabase session.
    //
    // After this succeeds Flutter should:
    //
    // 1. sign out the recovery/OTP session
    // 2. clear any locally retained recovery state
    // 3. navigate to Login
    //
    // The user then signs in normally with the new password.
    // ========================================================

    return successResponse({
      passwordReset:
        true,
    });


  } catch (error) {

    console.error(
      "COMPLETE_PASSWORD_RESET_ERROR",
      {
        error:
          error instanceof Error
            ? error.message
            : String(error),
      },
    );


    return errorResponse(
      error,
      "PASSWORD_RESET_FAILED",
    );

  }
});

