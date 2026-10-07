import {
  getAddress,
} from "ethers";

import {
  errorResponse,
  successResponse,
} from "../../_shared/api-response.ts";

import {
  AppError,
} from "../../_shared/app-error.ts";

import {
  blockchainConfig,
  relayerContract,
} from "../../_shared/blockchain/client.ts";

import {
  createSupabaseClient,
  createSupabaseServiceClient,
} from "../../_shared/supabase-client.ts";

type ReconciliationRequest = {
  job_id?: unknown;
  jobId?: unknown;
  tx_hash?: unknown;
  txHash?: unknown;
};


type LiquidationReconciliationContext = {
  queue_id: string;
  liquidation_job_id: string;
  job_status: string;
  queue_status: string;
  manual_review_required: boolean;
  country_code: string;
  document_number: string | null;
  sender_wallet_address: string;
  receiver_wallet_address: string;
  collateral: string;
  tx_hash: string | null;
  signed_payload: Record<string, unknown>;
};


type StoredSignedPayload = {
  owner: string;
  to: string;
  amount: string;
  fee: string;
  parsedAmount: bigint;
  parsedFee: bigint;
  nonce: bigint;
  deadline: bigint;
  v: number;
  r: string;
  s: string;
};


function requiredString(
  value: unknown,
  errorMessage: string,
): string {
  if (
    typeof value !== "string" ||
    value.trim() === ""
  ) {
    throw new AppError(
      errorMessage,
      400,
    );
  }

  return value.trim();
}


function parseJobId(
  value: unknown,
): string {
  const jobId =
    requiredString(
      value,
      "LIQUIDATION_JOB_ID_REQUIRED",
    );

  if (
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      .test(jobId)
  ) {
    throw new AppError(
      "INVALID_LIQUIDATION_JOB_ID",
      400,
    );
  }

  return jobId;
}


function parseTransactionHash(
  value: unknown,
): string {
  const txHash =
    requiredString(
      value,
      "BLOCKCHAIN_TRANSACTION_HASH_REQUIRED",
    );

  if (
    !/^0x[0-9a-fA-F]{64}$/.test(
      txHash,
    )
  ) {
    throw new AppError(
      "INVALID_BLOCKCHAIN_TRANSACTION_HASH",
      400,
    );
  }

  return txHash;
}


function parseBigIntField(
  value: unknown,
  errorMessage: string,
): bigint {
  if (
    typeof value !== "string" &&
    typeof value !== "number" &&
    typeof value !== "bigint"
  ) {
    throw new AppError(errorMessage);
  }

  try {
    const parsedValue =
      BigInt(value.toString());

    if (parsedValue < 0n) {
      throw new Error(errorMessage);
    }

    return parsedValue;
  } catch {
    throw new AppError(errorMessage);
  }
}


function normalizeDecimal(
  value: unknown,
  errorMessage: string,
): string {
  const decimal =
    requiredString(
      value,
      errorMessage,
    );

  if (!/^\d+(\.\d+)?$/.test(decimal)) {
    throw new AppError(errorMessage);
  }

  const [
    integerPart,
    fractionalPart = "",
  ] = decimal.split(".");

  const normalizedInteger =
    integerPart.replace(
      /^0+(?=\d)/,
      "",
    );

  const normalizedFraction =
    fractionalPart.replace(
      /0+$/,
      "",
    );

  return normalizedFraction
    ? `${normalizedInteger}.${normalizedFraction}`
    : normalizedInteger;
}


