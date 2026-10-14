
import {
  Contract,
  getAddress,
  isAddress,
  JsonRpcProvider,
  Wallet,
} from "ethers";

import type {
  TypedDataDomain,
  TypedDataField,
} from "ethers";

import {
  AppError,
} from "../app-error.ts";

import {
  deriveWallet,
} from "./wallet.ts";

import type {
  SupportedBlockchainConfig,
} from "../types/supported_blockchain_config.ts";

/*
 * ==========================================================
 * TOKEN CONTRACT ABI
 * ==========================================================
 */
const TOKEN_ABI = [
  /*
   * Token metadata and balances.
   */
  "function name() view returns (string)",
  "function balanceOf(address account) view returns (uint256)",
  "function decimals() view returns (uint8)",
  "function totalSupply() view returns (uint256)",
  "function nonces(address owner) view returns (uint256)",

  /*
   * Access control.
   */
  "function hasRole(bytes32 role, address account) view returns (bool)",
  "function grantRole(bytes32 role, address account)",

  /*
   * Token supply adjustment.
   */
  "function mint(address to, uint256 amount)",
  "function burn(address from, uint256 amount)",

  /*
   * Relayed token transfer.
   */
  `function transferWithPermitAndFee(
    address owner,
    address to,
    address feeRecipient,
    uint256 amount,
    uint256 fee,
    uint256 deadline,
    uint8 v,
    bytes32 r,
    bytes32 s
  )`,
];

/*
 * ==========================================================
 * BLOCKCHAIN CONFIGURATION
 * ==========================================================
 *
 * The network-specific values are loaded from Supabase.
 *
 * The same treasury wallet is used across supported
 * EVM blockchains.
 */
export type BlockchainClientConfig =
  SupportedBlockchainConfig & {
    treasury_wallet_address: string;
  };

/*
 * ==========================================================
 * ENVIRONMENT HELPERS
 * ==========================================================
 */
function getRequiredEnvironment(
  name: string,
): string {
  const value =
    Deno.env.get(name)?.trim();

  if (!value) {
    throw new AppError(
      `ENV_${name}_MISSING`,
    );
  }

  return value;
}

function getRequiredWalletIndex(
  name: string,
): number {
  const rawValue =
    getRequiredEnvironment(name);

  const walletIndex =
    Number(rawValue);

  if (
    !Number.isSafeInteger(walletIndex) ||
    walletIndex < 0
  ) {
    throw new AppError(
      `INVALID_${name}`,
    );
  }

  return walletIndex;
}

function validatePrivateKey(
  privateKey: string,
  errorCode: string,
): string {
  if (
    !/^0x[0-9a-fA-F]{64}$/.test(
      privateKey,
    )
  ) {
    throw new AppError(
      errorCode,
    );
  }

  return privateKey;
}

/*
 * ==========================================================
 * DERIVE PRIVILEGED WALLETS
 * ==========================================================
 *
 * These values remain server-side.
 *
 * Blockchain network configuration is no longer read
 * from environment variables.
 */
const masterMnemonic =
  getRequiredEnvironment(
    "MASTER_MNEMONIC",
  );

const treasuryWalletIndex =
  getRequiredWalletIndex(
    "MINTER_INDEX",
  );

const adminWalletIndex =
  getRequiredWalletIndex(
    "ADMIN_INDEX",
  );

/*
 * Treasury wallet.
 */
const derivedTreasuryWallet =
  deriveWallet(
    masterMnemonic,
    treasuryWalletIndex,
  );

const treasuryPrivateKey =
  validatePrivateKey(
    derivedTreasuryWallet.privateKey,
    "INVALID_TREASURY_PRIVATE_KEY",
  );

export const treasuryAddress =
  getAddress(
    derivedTreasuryWallet.address,
  );

/*
 * Administrator wallet.
 */
const derivedAdminWallet =
  deriveWallet(
    masterMnemonic,
    adminWalletIndex,
  );

