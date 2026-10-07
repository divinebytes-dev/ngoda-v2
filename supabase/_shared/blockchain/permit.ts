import {
  getAddress,
  isAddress,
  parseUnits,
  Signature,
  Wallet,
} from "ethers";

import {
  AppError,
} from "../app-error.ts";

import {
  blockchainConfig,
  getTokenDecimals,
  permitDomain,
  permitTypes,
  providerContract,
} from "./client.ts";

import {
  deriveWallet,
  getWalletMnemonic,
} from "./wallet.ts";


export type SignedTokenTransfer = {
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


export function buildPermitValue({
  owner,
  amount,
  nonce,
  deadline,
}: {
  owner: string;
  amount: bigint;
  nonce: bigint;
  deadline: bigint;
}) {
  return {
    owner,

    spender:
      blockchainConfig.contractAddress,

    value:
      amount,

    nonce,
    deadline,
  };
}


export async function signTransfer({
  fromIndex,
  expectedOwner,
  to,
  amount,
  fee,
}: {
  fromIndex: number;
  expectedOwner: string;
  to: string;
  amount: string;
  fee: string;
}): Promise<SignedTokenTransfer> {
  if (
    !Number.isSafeInteger(
      fromIndex,
    ) ||
    fromIndex < 0
  ) {
    throw new AppError(
      "INVALID_WALLET_INDEX",
    );
  }

  if (
    !isAddress(
      expectedOwner,
    )
  ) {
    throw new AppError(
      "INVALID_OWNER_ADDRESS",
    );
  }

  if (!isAddress(to)) {
    throw new AppError(
      "INVALID_RECEIVER_ADDRESS",
    );
  }

  const normalizedOwner =
    getAddress(
      expectedOwner,
    );

  const normalizedReceiver =
    getAddress(to);

  const mnemonic =
    getWalletMnemonic();

  const derivedWallet =
    deriveWallet(
      mnemonic,
      fromIndex,
    );

  const derivedAddress =
    getAddress(
      derivedWallet.address,
    );

  /*
   * Prevent signing from a derived wallet index that does
   * not belong to the expected database wallet address.
   */
  if (
    derivedAddress !==
    normalizedOwner
  ) {
    throw new AppError(
      "DERIVED_WALLET_OWNER_MISMATCH",
    );
  }

  const tokenDecimals =
    await getTokenDecimals();

  let parsedAmount: bigint;
  let parsedFee: bigint;

  try {
    parsedAmount =
      parseUnits(
        amount,
        tokenDecimals,
      );

    parsedFee =
      parseUnits(
        fee,
        tokenDecimals,
      );
  } catch {
    throw new AppError(
      "INVALID_TOKEN_AMOUNT",
    );
  }

  if (parsedAmount <= 0n) {
    throw new AppError(
      "INVALID_TRANSFER_AMOUNT",
    );
  }

  if (parsedFee < 0n) {
    throw new AppError(
      "INVALID_TRANSFER_FEE",
    );
  }

  const total =
    parsedAmount +
    parsedFee;

  const nonceRaw =
    await providerContract.nonces(
      derivedAddress,
    );

  const nonce =
    BigInt(
      nonceRaw.toString(),
    );

  const deadline =
    BigInt(
      Math.floor(
        Date.now() / 1000,
      ) + 600,
    );

  const permitValue =
    buildPermitValue({
      owner:
        derivedAddress,

      amount:
        total,

      nonce,
      deadline,
    });

  const wallet =
    new Wallet(
      derivedWallet.privateKey,
    );

  const signature =
    await wallet.signTypedData(
      permitDomain,
      permitTypes,
      permitValue,
    );

  const parsedSignature =
    Signature.from(
      signature,
    );

  return {
    owner:
      derivedAddress,

    to:
      normalizedReceiver,

    amount:
      amount,

    fee:
      fee,

    parsedAmount,
    parsedFee,

    nonce,
    deadline,

    v:
      parsedSignature.v,

    r:
      parsedSignature.r,

    s:
      parsedSignature.s,
  };
}
