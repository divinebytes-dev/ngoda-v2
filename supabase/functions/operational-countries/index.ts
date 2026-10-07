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

Deno.serve(async (request: Request) => {
  try {
    /*
     * Support direct GET requests and Flutter functions.invoke(),
     * which normally uses POST.
     */
    if (
      request.method !== "GET" &&
      request.method !== "POST"
    ) {
      throw new AppError(
        "METHOD_NOT_ALLOWED",
      );
    }

const anonSupabase =
  createSupabaseAnonClient();

const { data, error } =
  await anonSupabase.rpc(
    "fetch_operational_countries",
  );


    if (error) {
      console.error(
        "Operational-country RPC failed",
        {
          code: error.code,
          message: error.message,
          details: error.details,
          hint: error.hint,
        },
      );

      throw new AppError(
        "COUNTRY_FETCH_FAILED",
      );
    }

    return successResponse(
      data ?? [],
    );
  } catch (error) {
    console.error(
      "Error fetching operational countries",
      {
        message:
          error instanceof Error
            ? error.message
            : "COUNTRY_FETCH_FAILED",
      },
    );

    return errorResponse(
      error,
      "COUNTRY_FETCH_FAILED",
    );
  }
});