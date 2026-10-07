import {
  ethers,
} from "ethers";

import {
  AppError,
} from "../app-error.ts";

import {
  blockchainConfig,
  minterContract,
  providerContract,
} from "./client.ts";

export type TokenAdjustmentType =
  | "minting"
  | "burning";

export type TokenAdjustmentResult = {
  tx_hash: string;
  block_number: number;
  status: "confirmed";
};

function parseTokenAmount(
  amount: string,
  decimals: number,
): bigint {
  const normalizedAmount =
    amount.trim();

  if (!normalizedAmount) {
    throw new AppError(
      "INVALID_TOKEN_ADJUSTMENT_AMOUNT",
    );
  }

  let parsedAmount: bigint;

  try {
    parsedAmount =
      ethers.parseUnits(
        normalizedAmount,
        decimals,
      );
  } catch {
    throw new AppError(
      "INVALID_TOKEN_ADJUSTMENT_AMOUNT",
    );
  }

  if (parsedAmount <= 0n) {
    throw new AppError(
      "INVALID_TOKEN_ADJUSTMENT_AMOUNT",
    );
  }

  return parsedAmount;
}

async function waitForTransaction(
  transaction:
    ethers.ContractTransactionResponse,
): Promise<TokenAdjustmentResult> {
  if (!transaction.hash) {
    throw new AppError(
      "BLOCKCHAIN_TRANSACTION_FAILED",
    );
  }

  const receipt =
    await transaction.wait();

  if (
    !receipt ||
    receipt.status !== 1
  ) {
    throw new AppError(
      "BLOCKCHAIN_TRANSACTION_FAILED",
    );
  }

  return {
    tx_hash:
      transaction.hash,

    block_number:
      receipt.blockNumber,

    status:
      "confirmed",
  };
}

async function getTokenDecimals():
  Promise<number> {
  const rawDecimals =
    await providerContract.decimals();

  const decimals =
    Number(rawDecimals);

  if (
    !Number.isSafeInteger(decimals) ||
    decimals < 0
  ) {
    throw new AppError(
      "INVALID_TOKEN_DECIMALS",
    );
  }

  return decimals;
}

export async function checkContractRole(
  role: string,
  address: string,
): Promise<boolean> {
  if (!ethers.isAddress(address)) {
    throw new AppError(
      "INVALID_BLOCKCHAIN_ADDRESS",
    );
  }

  return await providerContract.hasRole(
    role,
    ethers.getAddress(address),
  );
}

async function getAdjustmentRole(
  adjustmentType:
    TokenAdjustmentType,
): Promise<string> {
  if (adjustmentType === "minting") {
    return await providerContract
      .MINTER_ROLE();
  }

  return await providerContract
    .BURNER_ROLE();
}

export async function mintGoldTokens(
  treasuryAddress: string,
  amount: string,
): Promise<TokenAdjustmentResult> {
  if (
    !ethers.isAddress(
      treasuryAddress,
    )
  ) {
    throw new AppError(
      "INVALID_TREASURY_ADDRESS",
    );
  }

  const decimals =
    await getTokenDecimals();

  const parsedAmount =
    parseTokenAmount(
      amount,
      decimals,
    );

  const transaction =
    await minterContract.mint(
      ethers.getAddress(
        treasuryAddress,
      ),
      parsedAmount,
    );

  return await waitForTransaction(
    transaction,
  );
}

export async function burnGoldTokens(
  treasuryAddress: string,
  amount: string,
): Promise<TokenAdjustmentResult> {
  if (
    !ethers.isAddress(
      treasuryAddress,
    )
  ) {
    throw new AppError(
      "INVALID_TREASURY_ADDRESS",
    );
  }

  const decimals =
    await getTokenDecimals();

  const parsedAmount =
    parseTokenAmount(
      amount,
      decimals,
    );

  const treasuryBalanceRaw =
    await providerContract.balanceOf(
      treasuryAddress,
    );

  if (
    BigInt(treasuryBalanceRaw) <
    parsedAmount
  ) {
    throw new AppError(
      "INSUFFICIENT_TREASURY_TOKEN_BALANCE",
    );
  }

  const transaction =
    await minterContract.burn(
      ethers.getAddress(
        treasuryAddress,
      ),
      parsedAmount,
    );

  return await waitForTransaction(
    transaction,
  );
}

export async function executeGoldTokenAdjustment(
  input: {
    adjustment_type:
      TokenAdjustmentType;

    treasury_address?: string;

    amount: string;
  },
): Promise<TokenAdjustmentResult> {
  const treasuryAddress =
    input.treasury_address ??
    blockchainConfig.treasuryAddress;

  if (
    input.adjustment_type !==
      "minting" &&
    input.adjustment_type !==
      "burning"
  ) {
    throw new AppError(
      "INVALID_TOKEN_ADJUSTMENT_TYPE",
    );
  }

  /*
   * Preserve the existing contract-role model: the treasury
   * address must have the applicable role.
   */
  const requiredRole =
    await getAdjustmentRole(
      input.adjustment_type,
    );

  const hasRequiredRole =
    await checkContractRole(
      requiredRole,
      treasuryAddress,
    );

  if (!hasRequiredRole) {
    throw new AppError(
      input.adjustment_type ===
        "minting"
        ? "NO_MINTER_ROLE"
        : "NO_BURNER_ROLE",
    );
  }

  if (
    input.adjustment_type ===
    "minting"
  ) {
    return await mintGoldTokens(
      treasuryAddress,
      input.amount,
    );
  }

  return await burnGoldTokens(
    treasuryAddress,
    input.amount,
  );
}