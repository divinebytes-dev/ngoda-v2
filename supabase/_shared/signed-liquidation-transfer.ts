import { AppError } from "./app-error.ts";
import { createSupabaseServiceClient } from "./supabase-client.ts";


import {
  blockchainConfig,
} from "../_shared/blockchain/client.ts";

import {
  signTransfer,
} from "../_shared/blockchain/permit.ts";

import type {
  SignedTokenTransfer,
} from "../_shared/blockchain/permit.ts";



/*
 * This is a TypeScript representation of one row returned
 * by claim_country_liquidation_blockchain_jobs().
 *
 * It is not a database table.
 *
 * The actual database table is:
 *
 * public.liquidation_blockchain_queue
 */
export type ClaimedLiquidationBlockchainQueueJob = {
  queue_id: string;
  liquidation_job_id: string;

  user_id: string;
  wallet_index: string | number;

  treasury_id: string;
  sender_wallet_address: string;

  collateral: string;

  debt_repayment_amount: string;
  penalty_amount: string;
  total_liquidation_proceeds: string;
  total_debt: string;

  gold_price: string;

  document_number: string;

  fiscal_year: number;
  period: number;

  country_code: string;

  retry_count: number;

  signed_payload:
    Record<string, unknown> | null;
};


/*
 * BigInt values cannot be stored directly in JSONB.
 *
 * Therefore, blockchain integers are converted to strings
 * before saving the payload.
 */
type StoredSignedTokenTransfer = {
  owner: string;
  to: string;

  amount: string;
  fee: string;

  parsedAmount: string;
  parsedFee: string;

  nonce: string;
  deadline: string;

  v: string;
  r: string;
  s: string;
};


type SaveSignedPayloadResult = {
  success: boolean;
  queue_id: string;
  already_signed: boolean;

  signed_payload:
    Record<string, unknown>;
};


function requiredString(
  value: unknown,
  errorMessage: string,
): string {
  if (
    typeof value !== "string" &&
    typeof value !== "number" &&
    typeof value !== "bigint"
  ) {
    throw new AppError(
      errorMessage,
    );
  }

  const result =
    value.toString().trim();

  if (!result) {
    throw new AppError(
      errorMessage,
    );
  }

  return result;
}


function serializeSignedTransfer(
  signed: SignedTokenTransfer,
): StoredSignedTokenTransfer {
  return {
    owner:
      signed.owner,

    to:
      signed.to,

    amount:
      signed.amount,

    fee:
      signed.fee,

    parsedAmount:
      signed.parsedAmount
        .toString(),

    parsedFee:
      signed.parsedFee
        .toString(),

    nonce:
      signed.nonce
        .toString(),

    deadline:
      signed.deadline
        .toString(),

    v:
      signed.v.toString(),

    r:
      signed.r,

    s:
      signed.s,
  };
}


function deserializeSignedTransfer(
  value: Record<string, unknown>,
): SignedTokenTransfer {
  const v =
    Number(
      requiredString(
        value.v,
        "SIGNED_PAYLOAD_V_REQUIRED",
      ),
    );

  if (
    !Number.isSafeInteger(v) ||
    v < 0
  ) {
    throw new AppError(
      "INVALID_SIGNED_PAYLOAD_V",
    );
  }

  try {
    return {
      owner:
        requiredString(
          value.owner,
          "SIGNED_PAYLOAD_OWNER_REQUIRED",
        ),

      to:
        requiredString(
          value.to,
          "SIGNED_PAYLOAD_RECEIVER_REQUIRED",
        ),

      amount:
        requiredString(
          value.amount,
          "SIGNED_PAYLOAD_AMOUNT_REQUIRED",
        ),

      fee:
        requiredString(
          value.fee,
          "SIGNED_PAYLOAD_FEE_REQUIRED",
        ),

      parsedAmount:
        BigInt(
          requiredString(
            value.parsedAmount,
            "SIGNED_PAYLOAD_PARSED_AMOUNT_REQUIRED",
          ),
        ),

      parsedFee:
        BigInt(
          requiredString(
            value.parsedFee,
            "SIGNED_PAYLOAD_PARSED_FEE_REQUIRED",
          ),
        ),

      nonce:
        BigInt(
          requiredString(
            value.nonce,
            "SIGNED_PAYLOAD_NONCE_REQUIRED",
          ),
        ),

      deadline:
        BigInt(
          requiredString(
            value.deadline,
            "SIGNED_PAYLOAD_DEADLINE_REQUIRED",
          ),
        ),

      v,

      r:
        requiredString(
          value.r,
          "SIGNED_PAYLOAD_R_REQUIRED",
        ),

      s:
        requiredString(
          value.s,
          "SIGNED_PAYLOAD_S_REQUIRED",
        ),
    };
  } catch (error) {
    if (error instanceof AppError) {
      throw error;
    }

    throw new AppError(
      "INVALID_STORED_LIQUIDATION_SIGNATURE",
    );
  }
}


