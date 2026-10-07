import {
  formatEther,
  formatUnits,
} from "ethers";

import {
  AppError,
} from "../app-error.ts";

import {
  provider,
  providerContract,
} from "./client.ts";

import { ethers } from "ethers";

const ZERO_ADDRESS =
  "0x0000000000000000000000000000000000000000";

export type BlockchainWalletBalances = {
  token_balance: string;
  gas_balance: string;
};

export async function getBlockchainWalletBalances(
  address: string,
): Promise<BlockchainWalletBalances> {
  if (
    !address ||
    address === "0x00" ||
    address.toLowerCase() ===
      ZERO_ADDRESS
  ) {
    return {
      token_balance: "0",
      gas_balance: "0",
    };
  }

  const [
    tokenRaw,
    tokenDecimals,
    gasRaw,
  ] = await Promise.all([
    providerContract.balanceOf(address),
    providerContract.decimals(),
    provider.getBalance(address),
  ]);

  const decimals =
    Number(tokenDecimals);

  if (
    !Number.isSafeInteger(decimals) ||
    decimals < 0
  ) {
    throw new AppError(
      "INVALID_TOKEN_DECIMALS",
    );
  }

  return {
    token_balance:
      formatUnits(
        tokenRaw,
        decimals,
      ),
    gas_balance:
      formatEther(gasRaw),
  };
}

export async function getRelayerGasBalance():
  Promise<string> {
      const relayerAddress =  getRelayerAddress();
  const balances =
    await getBlockchainWalletBalances(
      relayerAddress,
    );

  return balances.gas_balance;
}

export async function getTotalSupply(): Promise<{
  token_balance: string;
}> {
  const totalSupply = await providerContract.totalSupply();
  const tokenDecimals = await providerContract.decimals();
  const decimals = tokenDecimals.toString();
  return {
    token_balance:
      formatTokenAmount(totalSupply, decimals),
  };
}

function formatTokenAmount(
  amount: bigint,
  decimals: string,
): string {
  
  return ethers.formatUnits(
    amount,
    Number(decimals),
  );
}

function getRelayerAddress(): string {
  const address =
    Deno.env.get("RELAYER_ADDRESS");

  if (!address) {
    throw new Error(
      "RELAYER_ADDRESS_MISSING",
    );
  }

  if (!ethers.isAddress(address)) {
    throw new Error(
      "INVALID_RELAYER_ADDRESS",
    );
  }

  return ethers.getAddress(address);
}