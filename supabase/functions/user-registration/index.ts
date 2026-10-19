import {
  errorResponse,
  successResponse,
} from "../../_shared/api-response.ts";

import {
  createSupabaseAnonClient,
  createSupabaseServiceClient,
} from "../../_shared/supabase-client.ts";

import {
  AppError,
} from "../../_shared/app-error.ts";

import {
  Role,
} from "../../_shared/enums.ts";

import {
  deriveWallet,
  getWalletMnemonic,
} from "../../_shared/blockchain/wallet.ts";

import {
  createUniqueReferralCode,
} from "../../_shared/referral.ts";

import {
  fetchCountryCallingCode,
} from "../../_shared/country.ts";

import {
  normalizePhoneNumber,
} from "../../_shared/phone-number.ts";

type SignUpRequest = {
  phone?: string;
  email?: string;
  password?: string;
  country_code?: string;
  upliner_code?: string;
};

type RpcError = {
  code?: string;
  message?: string;
  details?: string | null;
  hint?: string | null;
};

type RpcResult = {
  data: unknown;
  error: RpcError | null;
};

type RpcClient = {
  rpc: (
    functionName: string,
    args?: Record<string, unknown>,
  ) => Promise<RpcResult>;
};

const PROFILE_ROLLBACK_ERROR_CODES = new Set([
  "P0001",
  "23505",
  "23503",
  "23514",
  "23502",
  "42501",
  "22023",
  "22P02",
  "22003",
  "40001",
  "40P01",
]);

function asRpcClient(
  client: unknown,
): RpcClient {
  return client as RpcClient;
}

function scalarValue(
  data: unknown,
): string | null {
  if (
    typeof data === "string" ||
    typeof data === "number"
  ) {
    return String(data);
  }

  if (
    Array.isArray(data) &&
    data.length > 0
  ) {
    const first = data[0];

    if (
      typeof first === "string" ||
      typeof first === "number"
    ) {
      return String(first);
    }

    if (
      first !== null &&
      typeof first === "object"
    ) {
      const value = Object.values(first)[0];

      if (
        typeof value === "string" ||
        typeof value === "number"
      ) {
        return String(value);
      }
    }
  }

  return null;
}

function logRpcError(
  event: string,
  error: RpcError,
): void {
  console.error(
    event,
    {
      code: error.code,
      message: error.message,
      details: error.details,
      hint: error.hint,
    },
  );
}

