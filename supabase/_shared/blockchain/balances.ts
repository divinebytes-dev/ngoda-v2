import {
  formatEther,
  formatUnits,
  ethers,
} from "ethers";

import {
  AppError,
} from "../app-error.ts";

import {
  createBlockchainReadClient,
} from "./client.ts";

import type {
  SupportedBlockchainConfig,
} from "../types/supported_blockchain_config.ts";

import type {
  SupportedBlockchainBalance,
} from "../types/supported_blockchain_balance.ts";

const ZERO_ADDRESS =
  "0x0000000000000000000000000000000000000000";

export type BlockchainWalletBalances = {
  token_balance: string;
  gas_balance: string;
};

export type BlockchainConfig = {
  code: string;
  chain_id: number;
  rpc_url: string;
  contract_address: string;
  native_currency_code: string;
};

export async function getBlockchainWalletBalances(
  blockchain: SupportedBlockchainConfig,
  address: string,
): Promise<BlockchainWalletBalances> {
  if (
    !address ||
    address === "0x00" ||
    address.toLowerCase() === ZERO_ADDRESS
  ) {
    return {
      token_balance: "0",
      gas_balance: "0",
    };
  }

  if (!ethers.isAddress(address)) {
    throw new AppError(
      "INVALID_BLOCKCHAIN_WALLET_ADDRESS",
    );
  }

  const {
    provider,
    contract,
  } = createBlockchainReadClient(blockchain);

  const [
    tokenRaw,
    tokenDecimals,
    gasRaw,
  ] = await Promise.all([
    contract.balanceOf(address),
    contract.decimals(),
    provider.getBalance(address),
  ]);

  const decimals = Number(tokenDecimals);

  if (
    !Number.isSafeInteger(decimals) ||
    decimals < 0 ||
    decimals > 255
  ) {
    throw new AppError(
      "INVALID_TOKEN_DECIMALS",
    );
  }

  return {
    token_balance: formatUnits(
      tokenRaw,
      decimals,
    ),
    gas_balance: formatEther(gasRaw),
  };
}

export async function getRelayerGasBalance(
  blockchain: SupportedBlockchainConfig,
): Promise<string> {
  const address = getRelayerAddress();

  const {
    provider,
  } = createBlockchainReadClient(blockchain);

  const gasBalance =
    await provider.getBalance(address);

  return formatEther(gasBalance);
}

export async function getTotalSupply(
  blockchain: SupportedBlockchainConfig,
): Promise<{
  token_balance: string;
}> {
  const {
    contract,
  } = createBlockchainReadClient(blockchain);

  const [
    totalSupply,
    tokenDecimals,
  ] = await Promise.all([
    contract.totalSupply(),
    contract.decimals(),
  ]);

  return {
    token_balance: formatTokenAmount(
      totalSupply,
      Number(tokenDecimals),
    ),
  };
}

function formatTokenAmount(
  amount: bigint,
  decimals: number,
): string {
  if (
    !Number.isSafeInteger(decimals) ||
    decimals < 0 ||
    decimals > 255
  ) {
    throw new AppError(
      "INVALID_TOKEN_DECIMALS",
    );
  }

  return ethers.formatUnits(
    amount,
    decimals,
  );
}

function getRelayerAddress(): string {
  const address =
    Deno.env.get("RELAYER_ADDRESS");

  if (!address) {
    throw new AppError(
      "RELAYER_ADDRESS_MISSING",
    );
  }

  if (!ethers.isAddress(address)) {
    throw new AppError(
      "INVALID_RELAYER_ADDRESS",
    );
  }

  return ethers.getAddress(address);
}

export async function getSupportedBlockchainBalance(
  blockchain: SupportedBlockchainConfig,
  walletAddress: string,
): Promise<SupportedBlockchainBalance> {
  if (!ethers.isAddress(walletAddress)) {
    throw new AppError(
      "INVALID_BLOCKCHAIN_WALLET_ADDRESS",
    );
  }

  const {
    provider,
    contract,
  } = createBlockchainReadClient(blockchain);

  const [
    totalSupply,
    tokenBalance,
    decimalsRaw,
    gasBalance,
  ] = await Promise.all([
    contract.totalSupply(),
    contract.balanceOf(walletAddress),
    contract.decimals(),
    provider.getBalance(walletAddress),
  ]);

  const decimals = Number(decimalsRaw);

  if (
    !Number.isSafeInteger(decimals) ||
    decimals < 0 ||
    decimals > 255
  ) {
    throw new AppError(
      "INVALID_TOKEN_DECIMALS",
    );
  }

  return {
    blockchain_code: blockchain.code,
    chain_id: blockchain.chain_id,
    token_supply: formatUnits(
      totalSupply,
      decimals,
    ),
    balance: formatUnits(
      tokenBalance,
      decimals,
    ),
    gas_balance: formatEther(
      gasBalance,
    ),
    native_currency_code:
      blockchain.native_currency_code,
  };
}