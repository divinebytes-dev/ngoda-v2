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

    const authSupabase = createSupabaseClient(request);

    const authUser = await fetchAuthenticatedUser(authSupabase);

    const serviceSupabase = createSupabaseServiceClient();

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

    return successResponse(
      user.referral_code ?? null,
    );
  } catch (error) {
    console.error(
      "Error fetching referral code",
      {
        message:
          error instanceof Error
            ? error.message
            : "FAILED_TO_FETCH_REFERRAL_CODE",
      },
    );

    return errorResponse(
      error,
      "FAILED_TO_FETCH_REFERRAL_CODE",
    );
  }
});