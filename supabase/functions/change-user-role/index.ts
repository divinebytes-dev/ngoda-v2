import {
  errorResponse,
  successResponse,
} from "../../_shared/api-response.ts";

import {
  createSupabaseClient,
  createSupabaseServiceClient,
} from "../../_shared/supabase-client.ts";

import {
  AppError,
} from "../../_shared/app-error.ts";


type ChangeUserRoleBody = {
  identifier?: string;
  email?: string;
  new_role?: string;
};


type ChangeUserRoleResult = {
  success: boolean;
  changed: boolean;
  user_id: string;
  user_email: string | null;
  user_phone: string | null;
  country_code: string;
  old_role_name: string;
  new_role_name: string;
};


Deno.serve(async (request: Request) => {
  try {
    if (request.method !== "POST") {
      throw new AppError(
        "METHOD_NOT_ALLOWED",
        405,
      );
    }

    let body: ChangeUserRoleBody;

    try {
      body =
        await request.json() as
          ChangeUserRoleBody;
    } catch {
      throw new AppError(
        "INVALID_REQUEST_BODY",
      );
    }

    /*
     * Keep email as a temporary fallback so existing
     * Flutter requests do not break immediately.
     */
    const identifier =
      (
        body.identifier ??
        body.email
      )
        ?.trim();

    const newRole =
      body.new_role
        ?.trim()
        .toLowerCase();

    if (!identifier) {
      throw new AppError(
        "USER_IDENTIFIER_REQUIRED",
      );
    }

    if (!newRole) {
      throw new AppError(
        "NEW_ROLE_REQUIRED",
      );
    }

    if (newRole === "admin") {
      throw new AppError(
        "CANNOT_ASSIGN_ROLE",
      );
    }

    /*
     * The authenticated client allows PostgreSQL to
     * validate the calling administrator.
     */
    const authSupabase =
      createSupabaseClient(request);

    const {
      data,
      error: roleChangeError,
    } = await authSupabase.rpc(
      "change_my_user_role",
      {
        p_identifier:
          identifier,

        p_new_role:
          newRole,
      },
    );

    if (roleChangeError) {
      console.error(
        "CHANGE_USER_ROLE_RPC_FAILED",
        {
          code:
            roleChangeError.code,

          message:
            roleChangeError.message,

          details:
            roleChangeError.details,

          hint:
            roleChangeError.hint,

          identifier,

          newRole,
        },
      );

      throw new AppError(
        roleChangeError.message ||
          "FAILED_TO_CHANGE_USER_ROLE",
      );
    }

    if (
      !data ||
      typeof data !== "object" ||
      Array.isArray(data)
    ) {
      throw new AppError(
        "CHANGE_USER_ROLE_RESULT_NOT_FOUND",
      );
    }

    const result =
      data as unknown as
        ChangeUserRoleResult;

    if (
      !result.success ||
      !result.user_id ||
      !result.new_role_name
    ) {
      throw new AppError(
        "INVALID_CHANGE_USER_ROLE_RESULT",
      );
    }

    /*
     * Synchronize Supabase Auth app metadata.
     *
     * This requires the service-role client.
     */
    const serviceSupabase =
      createSupabaseServiceClient();

    const {
      data: authUserData,
      error: authUserError,
    } = await serviceSupabase.auth.admin.getUserById(
      result.user_id,
    );

    if (authUserError || !authUserData.user) {
      console.error(
        "FETCH_AUTH_USER_FOR_ROLE_SYNC_FAILED",
        {
          userId:
            result.user_id,

          message:
            authUserError?.message,
        },
      );

      throw new AppError(
        authUserError?.message ||
          "AUTH_USER_NOT_FOUND",
      );
    }

    /*
     * Preserve all existing app metadata while replacing
     * only the role.
     */
    const existingAppMetadata =
      authUserData.user.app_metadata ??
      {};

    const {
      error: authUpdateError,
    } = await serviceSupabase.auth.admin.updateUserById(
      result.user_id,
      {
        app_metadata: {
          ...existingAppMetadata,
          role:
            result.new_role_name,
        },
      },
    );

    if (authUpdateError) {
      console.error(
        "AUTH_USER_ROLE_SYNC_FAILED",
        {
          userId:
            result.user_id,

          newRole:
            result.new_role_name,

          message:
            authUpdateError.message,
        },
      );

      /*
       * The RPC is idempotent. Retrying this request will
       * skip the database update and retry this metadata
       * synchronization.
       */
      throw new AppError(
        authUpdateError.message ||
          "AUTH_USER_ROLE_SYNC_FAILED",
      );
    }

    return successResponse({
      success: true,
      changed:
        result.changed,
      user_id:
        result.user_id,
      user_email:
        result.user_email,
      user_phone:
        result.user_phone,
      country_code:
        result.country_code,
      old_role_name:
        result.old_role_name,
      new_role_name:
        result.new_role_name,
      auth_role_updated:
        true,
    });
  } catch (error) {
    return errorResponse(
      error,
      "FAILED_TO_CHANGE_USER_ROLE",
    );
  }
});