function validateSignedLiquidationTransfer(
  input: {
    signed: SignedTokenTransfer;
    job: ClaimedLiquidationBlockchainQueueJob;
    treasuryAddress: string;
  },
): void {
  if (
    input.signed.owner
      .toLowerCase() !==
    input.job.sender_wallet_address
      .toLowerCase()
  ) {
    throw new AppError(
      "LIQUIDATION_OWNER_ADDRESS_MISMATCH",
    );
  }

  if (
    input.signed.to
      .toLowerCase() !==
    input.treasuryAddress
      .toLowerCase()
  ) {
    throw new AppError(
      "LIQUIDATION_TREASURY_ADDRESS_MISMATCH",
    );
  }

  if (
    input.signed.amount !==
    input.job.collateral
  ) {
    throw new AppError(
      "LIQUIDATION_COLLATERAL_AMOUNT_MISMATCH",
    );
  }

  if (input.signed.fee !== "0") {
    throw new AppError(
      "LIQUIDATION_BLOCKCHAIN_FEE_NOT_ALLOWED",
    );
  }
}


/*
 * This is where prepareSignedLiquidationTransfer is
 * defined.
 *
 * It either:
 *
 * 1. returns the signature already stored in the queue; or
 * 2. creates, stores and returns a new signature.
 */
export async function prepareSignedLiquidationTransfer(
  input: {
    supabase: ReturnType<
      typeof createSupabaseServiceClient
    >;

    job:
      ClaimedLiquidationBlockchainQueueJob;
  },
): Promise<SignedTokenTransfer> {
  /*
   * One global blockchain treasury address is used for
   * Gold-token movements.
   */
  const treasuryAddress =
    blockchainConfig
      .treasuryAddress
      .trim();

  if (!treasuryAddress) {
    throw new AppError(
      "GLOBAL_TREASURY_WALLET_NOT_CONFIGURED",
    );
  }

  const senderWalletAddress =
    input.job
      .sender_wallet_address
      ?.trim();

  if (!senderWalletAddress) {
    throw new AppError(
      "LIQUIDATION_SENDER_WALLET_ADDRESS_REQUIRED",
    );
  }

  /*
   * Reuse the stored signature when the queue was
   * previously signed.
   */
  if (input.job.signed_payload) {
    const storedTransfer =
      deserializeSignedTransfer(
        input.job.signed_payload,
      );

    validateSignedLiquidationTransfer({
      signed:
        storedTransfer,

      job:
        input.job,

      treasuryAddress,
    });

    return storedTransfer;
  }

  const walletIndex =
    Number(
      input.job.wallet_index,
    );

  if (
    !Number.isSafeInteger(
      walletIndex,
    ) ||
    walletIndex < 0
  ) {
    throw new AppError(
      "INVALID_USER_WALLET_INDEX",
    );
  }

  const collateralAmount =
    input.job.collateral
      ?.toString()
      .trim();

  if (
    !collateralAmount ||
    !/^\d+(\.\d+)?$/.test(
      collateralAmount,
    )
  ) {
    throw new AppError(
      "INVALID_LIQUIDATION_COLLATERAL_AMOUNT",
    );
  }

  /*
   * signTransfer confirms that walletIndex derives the
   * expected sender wallet address.
   */
  const newlySignedTransfer =
    await signTransfer({
      fromIndex:
        walletIndex,

      expectedOwner:
        senderWalletAddress,

      to:
        treasuryAddress,

      amount:
        collateralAmount,

      fee:
        "0",
    });

  validateSignedLiquidationTransfer({
    signed:
      newlySignedTransfer,

    job:
      input.job,

    treasuryAddress,
  });

  const payloadToStore =
    serializeSignedTransfer(
      newlySignedTransfer,
    );

  const {
    data,
    error,
  } = await input.supabase.rpc(
    "save_liquidation_blockchain_signed_payload",
    {
      p_queue_id:
        input.job.queue_id,

      p_signed_payload:
        payloadToStore,
    },
  );

  if (error) {
    console.error(
      "SAVE_LIQUIDATION_SIGNED_PAYLOAD_RPC_FAILED",
      {
        code:
          error.code,

        message:
          error.message,

        details:
          error.details,

        hint:
          error.hint,

        queueId:
          input.job.queue_id,
      },
    );

    throw new AppError(
      error.message ||
        "FAILED_TO_SAVE_LIQUIDATION_SIGNED_PAYLOAD",
    );
  }

  const result =
    data as
      SaveSignedPayloadResult | null;

  if (!result?.signed_payload) {
    throw new AppError(
      "SIGNED_LIQUIDATION_PAYLOAD_NOT_RETURNED",
    );
  }

  /*
   * The RPC may return an existing signature saved by a
   * concurrent invocation. Always use what the database
   * returned.
   */
  const storedTransfer =
    deserializeSignedTransfer(
      result.signed_payload,
    );

  validateSignedLiquidationTransfer({
    signed:
      storedTransfer,

    job:
      input.job,

    treasuryAddress,
  });

  return storedTransfer;
}