function parseStoredPayload(
  value: unknown,
): StoredSignedPayload {
  if (
    value === null ||
    typeof value !== "object" ||
    Array.isArray(value)
  ) {
    throw new AppError(
      "LIQUIDATION_SIGNED_PAYLOAD_NOT_FOUND",
    );
  }

  const payload =
    value as Record<string, unknown>;

  const vValue =
    Number(payload.v);

  if (
    !Number.isSafeInteger(vValue) ||
    (vValue !== 27 && vValue !== 28)
  ) {
    throw new AppError(
      "INVALID_LIQUIDATION_SIGNATURE_V",
    );
  }

  const r =
    requiredString(
      payload.r,
      "INVALID_LIQUIDATION_SIGNATURE_R",
    );

  const s =
    requiredString(
      payload.s,
      "INVALID_LIQUIDATION_SIGNATURE_S",
    );

  if (
    !/^0x[0-9a-fA-F]{64}$/.test(r) ||
    !/^0x[0-9a-fA-F]{64}$/.test(s)
  ) {
    throw new AppError(
      "INVALID_LIQUIDATION_SIGNATURE",
    );
  }

  return {
    owner:
      getAddress(
        requiredString(
          payload.owner,
          "INVALID_LIQUIDATION_OWNER",
        ),
      ),

    to:
      getAddress(
        requiredString(
          payload.to,
          "INVALID_LIQUIDATION_RECEIVER",
        ),
      ),

    amount:
      normalizeDecimal(
        payload.amount,
        "INVALID_LIQUIDATION_AMOUNT",
      ),

    fee:
      normalizeDecimal(
        payload.fee,
        "INVALID_LIQUIDATION_FEE",
      ),

    parsedAmount:
      parseBigIntField(
        payload.parsedAmount,
        "INVALID_LIQUIDATION_RAW_AMOUNT",
      ),

    parsedFee:
      parseBigIntField(
        payload.parsedFee,
        "INVALID_LIQUIDATION_RAW_FEE",
      ),

    nonce:
      parseBigIntField(
        payload.nonce,
        "INVALID_LIQUIDATION_PERMIT_NONCE",
      ),

    deadline:
      parseBigIntField(
        payload.deadline,
        "INVALID_LIQUIDATION_PERMIT_DEADLINE",
      ),

    v:
      vValue,

    r,
    s,
  };
}


function parseContext(
  value: unknown,
): LiquidationReconciliationContext {
  if (
    value === null ||
    typeof value !== "object" ||
    Array.isArray(value)
  ) {
    throw new AppError(
      "LIQUIDATION_RECONCILIATION_CONTEXT_NOT_FOUND",
    );
  }

  const context =
    value as Record<string, unknown>;

  return {
    queue_id:
      requiredString(
        context.queue_id,
        "LIQUIDATION_QUEUE_ID_NOT_FOUND",
      ),

    liquidation_job_id:
      requiredString(
        context.liquidation_job_id,
        "LIQUIDATION_JOB_ID_NOT_FOUND",
      ),

    job_status:
      requiredString(
        context.job_status,
        "LIQUIDATION_JOB_STATUS_NOT_FOUND",
      ),

    queue_status:
      requiredString(
        context.queue_status,
        "LIQUIDATION_QUEUE_STATUS_NOT_FOUND",
      ),

    manual_review_required:
      context.manual_review_required === true,

    country_code:
      requiredString(
        context.country_code,
        "LIQUIDATION_COUNTRY_NOT_FOUND",
      ),

    document_number:
      typeof context.document_number === "string"
        ? context.document_number
        : null,

    sender_wallet_address:
      requiredString(
        context.sender_wallet_address,
        "LIQUIDATION_SENDER_NOT_FOUND",
      ),

    receiver_wallet_address:
      requiredString(
        context.receiver_wallet_address,
        "LIQUIDATION_RECEIVER_NOT_FOUND",
      ),

    collateral:
      requiredString(
        context.collateral,
        "LIQUIDATION_COLLATERAL_NOT_FOUND",
      ),

    tx_hash:
      typeof context.tx_hash === "string"
        ? context.tx_hash
        : null,

    signed_payload:
      context.signed_payload as Record<string, unknown>,
  };
}


function buildExplorerUrl(
  txHash: string,
): string | null {
  const configuredUrl =
    Deno.env
      .get("CHIADO_EXPLORER")
      ?.trim();

  if (!configuredUrl) {
    return null;
  }

  const baseUrl =
    configuredUrl.replace(
      /\/+$/,
      "",
    );

  if (
    baseUrl
      .toLowerCase()
      .endsWith("/tx")
  ) {
    return `${baseUrl}/${txHash}`;
  }

  return `${baseUrl}/tx/${txHash}`;
}