const adminPrivateKey =
  validatePrivateKey(
    derivedAdminWallet.privateKey,
    "INVALID_ADMIN_PRIVATE_KEY",
  );

export const adminAddress =
  getAddress(
    derivedAdminWallet.address,
  );

/*
 * Relayer wallet.
 *
 * The relayer retains its existing private key.
 */
const relayerPrivateKey =
  validatePrivateKey(
    getRequiredEnvironment(
      "RELAYER_PK",
    ),
    "INVALID_RELAYER_PRIVATE_KEY",
  );

export const relayerAddress =
  getAddress(
    new Wallet(
      relayerPrivateKey,
    ).address,
  );

/*
 * Optional relayer identity verification.
 */
const configuredRelayerAddress =
  Deno.env
    .get("RELAYER_ADDRESS")
    ?.trim();

if (configuredRelayerAddress) {
  if (
    !isAddress(
      configuredRelayerAddress,
    )
  ) {
    throw new AppError(
      "INVALID_RELAYER_ADDRESS",
    );
  }

  if (
    getAddress(
      configuredRelayerAddress,
    ) !== relayerAddress
  ) {
    throw new AppError(
      "RELAYER_ADDRESS_PRIVATE_KEY_MISMATCH",
    );
  }
}

/*
 * ==========================================================
 * VALIDATE BLOCKCHAIN CONFIGURATION
 * ==========================================================
 */
function validateBlockchainConfig(
  blockchain: SupportedBlockchainConfig,
): void {
  if (
    !Number.isSafeInteger(
      blockchain.chain_id,
    ) ||
    blockchain.chain_id <= 0
  ) {
    throw new AppError(
      "INVALID_BLOCKCHAIN_CHAIN_ID",
    );
  }

  const rpcUrl =
    blockchain.rpc_url?.trim();

  if (!rpcUrl) {
    throw new AppError(
      "BLOCKCHAIN_RPC_URL_MISSING",
    );
  }

  let parsedUrl: URL;

  try {
    parsedUrl =
      new URL(rpcUrl);
  } catch {
    throw new AppError(
      "INVALID_BLOCKCHAIN_RPC_URL",
    );
  }

  if (
    parsedUrl.protocol !== "https:" &&
    parsedUrl.protocol !== "http:"
  ) {
    throw new AppError(
      "INVALID_BLOCKCHAIN_RPC_URL",
    );
  }

  if (
    !isAddress(
      blockchain.contract_address,
    )
  ) {
    throw new AppError(
      "INVALID_TOKEN_CONTRACT_ADDRESS",
    );
  }
}

/*
 * ==========================================================
 * CREATE BLOCKCHAIN CLIENT
 * ==========================================================
 *
 * Creates the provider and all contract connections
 * for the selected EVM blockchain.
 *
 * The same derived treasury wallet is connected to
 * the selected network.
 */
