import {
  HDNodeWallet,
} from "ethers";

import {
  AppError,
} from "../app-error.ts";


export function getWalletMnemonic():
  string {
  /*
   * Support the existing mnemonic secret without
   * forcing an immediate secret rename.
   */
  const mnemonic =
    Deno.env
      .get("MASTER_MNEMONIC")
      ?.trim() ??
    Deno.env
      .get("BLOCKCHAIN_MNEMONIC")
      ?.trim() ??
    Deno.env
      .get("MNEMONIC")
      ?.trim();

  if (!mnemonic) {
    throw new AppError(
      "ENV_WALLET_MNEMONIC_MISSING",
    );
  }

  return mnemonic;
}


export function deriveWallet(
  mnemonic: string,
  walletIndex: number,
): {
  address: string;
  privateKey: string;
} {
  if (
    !Number.isSafeInteger(walletIndex) ||
    walletIndex < 0
  ) {
    throw new AppError(
      "INVALID_WALLET_INDEX",
    );
  }

  const normalizedMnemonic =
    mnemonic.trim();

  if (!normalizedMnemonic) {
    throw new AppError(
      "WALLET_MNEMONIC_MISSING",
    );
  }

  try {
    const root =
      HDNodeWallet.fromPhrase(
        normalizedMnemonic,
        undefined,
        "m/44'/60'/0'/0",
      );

    const wallet =
      root.deriveChild(
        walletIndex,
      );

    return {
      address:
        wallet.address,

      privateKey:
        wallet.privateKey,
    };
  } catch {
    throw new AppError(
      "INVALID_WALLET_MNEMONIC",
    );
  }
}