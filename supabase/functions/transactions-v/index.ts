import {
  errorResponse,
  successResponse,
} from "../../_shared/api-response.ts";

import {
  createSupabaseClient,
  createSupabaseServiceClient,
} from "../../_shared/supabase-client.ts";

import {
  fetchAuthenticatedUser,
  fetchUserWithId,
  requireRole,
} from "../../_shared/user-service.ts";

import {
  Role,
} from "../../_shared/enums.ts";

import {
  AppError,
} from "../../_shared/app-error.ts";

Deno.serve(async (request: Request) => {
  try {
    if (request.method !== "POST") {
      throw new AppError(
        "METHOD_NOT_ALLOWED",
      );
    }

    /*
     * User-scoped client validates the caller's JWT.
     */
    const authSupabase =
      createSupabaseClient(request);

    const authUser =
      await fetchAuthenticatedUser(
        authSupabase,
      );

    /*
     * Service client performs protected database work.
     */
    const serviceSupabase =
      createSupabaseServiceClient();

    const user = await fetchUserWithId(
      serviceSupabase,
      authUser.id,
    );

    requireRole(user, [
      Role.customer,
      Role.treasury,
      Role.finance,
      Role.agent,
      Role.admin,
      Role.accounts,
      Role.merchant,
      Role.vendor,
    ]);

    const {
      data,
      error,
    } = await serviceSupabase.rpc(
      "get_all_transaction_v",
    );

    if (error) {
      console.error(
        "Transaction-version RPC failed",
        {
          code: error.code,
          message: error.message,
          details: error.details,
          hint: error.hint,
          authenticatedUserId:
            authUser.id,
        },
      );

      throw new AppError(
        "FAILED_TO_FETCH_V",
      );
    }

    return successResponse(
      data ?? [],
    );
  } catch (error) {
    console.error(
      "Error fetching transaction versions",
      error,
    );

    return errorResponse(
      error,
      "FAILED_TO_FETCH_V",
    );
  }
});