Deno.serve(async (request: Request) => {
  try {
    if (request.method !== "POST") {
      throw new AppError(
        "METHOD_NOT_ALLOWED",
        405,
      );
    }

    let body: ReconciliationRequest;

    try {
      body =
        await request.json() as
          ReconciliationRequest;
    } catch {
      throw new AppError(
        "INVALID_REQUEST_BODY",
        400,
      );
    }

    const jobId =
      parseJobId(
        body.job_id ??
          body.jobId,
      );

    const txHash =
      parseTransactionHash(
        body.tx_hash ??
          body.txHash,
      );

    /*
     * First authorize the Accounts/Finance caller and
     * enforce their country through the public report RPC.
     */
    const authenticatedSupabase =
      createSupabaseClient(request);

    const {
      data: authorizedJob,
      error: authorizationError,
    } = await authenticatedSupabase.rpc(
      "fetch_my_manual_review_liquidation_job",
      {
        p_job_id:
          jobId,
      },
    );

    if (
      authorizationError ||
      !authorizedJob
    ) {
      console.error(
        "LIQUIDATION_RECONCILIATION_AUTHORIZATION_FAILED",
        {
          jobId,
          code:
            authorizationError?.code,
          message:
            authorizationError?.message,
        },
      );

      throw new AppError(
        authorizationError?.message ||
          "MANUAL_REVIEW_LIQUIDATION_JOB_NOT_FOUND",
        authorizationError?.code === "42501"
          ? 403
          : 404,
      );
    }

    const serviceSupabase =
      createSupabaseServiceClient();

    const {
      data: contextData,
      error: contextError,
    } = await serviceSupabase.rpc(
      "fetch_liquidation_reconciliation_context",
      {
        p_job_id:
          jobId,
      },
    );

    if (contextError) {
      throw new AppError(
        contextError.message ||
          "LIQUIDATION_RECONCILIATION_CONTEXT_FAILED",
      );
    }

    const context =
      parseContext(contextData);

    if (!context.manual_review_required) {
      throw new AppError(
        "LIQUIDATION_MANUAL_REVIEW_NOT_REQUIRED",
        409,
      );
    }

    if (
      context.job_status !==
        "blockchain_processing" ||
      context.queue_status !==
        "processing"
    ) {
      throw new AppError(
        "INVALID_LIQUIDATION_MANUAL_REVIEW_STATE",
        409,
      );
    }

    if (
      context.tx_hash &&
      context.tx_hash.toLowerCase() !==
        txHash.toLowerCase()
    ) {
      throw new AppError(
        "LIQUIDATION_BLOCKCHAIN_TX_HASH_MISMATCH",
        409,
      );
    }

    const signed =
      parseStoredPayload(
        context.signed_payload,
      );

    if (
      getAddress(
        context.sender_wallet_address,
      ) !== signed.owner
    ) {
      throw new AppError(
        "LIQUIDATION_OWNER_ADDRESS_MISMATCH",
      );
    }

    if (
      getAddress(
        context.receiver_wallet_address,
      ) !== signed.to
    ) {
      throw new AppError(
        "LIQUIDATION_RECEIVER_ADDRESS_MISMATCH",
      );
    }

    if (
      normalizeDecimal(
        context.collateral,
        "INVALID_LIQUIDATION_COLLATERAL",
      ) !== signed.amount
    ) {
      throw new AppError(
        "LIQUIDATION_COLLATERAL_AMOUNT_MISMATCH",
      );
    }

    if (
      signed.fee !== "0" ||
      signed.parsedFee !== 0n
    ) {
      throw new AppError(
        "LIQUIDATION_TRANSFER_FEE_NOT_ALLOWED",
      );
    }

    const provider =
      relayerContract
        .runner
        ?.provider;

    if (!provider) {
      throw new AppError(
        "BLOCKCHAIN_PROVIDER_NOT_CONFIGURED",
      );
    }

    const [
      transaction,
      receipt,
    ] = await Promise.all([
      provider.getTransaction(txHash),
      provider.getTransactionReceipt(txHash),
    ]);

    if (!transaction) {
      throw new AppError(
        "BLOCKCHAIN_TRANSACTION_NOT_FOUND",
        404,
      );
    }

    if (!receipt) {
      throw new AppError(
        "BLOCKCHAIN_TRANSACTION_RECEIPT_PENDING",
        409,
      );
    }

    if (receipt.status !== 1) {
      throw new AppError(
        "TOKEN_TRANSFER_REVERTED",
        409,
      );
    }

    if (!transaction.to) {
      throw new AppError(
        "BLOCKCHAIN_TRANSACTION_RECEIVER_NOT_FOUND",
      );
    }

    const relayerAddress =
      getAddress(
        await relayerContract.getAddress(),
      );

    if (
      getAddress(transaction.to) !==
      relayerAddress
    ) {
      throw new AppError(
        "LIQUIDATION_RELAYER_CONTRACT_MISMATCH",
        409,
      );
    }

    const parsedTransaction =
      relayerContract.interface
        .parseTransaction({
          data:
            transaction.data,

          value:
            transaction.value,
        });

    if (
      !parsedTransaction ||
      parsedTransaction.name !==
        "transferWithPermitAndFee"
    ) {
      throw new AppError(
        "INVALID_LIQUIDATION_RELAYER_TRANSACTION",
        409,
      );
    }

    const args =
      parsedTransaction.args;

    const decodedOwner =
      getAddress(args[0].toString());

    const decodedReceiver =
      getAddress(args[1].toString());

    const decodedFeeReceiver =
      getAddress(args[2].toString());

    const decodedAmount =
      BigInt(args[3].toString());

    const decodedFee =
      BigInt(args[4].toString());

    const decodedDeadline =
      BigInt(args[5].toString());

    const decodedV =
      Number(args[6].toString());

    const decodedR =
      args[7].toString();

    const decodedS =
      args[8].toString();

    if (decodedOwner !== signed.owner) {
      throw new AppError(
        "LIQUIDATION_TRANSACTION_OWNER_MISMATCH",
        409,
      );
    }

    if (decodedReceiver !== signed.to) {
      throw new AppError(
        "LIQUIDATION_TRANSACTION_RECEIVER_MISMATCH",
        409,
      );
    }

    if (
      decodedFeeReceiver !==
      getAddress(
        blockchainConfig.treasuryAddress,
      )
    ) {
      throw new AppError(
        "LIQUIDATION_TRANSACTION_FEE_RECEIVER_MISMATCH",
        409,
      );
    }

    if (decodedAmount !== signed.parsedAmount) {
      throw new AppError(
        "LIQUIDATION_TRANSACTION_AMOUNT_MISMATCH",
        409,
      );
    }

    if (decodedFee !== signed.parsedFee) {
      throw new AppError(
        "LIQUIDATION_TRANSACTION_FEE_MISMATCH",
        409,
      );
    }

    if (decodedDeadline !== signed.deadline) {
      throw new AppError(
        "LIQUIDATION_TRANSACTION_DEADLINE_MISMATCH",
        409,
      );
    }

    if (
      decodedV !== signed.v ||
      decodedR.toLowerCase() !==
        signed.r.toLowerCase() ||
      decodedS.toLowerCase() !==
        signed.s.toLowerCase()
    ) {
      throw new AppError(
        "LIQUIDATION_TRANSACTION_SIGNATURE_MISMATCH",
        409,
      );
    }

    const explorerUrl =
      buildExplorerUrl(txHash);

    const verifiedResult = {
      verified:
        true,

      liquidation_job_id:
        context.liquidation_job_id,

      queue_id:
        context.queue_id,

      tx_hash:
        txHash,

      explorer_url:
        explorerUrl,

      block_number:
        receipt.blockNumber,

      verified_transfer: {
        relayer_contract:
          relayerAddress,

        owner:
          decodedOwner,

        receiver:
          decodedReceiver,

        raw_amount:
          decodedAmount.toString(),

        raw_fee:
          decodedFee.toString(),

        permit_nonce:
          signed.nonce.toString(),

        permit_deadline:
          decodedDeadline.toString(),
      },
    };

    /*
     * Only after every on-chain field matches the stored
     * signature may the database leave manual review.
     */

    const {
      data: confirmation,
      error: confirmationError,
    } = await serviceSupabase.rpc(
      "confirm_liquidation_blockchain_transfer",
      {
        p_queue_id:
          context.queue_id,

        p_tx_hash:
          txHash,

        p_explorer_url:
          explorerUrl,
      },
    );

    if (confirmationError) {
      console.error(
        "LIQUIDATION_RECONCILIATION_CONFIRMATION_FAILED",
        {
          jobId,
          queueId:
            context.queue_id,
          txHash,
          code:
            confirmationError.code,
          message:
            confirmationError.message,
          details:
            confirmationError.details,
          hint:
            confirmationError.hint,
        },
      );

      throw new AppError(
        confirmationError.message ||
          "LIQUIDATION_RECONCILIATION_CONFIRMATION_FAILED",
      );
    }

    return successResponse({
      ...verifiedResult,

      reconciled:
        true,

      confirmation,

      next_action:
        "WAIT_FOR_LIQUIDATION_ACCOUNTING",
    });
  } catch (error) {
    console.error(
      "RECONCILE_MANUAL_REVIEW_LIQUIDATION_ERROR",
      {
        error:
          error instanceof Error
            ? error.message
            : String(error),
      },
    );

    return errorResponse(
      error,
      "RECONCILE_MANUAL_REVIEW_LIQUIDATION_FAILED",
    );
  }
});
