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
      const values =
        Object.values(first);

      const value =
        values[0];

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

Deno.serve(
  async (
    request: Request,
  ): Promise<Response> => {
    let authUserId: string | null = null;
    let profileCreated = false;

    try {
      if (request.method !== "POST") {
        throw new AppError(
          "METHOD_NOT_ALLOWED",
          405,
        );
      }

      let body: SignUpRequest;

      try {
        body =
          await request.json();
      } catch {
        throw new AppError(
          "INVALID_REQUEST_BODY",
        );
      }

      const rawPhone =
        body.phone?.trim();

      const email =
        body.email
          ?.trim()
          .toLowerCase();

      const password =
        body.password;

      const countryCode =
        body.country_code
          ?.trim()
          .toLowerCase();

      const uplinerCode =
        body.upliner_code
          ?.trim();

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
       * Public client for normal Supabase signup.
       *
       * Signup confirmation behaviour remains controlled
       * by the Supabase Auth configuration.
       */
      const authSupabase =
        createSupabaseClient(
          request,
        );

      /*
       * Service client is only used for privileged
       * application operations after signup.
       */
      const serviceSupabase =
        createSupabaseServiceClient();

      const serviceRpc =
        asRpcClient(
          serviceSupabase,
        );

      /*
       * Resolve the country calling code from configured
       * operational-country data.
       */
      const callingCode =
        await fetchCountryCallingCode(
          countryCode,
        );

      /*
       * Convert the supplied phone to E.164.
       */
      const phone =
        normalizePhoneNumber(
          rawPhone,
          callingCode,
        );

      /*
       * Allocate wallet index.
       */
      const {
        data: walletIndexData,
        error: walletIndexError,
      } = await serviceRpc.rpc(
        "get_next_wallet_index",
      );

      if (walletIndexError) {
        console.error(
          "SIGN_UP_WALLET_INDEX_FAILED",
          {
            code:
              walletIndexError.code,

            message:
              walletIndexError.message,

            details:
              walletIndexError.details,

            hint:
              walletIndexError.hint,
          },
        );

        throw new AppError(
          walletIndexError.message ||
            "WALLET_INDEX_CREATE_FAILED",
        );
      }

      const walletIndexValue =
        scalarValue(
          walletIndexData,
        );

      if (!walletIndexValue) {
        throw new AppError(
          "WALLET_INDEX_CREATE_FAILED",
        );
      }

      const walletIndex =
        Number(
          walletIndexValue,
        );

      if (
        !Number.isFinite(
          walletIndex,
        ) ||
        walletIndex <= 0
      ) {
        throw new AppError(
          "INVALID_WALLET_INDEX",
        );
      }

      /*
       * Derive deterministic blockchain wallet.
       */
      const mnemonic =
        getWalletMnemonic();

      const {
        address,
      } = deriveWallet(
        mnemonic,
        walletIndex,
      );

      /*
       * Generate referral code.
       */
      const referralCode =
        await createUniqueReferralCode();

      /*
       * Normal Supabase signup.
       *
       * When email exists:
       *   email + password is the signup identity.
       *
       * When email does not exist:
       *   phone + password is the signup identity.
       *
       * This preserves Supabase's normal confirmation
       * behaviour for whichever identifier performs signup.
       */
      const {
        data: authData,
        error: authError,
      } = email
        ? await authSupabase.auth.signUp({
            email,
            password,
          })
        : await authSupabase.auth.signUp({
            phone,
            password,
            options: {
              channel: "sms",
            },
          });

      if (authError) {
        console.error(
          "SIGN_UP_AUTH_FAILED",
          {
            phone,
            email,

            message:
              authError.message,

            status:
              authError.status,
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

      authUserId =
        authData.user.id;

      /*
       * When signup used email, attach the mandatory
       * phone to the SAME Supabase Auth user.
       *
       * Phone-only signup already has the phone.
       */
      if (email) {
        const {
          error: phoneUpdateError,
        } =
          await serviceSupabase.auth.admin
            .updateUserById(
              authUserId,
              {
                phone,
              },
            );

        if (phoneUpdateError) {
          console.error(
            "SIGN_UP_PHONE_UPDATE_FAILED",
            {
              authUserId,
              phone,

              message:
                phoneUpdateError.message,

              status:
                phoneUpdateError.status,
            },
          );

          throw new AppError(
            phoneUpdateError.message ||
              "AUTH_PHONE_UPDATE_FAILED",
          );
        }
      }

      /*
       * Create the application profile.
       *
       * public.users remains profile/application data;
       * authentication remains entirely in Supabase Auth.
       */
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
            email ?? null,

          p_wallet_address:
            address,

          p_wallet_index:
            walletIndex,

          p_referral_code:
            referralCode,

          p_upliner_code:
            uplinerCode ?? null,
        },
      );

      if (profileError) {
        console.error(
          "SIGN_UP_PROFILE_FAILED",
          {
            code:
              profileError.code,

            message:
              profileError.message,

            details:
              profileError.details,

            hint:
              profileError.hint,

            authUserId,
          },
        );

        throw new AppError(
          profileError.message ||
            "USER_PROFILE_CREATE_FAILED",
        );
      }

      profileCreated =
        true;

      /*
       * Add application metadata only after the
       * application profile has been created.
       */
      const {
        error: metadataError,
      } =
        await serviceSupabase.auth.admin
          .updateUserById(
            authUserId,
            {
              app_metadata: {
                role:
                  Role.customer,

                country_code:
                  countryCode,

                wallet_index:
                  walletIndex,
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
          metadataError.message ||
            "AUTH_METADATA_UPDATE_FAILED",
        );
      }

      return successResponse({
        user: {
          id:
            authData.user.id,

          email:
            email ?? null,

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

        /*
         * With normal signUp(), session being null tells
         * the frontend that Supabase is waiting for the
         * configured confirmation flow.
         */
        requires_verification:
          authData.session == null,
      });
    } catch (error) {
      /*
       * If Auth was created but registration failed,
       * remove the Auth user.
       *
       * If your profile RPC has already committed, don't
       * silently leave public.users behind. Ideally the
       * profile RPC should have a matching cleanup RPC,
       * or metadata should be applied before profile
       * creation depending on which failure semantics you
       * want.
       */
      if (
        authUserId &&
        !profileCreated
      ) {
        try {
          const serviceSupabase =
            createSupabaseServiceClient();

          await serviceSupabase.auth.admin
            .deleteUser(
              authUserId,
            );
        } catch (
          cleanupError
        ) {
          console.error(
            "SIGN_UP_AUTH_CLEANUP_FAILED",
            {
              authUserId,

              error:
                cleanupError instanceof Error
                  ? cleanupError.message
                  : String(
                    cleanupError,
                  ),
            },
          );
        }
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