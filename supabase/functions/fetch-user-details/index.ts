import {
  errorResponse,
  successResponse,
} from "../../_shared/api-response.ts";

import {
  AppError,
} from "../../_shared/app-error.ts";

import {
  createSupabaseClient,
} from "../../_shared/supabase-client.ts";


Deno.serve(async (request: Request) => {
  try {
    /*
     * ----------------------------------------------------------
     * Method
     * ----------------------------------------------------------
     */
    if (request.method !== "GET") {
      throw new AppError(
        "METHOD_NOT_ALLOWED",
        405,
      );
    }


    /*
     * ----------------------------------------------------------
     * Authenticated Supabase client
     * ----------------------------------------------------------
     */
    const supabase =
      createSupabaseClient(request);


    /*
     * ----------------------------------------------------------
     * Fetch current user's complete profile
     * ----------------------------------------------------------
     */
    const {
      data,
      error,
    } = await supabase.rpc(
      "fetch_my_user_details",
    );


    /*
     * ----------------------------------------------------------
     * RPC failure
     * ----------------------------------------------------------
     */
    if (error) {
      console.error(
        "FETCH_MY_USER_DETAILS_RPC_FAILED",
        {
          code: error.code,
          message: error.message,
          details: error.details,
          hint: error.hint,
        },
      );

      throw new AppError(
        error.message ||
          "FETCH_MY_USER_DETAILS_FAILED",
      );
    }


    /*
     * ----------------------------------------------------------
     * RPC must return a JSON object
     * ----------------------------------------------------------
     */
    if (
      data === null ||
      typeof data !== "object" ||
      Array.isArray(data)
    ) {
      throw new AppError(
        "INVALID_USER_DETAILS_RESULT",
      );
    }


    /*
     * ----------------------------------------------------------
     * Success
     * ----------------------------------------------------------
     */
    return successResponse(
      data,
    );
  } catch (error) {
    console.error(
      "FETCH_MY_USER_DETAILS_ERROR",
      {
        error:
          error instanceof Error
            ? error.message
            : String(error),
      },
    );


    return errorResponse(
      error,
      "FETCH_MY_USER_DETAILS_FAILED",
    );
  }
});