Deno.serve(
  async (
    request: Request,
  ): Promise<Response> => {
    /*
     * Set only after the database proves that this
     * registration attempt created the Auth account.
     */
    let authUserId: string | null = null;

    let profileCreated = false;
    let profileRequestStarted = false;
    let profileRollbackConfirmed = false;

    const registrationAttemptId =
      crypto.randomUUID();

    try {
      if (request.method !== "POST") {
        throw new AppError(
          "METHOD_NOT_ALLOWED",
          405,
        );
      }

      let body: SignUpRequest;

      try {
        const parsedBody: unknown =
          await request.json();

        if (
          parsedBody === null ||
          typeof parsedBody !== "object" ||
          Array.isArray(parsedBody)
        ) {
          throw new Error(
            "Invalid registration body",
          );
        }

        body = parsedBody as SignUpRequest;
      } catch {
        throw new AppError(
          "INVALID_REQUEST_BODY",
        );
      }

      const rawPhone =
        typeof body.phone === "string"
          ? body.phone.trim()
          : "";

      const email =
        typeof body.email === "string"
          ? body.email.trim().toLowerCase()
          : "";

      const password =
        typeof body.password === "string"
          ? body.password
          : "";

      const countryCode =
        typeof body.country_code === "string"
          ? body.country_code.trim().toLowerCase()
          : "";

      const uplinerCode =
        typeof body.upliner_code === "string"
          ? body.upliner_code.trim()
          : "";

      if (!rawPhone) {
        throw new AppError(
          "PHONE_REQUIRED",
        );
      }

      if (!password) {
        throw new AppError(
          "PASSWORD_REQUIRED",
        );
      }

      if (!countryCode) {
        throw new AppError(
          "COUNTRY_CODE_REQUIRED",
        );
      }

      /*
       * Registration does not require an existing session.
       * Never use createSupabaseClient(request) here.
       */
      const authSupabase =
        createSupabaseAnonClient();

      const serviceSupabase =
        createSupabaseServiceClient();

      const serviceRpc =
        asRpcClient(serviceSupabase);

      const callingCode =
        await fetchCountryCallingCode(
          countryCode,
        );

      const phone =
        normalizePhoneNumber(
          rawPhone,
          callingCode,
        );

      /*
       * Allocate the deterministic wallet index
       * through the privileged backend client.
       */
      const {
        data: walletIndexData,
        error: walletIndexError,
      } = await serviceRpc.rpc(
        "get_next_wallet_index",
      );

      if (walletIndexError) {
        logRpcError(
          "SIGN_UP_WALLET_INDEX_FAILED",
          walletIndexError,
        );

        throw new AppError(
          walletIndexError.message ||
            "WALLET_INDEX_CREATE_FAILED",
        );
      }

      const walletIndexValue =
        scalarValue(walletIndexData);

      if (!walletIndexValue) {
        throw new AppError(
          "WALLET_INDEX_CREATE_FAILED",
        );
      }

      const walletIndex =
        Number(walletIndexValue);

      if (
        !Number.isSafeInteger(walletIndex) ||
        walletIndex <= 0
      ) {
        throw new AppError(
          "INVALID_WALLET_INDEX",
        );
      }

      const mnemonic =
        getWalletMnemonic();

      const {
        address,
      } = deriveWallet(
        mnemonic,
        walletIndex,
      );

      const referralCode =
        await createUniqueReferralCode();

      /*
       * Supabase still controls normal email/SMS
       * confirmation behavior.
       *
       * The random attempt ID is captured by the
       * database trigger only when Auth inserts a user.
       */
      const {
        data: authData,
        error: authError,
      } = email
        ? await authSupabase.auth.signUp({
            email,
            password,
            options: {
              data: {
                ngoda_registration_attempt:
                  registrationAttemptId,
              },
            },
          })
        : await authSupabase.auth.signUp({
            phone,
            password,
            options: {
              channel: "sms",
              data: {
                ngoda_registration_attempt:
                  registrationAttemptId,
              },
            },
          });

      if (authError) {
        console.error(
          "SIGN_UP_AUTH_FAILED",
          {
            message: authError.message,
            status: authError.status,
          },
        );

        throw new AppError(
          authError.message ||
            "AUTH_USER_CREATE_FAILED",
          authError.status ?? 400,
        );
      }

      if (!authData.user) {
        throw new AppError(
          "AUTH_USER_CREATE_FAILED",
        );
      }

      /*
       * A returned Auth user alone is not proof that
       * this request created the account.
       *
       * Verify against the private INSERT-time record
       * before performing any admin update or cleanup.
       */
      const {
        data: creationProven,
        error: proofError,
      } = await serviceRpc.rpc(
        "verify_registration_auth_creation",
        {
          p_user_id:
            authData.user.id,

          p_attempt_id:
            registrationAttemptId,
        },
      );

      if (proofError) {
        logRpcError(
          "SIGN_UP_CREATION_PROOF_FAILED",
          proofError,
        );

        throw new AppError(
          "REGISTRATION_NOT_COMPLETED",
        );
      }

      if (creationProven !== true) {
        throw new AppError(
          "REGISTRATION_NOT_COMPLETED",
        );
      }

      authUserId =
        authData.user.id;

      /*
       * Apply required application metadata before
       * committing the application profile.
       *
       * Preserve Supabase provider metadata.
       * Do not mark the supplied phone as confirmed.
       */
      const {
        error: metadataError,
      } = await serviceSupabase.auth.admin
        .updateUserById(
          authUserId,
          {
            ...(email ? { phone } : {}),

            app_metadata: {
              ...authData.user.app_metadata,

              role:
                Role.customer,

              country_code:
                countryCode,

              wallet_index:
                walletIndex,

              email:
                authData.user.email ||
                email ||
                null,
            },
          },
        );

      if (metadataError) {
        console.error(
          "SIGN_UP_METADATA_UPDATE_FAILED",
          {
            authUserId,

            message:
              metadataError.message,

            status:
              metadataError.status,
          },
        );

        throw new AppError(
          "AUTH_METADATA_UPDATE_FAILED",
        );
      }

      /*
       * Create the application profile only after
       * required Auth metadata has been saved.
       */
      profileRequestStarted = true;

      const {
        data: profileData,
        error: profileError,
      } = await serviceRpc.rpc(
        "create_customer_profile",
        {
          p_user_id:
            authUserId,

          p_country_code:
            countryCode,

          p_phone:
            phone,

          p_email:
            email || null,

          p_wallet_address:
            address,

          p_wallet_index:
            walletIndex,

          p_referral_code:
            referralCode,

          p_upliner_code:
            uplinerCode || null,
        },
      );

      if (profileError) {
        /*
         * Known PostgreSQL statement errors establish
         * that the profile RPC rolled back.
         *
         * Transport or unknown errors do not establish
         * whether the profile transaction committed.
         */
        profileRollbackConfirmed =
          PROFILE_ROLLBACK_ERROR_CODES.has(
            profileError.code ?? "",
          );

        logRpcError(
          "SIGN_UP_PROFILE_FAILED",
          profileError,
        );

        throw new AppError(
          profileError.message ||
            "USER_PROFILE_CREATE_FAILED",
        );
      }

      profileCreated = true;

      return successResponse({
        user: {
          id:
            authUserId,

          email:
            email || null,

          phone,

          country_code:
            countryCode,

          wallet_address:
            address,

          wallet_index:
            walletIndex,

          referral_code:
            referralCode,
        },

        profile:
          profileData,

        requires_verification:
          authData.session == null,
      });
    } catch (error) {
      /*
       * Cleanup is permitted only for a proven new
       * account when the profile has not committed.
       */
      const cleanupPermitted =
        authUserId !== null &&
        !profileCreated &&
        (
          !profileRequestStarted ||
          profileRollbackConfirmed
        );

      if (cleanupPermitted && authUserId) {
        try {
          const serviceSupabase =
            createSupabaseServiceClient();

          /*
           * Do not delete Auth if a profile exists
           * or if its existence cannot be checked.
           */
          const {
            data: existingProfile,
            error: lookupError,
          } = await serviceSupabase
            .from("users")
            .select("id")
            .eq("id", authUserId)
            .maybeSingle();

          if (lookupError) {
            console.error(
              "SIGN_UP_AUTH_CLEANUP_DEFERRED",
              {
                authUserId,

                message:
                  lookupError.message,
              },
            );
          } else if (existingProfile) {
            console.warn(
              "SIGN_UP_PROFILE_ALREADY_COMMITTED",
              {
                authUserId,
              },
            );
          } else {
            const {
              error: cleanupError,
            } = await serviceSupabase.auth.admin
              .deleteUser(
                authUserId,
              );

            if (cleanupError) {
              console.error(
                "SIGN_UP_AUTH_CLEANUP_FAILED",
                {
                  authUserId,

                  message:
                    cleanupError.message,
                },
              );
            }
          }
        } catch (cleanupError) {
          console.error(
            "SIGN_UP_AUTH_CLEANUP_FAILED",
            {
              authUserId,

              error:
                cleanupError instanceof Error
                  ? cleanupError.message
                  : String(cleanupError),
            },
          );
        }
      }

      /*
       * If the profile response was lost, its database
       * transaction may already have committed.
       * Preserve Auth and flag the account for checking.
       */
      if (
        authUserId &&
        !profileCreated &&
        profileRequestStarted &&
        !profileRollbackConfirmed
      ) {
        console.error(
          "SIGN_UP_RECONCILIATION_REQUIRED",
          {
            authUserId,
          },
        );
      }

      console.error(
        "SIGN_UP_ERROR",
        {
          authUserId,
          profileCreated,

          error:
            error instanceof Error
              ? error.message
              : String(error),
        },
      );

      return errorResponse(
        error,
        "SIGN_UP_FAILED",
      );
    }
  },
);