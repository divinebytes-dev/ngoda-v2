import {
  AppError,
} from "../app-error.ts";

import type {
  SignedTokenTransfer,
} from "../blockchain/permit.ts";

import type {
  StoredSignedTokenTransfer,
} from "../types/stored-signed-token-transfer.ts";

import type {
  ClaimedLiquidationBlockchainQueueJob,
} from "../types/claimed-liquidation-blockchain-queue-job.ts";

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
    value
      .toString()
      .trim();

  if (!result) {
    throw new AppError(
      errorMessage,
    );
  }

  return result;
}


function requiredAddress(
  value: unknown,
  errorMessage: string,
): string {
  const address =
    requiredString(
      value,
      errorMessage,
    );

  if (
    !/^0x[a-fA-F0-9]{40}$/.test(
      address,
    )
  ) {
    throw new AppError(
      errorMessage,
    );
  }

  return address;
}


function requiredSignaturePart(
  value: unknown,
  errorMessage: string,
): string {
  const signaturePart =
    requiredString(
      value,
      errorMessage,
    );

  if (
    !/^0x[a-fA-F0-9]{64}$/.test(
      signaturePart,
    )
  ) {
    throw new AppError(
      errorMessage,
    );
  }

  return signaturePart;
}


function normalizeDecimal(
  value: unknown,
  errorMessage: string,
): string {
  const rawValue =
    requiredString(
      value,
      errorMessage,
    );

  if (
    !/^\d+(\.\d+)?$/.test(
      rawValue,
    )
  ) {
    throw new AppError(
      errorMessage,
    );
  }

  const [
    integerPartRaw,
    fractionPartRaw = "",
  ] = rawValue.split(".");

  const integerPart =
    integerPartRaw.replace(
      /^0+(?=\d)/,
      "",
    );

  const fractionPart =
    fractionPartRaw.replace(
      /0+$/,
      "",
    );

  if (!fractionPart) {
    return integerPart;
  }

  return `${integerPart}.${fractionPart}`;
}


function requiredBigInt(
  value: unknown,
  errorMessage: string,
): bigint {
  const rawValue =
    requiredString(
      value,
      errorMessage,
    );

  if (
    !/^\d+$/.test(
      rawValue,
    )
  ) {
    throw new AppError(
      errorMessage,
    );
  }

  try {
    return BigInt(
      rawValue,
    );
  } catch {
    throw new AppError(
      errorMessage,
    );
  }
}


export function storeSignedTransfer(
  signed:
    SignedTokenTransfer,
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
      signed.v,

    r:
      signed.r,

    s:
      signed.s,
  };
}


export function restoreSignedTransfer(
  payload:
    Record<string, unknown>,

  job:
    ClaimedLiquidationBlockchainQueueJob,

  expectedTreasuryAddress?: string,
): SignedTokenTransfer {
  try {
    const v =
      Number(
        payload.v,
      );

    if (
      !Number.isSafeInteger(v) ||
      (
        v !== 27 &&
        v !== 28
      )
    ) {
      throw new AppError(
        "INVALID_SIGNED_PAYLOAD_V",
      );
    }

    const parsedAmount =
      requiredBigInt(
        payload.parsedAmount,
        "SIGNED_PAYLOAD_PARSED_AMOUNT_REQUIRED",
      );

    const parsedFee =
      requiredBigInt(
        payload.parsedFee,
        "SIGNED_PAYLOAD_PARSED_FEE_REQUIRED",
      );

    const nonce =
      requiredBigInt(
        payload.nonce,
        "SIGNED_PAYLOAD_NONCE_REQUIRED",
      );

    const deadline =
      requiredBigInt(
        payload.deadline,
        "SIGNED_PAYLOAD_DEADLINE_REQUIRED",
      );

    if (
      parsedAmount <= 0n
    ) {
      throw new AppError(
        "INVALID_SIGNED_PAYLOAD_PARSED_AMOUNT",
      );
    }

    if (
      parsedFee < 0n
    ) {
      throw new AppError(
        "INVALID_SIGNED_PAYLOAD_PARSED_FEE",
      );
    }

    if (
      nonce < 0n
    ) {
      throw new AppError(
        "INVALID_SIGNED_PAYLOAD_NONCE",
      );
    }

    if (
      deadline <= 0n
    ) {
      throw new AppError(
        "INVALID_SIGNED_PAYLOAD_DEADLINE",
      );
    }

    const transfer:
      SignedTokenTransfer = {
        owner:
          requiredAddress(
            payload.owner,
            "INVALID_SIGNED_PAYLOAD_OWNER",
          ),

        to:
          requiredAddress(
            payload.to,
            "INVALID_SIGNED_PAYLOAD_RECEIVER",
          ),

        /*
         * Backward compatibility with signatures stored
         * before amount and fee were included.
         */
        amount:
          normalizeDecimal(
            payload.amount ??
              job.collateral,

            "SIGNED_PAYLOAD_AMOUNT_REQUIRED",
          ),

        fee:
          normalizeDecimal(
            payload.fee ??
              "0",

            "SIGNED_PAYLOAD_FEE_REQUIRED",
          ),

        parsedAmount,

        parsedFee,

        nonce,

        deadline,

        v,

        r:
          requiredSignaturePart(
            payload.r,
            "INVALID_SIGNED_PAYLOAD_R",
          ),

        s:
          requiredSignaturePart(
            payload.s,
            "INVALID_SIGNED_PAYLOAD_S",
          ),
      };

    validateSignedTransferForJob(
      transfer,
      job,
      expectedTreasuryAddress,
    );

    return transfer;
  } catch (error) {
    if (
      error instanceof AppError
    ) {
      throw error;
    }

    throw new AppError(
      "INVALID_STORED_LIQUIDATION_SIGNATURE",
    );
  }
}


