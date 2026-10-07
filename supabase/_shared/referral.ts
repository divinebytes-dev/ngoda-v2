import {
  createSupabaseServiceClient,
} from "./supabase-client.ts";

const REFERRAL_CHARS =
  "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

export function generateReferralCode(
  length = 8,
): string {
  const bytes = new Uint8Array(length);

  crypto.getRandomValues(bytes);

  return Array.from(bytes)
    .map(
      (byte) =>
        REFERRAL_CHARS[
          byte % REFERRAL_CHARS.length
        ],
    )
    .join("");
}

export async function createUniqueReferralCode():
  Promise<string> {
  const supabase =
    createSupabaseServiceClient();

  let code: string;

  do {
    code = generateReferralCode();

    const {
      data,
      error,
    } = await supabase
      .from("users")
      .select("id")
      .eq("referral_code", code)
      .maybeSingle();

    if (error) {
      console.error(
        "REFERRAL_CODE_CHECK_FAILED",
        {
          code: error.code,
          message: error.message,
          details: error.details,
          hint: error.hint,
        },
      );

      throw new Error(
        "REFERRAL_CODE_CHECK_FAILED",
      );
    }

    if (!data) {
      return code;
    }
  } while (true);
}