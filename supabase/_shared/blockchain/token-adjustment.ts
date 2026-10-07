import {
  ContractTransactionResponse,
  getAddress,
  isAddress,
  parseEther,
  parseUnits,
} from "ethers";

import {
  AppError,
} from "../app-error.ts";

import {
  blockchainConfig,
  getTokenDecimals,
  minterContract,
  minterSigner,
  provider,
  providerContract,
} from "./client.ts";

import {
  BURNER_ROLE,
  MINTER_ROLE,
} from "./roles.ts";


const MIN_GAS_BALANCE =
  parseEther("0.0001");


export type GoldTokenAdjustmentType =
  | "minting"
  | "burning";


export type BlockchainAdjustmentResult = {
  tx_hash: string;
  status: "confirmed";
  block_number: number;
};


function validateAmount(
  amount: string,
): string {
  const normalizedAmount =
    amount.trim();

  if (!normalizedAmount) {
    throw new AppError(
      "INVALID_TOKEN_ADJUSTMENT_AMOUNT",
    );
  }

  return normalizedAmount;
}


async function parseTokenAmount(
  amount: string,
): Promise<bigint> {
  const normalizedAmount =
    validateAmount(amount);

  const decimals =
    await getTokenDecimals();

  let parsedAmount: bigint;

  try {
    parsedAmount =
      parseUnits(
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


async function validateTransactionGas():
  Promise<void> {
  const signerAddress =
    await minterSigner.getAddress();

  const gasBalance =
    await provider.getBalance(
      signerAddress,
    );

  if (
    gasBalance <
    MIN_GAS_BALANCE
  ) {
    throw new AppError(
      "TOP_UP_GAS",
    );
  }
}


async function waitForTransaction(
  transaction:
    ContractTransactionResponse,
): Promise<BlockchainAdjustmentResult> {
  if (!transaction.hash) {
    throw new AppError(
      "BLOCKCHAIN_TX_FAILED",
    );
  }

  const receipt =
    await transaction.wait();

  if (
    !receipt ||
    receipt.status !== 1
  ) {
    throw new AppError(
      "BLOCKCHAIN_TX_FAILED",
    );
  }

  return {
    tx_hash:
      transaction.hash,

    status:
      "confirmed",

    block_number:
      receipt.blockNumber,
  };
}


export async function checkRole(
  role: string,
  address: string,
): Promise<boolean> {
  if (!isAddress(address)) {
    throw new AppError(
      "INVALID_BLOCKCHAIN_ADDRESS",
    );
  }

  return await providerContract.hasRole(
    role,
    getAddress(address),
  );
}


async function validateExecutionRole(
  adjustmentType:
    GoldTokenAdjustmentType,
): Promise<void> {
  /*
   * AccessControl checks msg.sender.
   *
   * Therefore the role must belong to the minter signer
   * executing the contract call, not merely to the token
   * recipient.
   */
  const signerAddress =
    await minterSigner.getAddress();

  const requiredRole =
    adjustmentType === "minting"
      ? MINTER_ROLE
      : BURNER_ROLE;

  const hasRequiredRole =
    await checkRole(
      requiredRole,
      signerAddress,
    );

  if (!hasRequiredRole) {
    throw new AppError(
      adjustmentType === "minting"
        ? "NO_MINTER_ROLE"
        : "NO_BURNER_ROLE",
    );
  }
}


export async function mintGoldTokens(
  to: string,
  amount: string,
): Promise<BlockchainAdjustmentResult> {
  if (!isAddress(to)) {
    throw new AppError(
      "INVALID_MINT_RECEIVER_ADDRESS",
    );
  }

  await validateExecutionRole(
    "minting",
  );

  await validateTransactionGas();

  const parsedAmount =
    await parseTokenAmount(
      amount,
    );

  const transaction =
    await minterContract.mint(
      getAddress(to),
      parsedAmount,
    );

  return await waitForTransaction(
    transaction,
  );
}


export async function burnTokensFromTreasury(
  amount: string,
): Promise<BlockchainAdjustmentResult> {
  const treasuryAddress =
    blockchainConfig.treasuryAddress;

  await validateExecutionRole(
    "burning",
  );

  await validateTransactionGas();

  const parsedAmount =
    await parseTokenAmount(
      amount,
    );

  /*
   * Verify the treasury has enough Gold before submitting
   * the irreversible burn transaction.
   */
  const treasuryBalance =
    await providerContract.balanceOf(
      treasuryAddress,
    );

  if (
    BigInt(treasuryBalance) <
    parsedAmount
  ) {
    throw new AppError(
      "INSUFFICIENT_TREASURY_TOKEN_BALANCE",
    );
  }

  const transaction =
    await minterContract.burn(
      treasuryAddress,
      parsedAmount,
    );

  return await waitForTransaction(
    transaction,
  );
}


export async function executeGoldTokenAdjustment(
  input: {
    adjustment_type:
      GoldTokenAdjustmentType;

    amount: string;
  },
): Promise<BlockchainAdjustmentResult> {
  if (
    input.adjustment_type ===
    "minting"
  ) {
    return await mintGoldTokens(
      blockchainConfig.treasuryAddress,
      input.amount,
    );
  }

  if (
    input.adjustment_type ===
    "burning"
  ) {
    return await burnTokensFromTreasury(
      input.amount,
    );
  }

  throw new AppError(
    "INVALID_TOKEN_ADJUSTMENT_TYPE",
  );
}