export function validateSignedTransferForJob(
  transfer:
    SignedTokenTransfer,

  job:
    ClaimedLiquidationBlockchainQueueJob,

  expectedTreasuryAddress?: string,
): void {
  const treasuryAddress = requiredAddress(
    expectedTreasuryAddress,
    "LIQUIDATION_CHAIN_TREASURY_ADDRESS_REQUIRED",
  );

  const senderAddress =
    requiredAddress(
      job.sender_wallet_address,
      "INVALID_LIQUIDATION_SENDER_WALLET_ADDRESS",
    );



  if (
    transfer.owner.toLowerCase() !==
    senderAddress.toLowerCase()
  ) {
    throw new AppError(
      "LIQUIDATION_OWNER_ADDRESS_MISMATCH",
    );
  }

  if (
    transfer.to.toLowerCase() !==
    treasuryAddress.toLowerCase()
  ) {
    throw new AppError(
      "LIQUIDATION_TREASURY_ADDRESS_MISMATCH",
    );
  }

  const transferAmount =
    normalizeDecimal(
      transfer.amount,
      "INVALID_SIGNED_TRANSFER_AMOUNT",
    );

  const collateralAmount =
    normalizeDecimal(
      job.collateral,
      "INVALID_LIQUIDATION_COLLATERAL_AMOUNT",
    );

  if (
    transferAmount !==
    collateralAmount
  ) {
    throw new AppError(
      "LIQUIDATION_COLLATERAL_AMOUNT_MISMATCH",
    );
  }

  const transferFee =
    normalizeDecimal(
      transfer.fee,
      "INVALID_SIGNED_TRANSFER_FEE",
    );

  if (
    transferFee !== "0" ||
    transfer.parsedFee !== 0n
  ) {
    throw new AppError(
      "LIQUIDATION_TRANSFER_FEE_NOT_ALLOWED",
    );
  }

  if (
    transfer.parsedAmount <= 0n
  ) {
    throw new AppError(
      "INVALID_LIQUIDATION_TRANSFER_AMOUNT",
    );
  }
}

// import {
//   AppError,
// } from "../app-error.ts";

// import type {
//   SignedTokenTransfer,
// } from "../blockchain/permit.ts";

// import type {
//   StoredSignedTokenTransfer,
// } from "../types/stored-signed-token-transfer.ts";

// import type {
//   ClaimedLiquidationBlockchainQueueJob,
// } from "../types/claimed-liquidation-blockchain-queue-job.ts";

// import {
//   treasuryAddress,
// } from "../blockchain/client.ts";


// function requiredString(
//   value: unknown,
//   errorMessage: string,
// ): string {
//   if (
//     typeof value !== "string" &&
//     typeof value !== "number" &&
//     typeof value !== "bigint"
//   ) {
//     throw new AppError(
//       errorMessage,
//     );
//   }

