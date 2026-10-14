
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
  createBlockchainClient,
  getTokenDecimals,
} from "./client.ts";

import type {
  BlockchainClientConfig,
} from "./client.ts";

import {
  BURNER_ROLE,
  MINTER_ROLE,
} from "./roles.ts";

/*
 * ==========================================================
 * CONFIGURATION
 * ==========================================================
 */
const MIN_GAS_BALANCE =
  parseEther("0.0001");

/*
 * ==========================================================
 * TYPES
 * ==========================================================
 */
export type GoldTokenAdjustmentType =
  | "minting"
  | "burning";

export type BlockchainAdjustmentResult = {
  tx_hash: string;
  status: "confirmed";
  block_number: number;
};

type BlockchainClient =
  ReturnType<
    typeof createBlockchainClient
  >;

/*
 * ==========================================================
 * VALIDATE ADJUSTMENT AMOUNT
 * ==========================================================
 */
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

/*
 * ==========================================================
 * PARSE TOKEN AMOUNT
 * ==========================================================
 */
async function parseTokenAmount(
  client: BlockchainClient,
  amount: string,
): Promise<bigint> {
  const normalizedAmount =
    validateAmount(amount);

  const decimals =
    await getTokenDecimals(
      client.providerContract,
    );

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

/*
 * ==========================================================
 * VALIDATE LIVE BLOCKCHAIN NETWORK
 * ==========================================================
 *
 * Ensures that the configured RPC endpoint is connected
 * to the intended blockchain.
 *
 * Also checks that the token contract is deployed.
 */
async function validateBlockchainNetwork(
  client: BlockchainClient,
): Promise<void> {
  const network =
    await client.provider.getNetwork();

  if (
    network.chainId !==
    BigInt(client.chainId)
  ) {
    throw new AppError(
      "BLOCKCHAIN_CHAIN_ID_MISMATCH",
    );
  }

  const contractCode =
    await client.provider.getCode(
      client.contractAddress,
    );

  if (
    !contractCode ||
    contractCode === "0x"
  ) {
    throw new AppError(
      "TOKEN_CONTRACT_NOT_DEPLOYED",
    );
  }
}

/*
 * ==========================================================
 * VALIDATE TRANSACTION GAS
 * ==========================================================
 */
async function validateTransactionGas(
  client: BlockchainClient,
): Promise<void> {
  const signerAddress =
    await client.treasurySigner.getAddress();

  const gasBalance =
    await client.provider.getBalance(
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

/*
 * ==========================================================
 * CHECK CONTRACT ROLE
 * ==========================================================
 */
export async function checkRole(
  client: BlockchainClient,
  role: string,
  address: string,
): Promise<boolean> {
  if (!isAddress(address)) {
    throw new AppError(
      "INVALID_BLOCKCHAIN_ADDRESS",
    );
  }

  return await client.providerContract.hasRole(
    role,
    getAddress(address),
  );
}

/*
 * ==========================================================
 * VALIDATE EXECUTION ROLE
 * ==========================================================
 *
 * AccessControl checks msg.sender.
 *
 * Therefore the role must belong to the treasury signer
 * executing the transaction.
 */
async function validateExecutionRole(
  client: BlockchainClient,
  adjustmentType:
    GoldTokenAdjustmentType,
): Promise<void> {
  const signerAddress =
    await client.treasurySigner.getAddress();

  const requiredRole =
    adjustmentType === "minting"
      ? MINTER_ROLE
      : BURNER_ROLE;

  const hasRequiredRole =
    await checkRole(
      client,
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

/*
 * ==========================================================
 * WAIT FOR TRANSACTION CONFIRMATION
 * ==========================================================
 */
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

/*
 * ==========================================================
 * MINT GOLD TOKENS
 * ==========================================================
 */
export async function mintGoldTokens(
  client: BlockchainClient,
  to: string,
  amount: string,
): Promise<BlockchainAdjustmentResult> {
  if (!isAddress(to)) {
    throw new AppError(
      "INVALID_MINT_RECEIVER_ADDRESS",
    );
  }

  /*
   * Validate signer permissions.
   */
  await validateExecutionRole(
    client,
    "minting",
  );

  /*
   * Validate gas balance.
   */
  await validateTransactionGas(
    client,
  );

  /*
   * Convert amount to token units.
   */
  const parsedAmount =
    await parseTokenAmount(
      client,
      amount,
    );

  /*
   * Execute mint.
   */
  const transaction =
    await client.treasuryContract.mint(
      getAddress(to),
      parsedAmount,
    );

  return await waitForTransaction(
    transaction,
  );
}

/*
 * ==========================================================
 * BURN GOLD TOKENS
 * ==========================================================
 */
export async function burnTokensFromTreasury(
  client: BlockchainClient,
  amount: string,
): Promise<BlockchainAdjustmentResult> {
  /*
   * Validate signer permissions.
   */
  await validateExecutionRole(
    client,
    "burning",
  );

  /*
   * Validate gas balance.
   */
  await validateTransactionGas(
    client,
  );

  /*
   * Convert amount to token units.
   */
  const parsedAmount =
    await parseTokenAmount(
      client,
      amount,
    );

  /*
   * Validate treasury token balance.
   */
  const treasuryBalance =
    await client.providerContract.balanceOf(
      client.treasuryAddress,
    );

  if (
    BigInt(treasuryBalance) <
    parsedAmount
  ) {
    throw new AppError(
      "INSUFFICIENT_TREASURY_TOKEN_BALANCE",
    );
  }

  /*
   * Execute burn.
   */
  const transaction =
    await client.treasuryContract.burn(
      client.treasuryAddress,
      parsedAmount,
    );

  return await waitForTransaction(
    transaction,
  );
}

/*
 * ==========================================================
 * EXECUTE GOLD TOKEN ADJUSTMENT
 * ==========================================================
 *
 * The blockchain configuration must be supplied from
 * prepare_my_token_adjustment_execution.
 */
export async function executeGoldTokenAdjustment(
  input: {
    adjustment_type:
      GoldTokenAdjustmentType;

    amount: string;

    blockchain:
      BlockchainClientConfig;
  },
): Promise<BlockchainAdjustmentResult> {
  /*
   * Validate adjustment type.
   */
  if (
    input.adjustment_type !== "minting" &&
    input.adjustment_type !== "burning"
  ) {
    throw new AppError(
      "INVALID_TOKEN_ADJUSTMENT_TYPE",
    );
  }

  /*
   * Create client for the selected blockchain.
   */
  const client =
    createBlockchainClient(
      input.blockchain,
    );

  /*
   * Validate live blockchain connection.
   */
  await validateBlockchainNetwork(
    client,
  );

  /*
   * Execute minting.
   */
  if (
    input.adjustment_type ===
    "minting"
  ) {
    return await mintGoldTokens(
      client,
      client.treasuryAddress,
      input.amount,
    );
  }

  /*
   * Execute burning.
   */
  return await burnTokensFromTreasury(
    client,
    input.amount,
  );
}