export function createBlockchainClient(
  blockchain: BlockchainClientConfig,
) {
  /*
   * Validate network configuration.
   */
  validateBlockchainConfig(
    blockchain,
  );

  /*
   * Validate treasury address.
   */
  if (
    !isAddress(
      blockchain.treasury_wallet_address,
    )
  ) {
    throw new AppError(
      "INVALID_TREASURY_ADDRESS",
    );
  }

  const configuredTreasuryAddress =
    getAddress(
      blockchain.treasury_wallet_address,
    );

  /*
   * The database-configured treasury wallet must
   * match the existing derived treasury wallet.
   */
  if (
    configuredTreasuryAddress !==
    treasuryAddress
  ) {
    throw new AppError(
      "TREASURY_DERIVED_ADDRESS_MISMATCH",
    );
  }

  /*
   * Network provider.
   */
  const provider =
    new JsonRpcProvider(
      blockchain.rpc_url.trim(),
      blockchain.chain_id,
    );

  /*
   * Read-only contract.
   */
  const providerContract =
    new Contract(
      getAddress(
        blockchain.contract_address,
      ),
      TOKEN_ABI,
      provider,
    );

  /*
   * Treasury signer and contract.
   */
  const treasurySigner =
    new Wallet(
      treasuryPrivateKey,
      provider,
    );

  if (
    getAddress(
      treasurySigner.address,
    ) !== configuredTreasuryAddress
  ) {
    throw new AppError(
      "TREASURY_SIGNER_ADDRESS_MISMATCH",
    );
  }

  const treasuryContract =
    new Contract(
      getAddress(
        blockchain.contract_address,
      ),
      TOKEN_ABI,
      treasurySigner,
    );

  /*
   * Relayer signer and contract.
   */
  const relayerSigner =
    new Wallet(
      relayerPrivateKey,
      provider,
    );

  const relayerContract =
    new Contract(
      getAddress(
        blockchain.contract_address,
      ),
      TOKEN_ABI,
      relayerSigner,
    );

  /*
   * Administrator signer and contract.
   */
  const adminSigner =
    new Wallet(
      adminPrivateKey,
      provider,
    );

  const adminContract =
    new Contract(
      getAddress(
        blockchain.contract_address,
      ),
      TOKEN_ABI,
      adminSigner,
    );

  return {
    blockchainCode:
      blockchain.code,

    chainId:
      blockchain.chain_id,

    contractAddress:
      getAddress(
        blockchain.contract_address,
      ),

    treasuryAddress:
      configuredTreasuryAddress,

    adminAddress,

    relayerAddress,

    provider,

    providerContract,

    treasurySigner,

    treasuryContract,

    relayerSigner,

    relayerContract,

    adminSigner,

    adminContract,
  };
}

/*
 * ==========================================================
 * CREATE READ-ONLY BLOCKCHAIN CLIENT
 * ==========================================================
 *
 * Used by operations that do not require private keys.
 *
 * Examples:
 * - Treasury dashboard
 * - Token balance
 * - Total supply
 * - Token metadata
 */
export function createBlockchainReadClient(
  blockchain: SupportedBlockchainConfig,
) {
  validateBlockchainConfig(
    blockchain,
  );

  const provider =
    new JsonRpcProvider(
      blockchain.rpc_url.trim(),
      blockchain.chain_id,
    );

  const contract =
    new Contract(
      getAddress(
        blockchain.contract_address,
      ),
      TOKEN_ABI,
      provider,
    );

  return {
    provider,
    contract,
  };
}

/*
 * ==========================================================
 * GET TOKEN DECIMALS
 * ==========================================================
 */
export async function getTokenDecimals(
  contract: Contract,
): Promise<number> {
  const rawDecimals =
    await contract.decimals();

  const decimals =
    Number(rawDecimals);

  if (
    !Number.isSafeInteger(
      decimals,
    ) ||
    decimals < 0
  ) {
    throw new AppError(
      "INVALID_TOKEN_DECIMALS",
    );
  }

  return decimals;
}

/*
 * ==========================================================
 * CREATE PERMIT DOMAIN
 * ==========================================================
 *
 * EIP-712 domains are blockchain-specific.
 */
export function createPermitDomain(
  blockchain: SupportedBlockchainConfig,
): TypedDataDomain {
  validateBlockchainConfig(
    blockchain,
  );

  return {
    name:
      "Golden Liberty Finance",

    version:
      "1",

    chainId:
      blockchain.chain_id,

    verifyingContract:
      getAddress(
        blockchain.contract_address,
      ),
  };
}

/*
 * ==========================================================
 * PERMIT TYPES
 * ==========================================================
 *
 * The permit structure is identical across networks.
 */
export const permitTypes:
  Record<string, TypedDataField[]> = {
    Permit: [
      {
        name: "owner",
        type: "address",
      },
      {
        name: "spender",
        type: "address",
      },
      {
        name: "value",
        type: "uint256",
      },
      {
        name: "nonce",
        type: "uint256",
      },
      {
        name: "deadline",
        type: "uint256",
      },
    ],
  };