//   const result =
//     value
//       .toString()
//       .trim();

//   if (!result) {
//     throw new AppError(
//       errorMessage,
//     );
//   }

//   return result;
// }


// function requiredAddress(
//   value: unknown,
//   errorMessage: string,
// ): string {
//   const address =
//     requiredString(
//       value,
//       errorMessage,
//     );

//   if (
//     !/^0x[a-fA-F0-9]{40}$/.test(
//       address,
//     )
//   ) {
//     throw new AppError(
//       errorMessage,
//     );
//   }

//   return address;
// }


// function requiredSignaturePart(
//   value: unknown,
//   errorMessage: string,
// ): string {
//   const signaturePart =
//     requiredString(
//       value,
//       errorMessage,
//     );

//   if (
//     !/^0x[a-fA-F0-9]{64}$/.test(
//       signaturePart,
//     )
//   ) {
//     throw new AppError(
//       errorMessage,
//     );
//   }

//   return signaturePart;
// }


// function normalizeDecimal(
//   value: unknown,
//   errorMessage: string,
// ): string {
//   const rawValue =
//     requiredString(
//       value,
//       errorMessage,
//     );

//   if (
//     !/^\d+(\.\d+)?$/.test(
//       rawValue,
//     )
//   ) {
//     throw new AppError(
//       errorMessage,
//     );
//   }

//   const [
//     integerPartRaw,
//     fractionPartRaw = "",
//   ] = rawValue.split(".");

//   const integerPart =
//     integerPartRaw.replace(
//       /^0+(?=\d)/,
//       "",
//     );

//   const fractionPart =
//     fractionPartRaw.replace(
//       /0+$/,
//       "",
//     );

//   if (!fractionPart) {
//     return integerPart;
//   }

//   return `${integerPart}.${fractionPart}`;
// }


// function requiredBigInt(
//   value: unknown,
//   errorMessage: string,
// ): bigint {
//   const rawValue =
//     requiredString(
//       value,
//       errorMessage,
//     );

//   if (
//     !/^\d+$/.test(
//       rawValue,
//     )
//   ) {
//     throw new AppError(
//       errorMessage,
//     );
//   }

//   try {
//     return BigInt(
//       rawValue,
//     );
//   } catch {
//     throw new AppError(
//       errorMessage,
//     );
//   }
// }


// export function storeSignedTransfer(
//   signed:
//     SignedTokenTransfer,
// ): StoredSignedTokenTransfer {
//   return {
//     owner:
//       signed.owner,

//     to:
//       signed.to,

//     amount:
//       signed.amount,

//     fee:
//       signed.fee,

//     parsedAmount:
//       signed.parsedAmount
//         .toString(),

//     parsedFee:
//       signed.parsedFee
//         .toString(),

//     nonce:
//       signed.nonce
//         .toString(),

//     deadline:
//       signed.deadline
//         .toString(),

//     v:
//       signed.v,

//     r:
//       signed.r,

//     s:
//       signed.s,
//   };
// }


// export function restoreSignedTransfer(
//   payload:
//     Record<string, unknown>,

//   job:
//     ClaimedLiquidationBlockchainQueueJob,
// ): SignedTokenTransfer {
//   try {
//     const v =
//       Number(
//         payload.v,
//       );

//     if (
//       !Number.isSafeInteger(v) ||
//       (
//         v !== 27 &&
//         v !== 28
//       )
//     ) {
//       throw new AppError(
//         "INVALID_SIGNED_PAYLOAD_V",
//       );
//     }

//     const parsedAmount =
//       requiredBigInt(
//         payload.parsedAmount,
//         "SIGNED_PAYLOAD_PARSED_AMOUNT_REQUIRED",
//       );

//     const parsedFee =
//       requiredBigInt(
//         payload.parsedFee,
//         "SIGNED_PAYLOAD_PARSED_FEE_REQUIRED",
//       );

//     const nonce =
//       requiredBigInt(
//         payload.nonce,
//         "SIGNED_PAYLOAD_NONCE_REQUIRED",
//       );

//     const deadline =
//       requiredBigInt(
//         payload.deadline,
//         "SIGNED_PAYLOAD_DEADLINE_REQUIRED",
//       );

//     if (
//       parsedAmount <= 0n
//     ) {
//       throw new AppError(
//         "INVALID_SIGNED_PAYLOAD_PARSED_AMOUNT",
//       );
//     }

//     if (
//       parsedFee < 0n
//     ) {
//       throw new AppError(
//         "INVALID_SIGNED_PAYLOAD_PARSED_FEE",
//       );
//     }

//     if (
//       nonce < 0n
//     ) {
//       throw new AppError(
//         "INVALID_SIGNED_PAYLOAD_NONCE",
//       );
//     }

//     if (
//       deadline <= 0n
//     ) {
//       throw new AppError(
//         "INVALID_SIGNED_PAYLOAD_DEADLINE",
//       );
//     }

//     const transfer:
//       SignedTokenTransfer = {
//         owner:
//           requiredAddress(
//             payload.owner,
//             "INVALID_SIGNED_PAYLOAD_OWNER",
//           ),

//         to:
//           requiredAddress(
//             payload.to,
//             "INVALID_SIGNED_PAYLOAD_RECEIVER",
//           ),

//         /*
//          * Backward compatibility with signatures stored
//          * before amount and fee were included.
//          */
//         amount:
//           normalizeDecimal(
//             payload.amount ??
//               job.collateral,

//             "SIGNED_PAYLOAD_AMOUNT_REQUIRED",
//           ),

//         fee:
//           normalizeDecimal(
//             payload.fee ??
//               "0",

//             "SIGNED_PAYLOAD_FEE_REQUIRED",
//           ),

//         parsedAmount,

//         parsedFee,

//         nonce,

//         deadline,

//         v,

//         r:
//           requiredSignaturePart(
//             payload.r,
//             "INVALID_SIGNED_PAYLOAD_R",
//           ),

//         s:
//           requiredSignaturePart(
//             payload.s,
//             "INVALID_SIGNED_PAYLOAD_S",
//           ),
//       };

//     validateSignedTransferForJob(
//       transfer,
//       job,
//     );

//     return transfer;
//   } catch (error) {
//     if (
//       error instanceof AppError
//     ) {
//       throw error;
//     }

//     throw new AppError(
//       "INVALID_STORED_LIQUIDATION_SIGNATURE",
//     );
//   }
// }


// export function validateSignedTransferForJob(
//   transfer:
//     SignedTokenTransfer,

//   job:
//     ClaimedLiquidationBlockchainQueueJob,
// ): void {
//   const senderAddress =
//     requiredAddress(
//       job.sender_wallet_address,
//       "INVALID_LIQUIDATION_SENDER_WALLET_ADDRESS",
//     );



//   if (
//     transfer.owner.toLowerCase() !==
//     senderAddress.toLowerCase()
//   ) {
//     throw new AppError(
//       "LIQUIDATION_OWNER_ADDRESS_MISMATCH",
//     );
//   }

//   if (
//     transfer.to.toLowerCase() !==
//     treasuryAddress.toLowerCase()
//   ) {
//     throw new AppError(
//       "LIQUIDATION_TREASURY_ADDRESS_MISMATCH",
//     );
//   }

//   const transferAmount =
//     normalizeDecimal(
//       transfer.amount,
//       "INVALID_SIGNED_TRANSFER_AMOUNT",
//     );

//   const collateralAmount =
//     normalizeDecimal(
//       job.collateral,
//       "INVALID_LIQUIDATION_COLLATERAL_AMOUNT",
//     );

//   if (
//     transferAmount !==
//     collateralAmount
//   ) {
//     throw new AppError(
//       "LIQUIDATION_COLLATERAL_AMOUNT_MISMATCH",
//     );
//   }

//   const transferFee =
//     normalizeDecimal(
//       transfer.fee,
//       "INVALID_SIGNED_TRANSFER_FEE",
//     );

//   if (
//     transferFee !== "0" ||
//     transfer.parsedFee !== 0n
//   ) {
//     throw new AppError(
//       "LIQUIDATION_TRANSFER_FEE_NOT_ALLOWED",
//     );
//   }

//   if (
//     transfer.parsedAmount <= 0n
//   ) {
//     throw new AppError(
//       "INVALID_LIQUIDATION_TRANSFER_AMOUNT",
//     );
//   }
// }