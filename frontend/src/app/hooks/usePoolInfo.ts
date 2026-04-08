"use client";

import { useReadContract, useReadContracts } from "wagmi";
import { CONTRACTS, ALM_ABI, POOL_ABI, ERC20_ABI } from "../lib/contracts";
import { formatUnits } from "viem";

// Spot price from ALM (USDC per 1 base, scaled per `rawPxScale` on-chain)
export function useSpotPrice() {
  const { data, isLoading, error, refetch } = useReadContract({
    address: CONTRACTS.ALM,
    abi: ALM_ABI,
    functionName: "getSpotPriceUSDCperPURR",
  });

  const rawPrice = data ? BigInt(data) : BigInt(0);

  return {
    rawPrice,
    formattedPrice: rawPrice ? Number(rawPrice) / 1e8 : 0,
    isLoading,
    error,
    refetch,
  };
}

// Hook to get pool info
export function usePoolInfo() {
  const { data, isLoading, error } = useReadContracts({
    contracts: [
      {
        address: CONTRACTS.POOL,
        abi: POOL_ABI,
        functionName: "token0",
      },
      {
        address: CONTRACTS.POOL,
        abi: POOL_ABI,
        functionName: "token1",
      },
      {
        address: CONTRACTS.POOL,
        abi: POOL_ABI,
        functionName: "alm",
      },
      {
        address: CONTRACTS.POOL,
        abi: POOL_ABI,
        functionName: "defaultSwapFeeBips",
      },
    ],
  });

  return {
    token0: data?.[0]?.result as `0x${string}` | undefined,
    token1: data?.[1]?.result as `0x${string}` | undefined,
    alm: data?.[2]?.result as `0x${string}` | undefined,
    feeBips: data?.[3]?.result ? Number(data[3].result) : 0,
    isLoading,
    error,
  };
}

// Hook to get token balances for a user
export function useTokenBalances(userAddress: `0x${string}` | undefined) {
  const { data, isLoading, error, refetch } = useReadContracts({
    contracts: [
      {
        address: CONTRACTS.PURR,
        abi: ERC20_ABI,
        functionName: "balanceOf",
        args: userAddress ? [userAddress] : undefined,
      },
      {
        address: CONTRACTS.USDC,
        abi: ERC20_ABI,
        functionName: "balanceOf",
        args: userAddress ? [userAddress] : undefined,
      },
    ],
    query: {
      enabled: !!userAddress,
    },
  });

  return {
    purrBalance: data?.[0]?.result as bigint | undefined,
    usdcBalance: data?.[1]?.result as bigint | undefined,
    formattedPurr: data?.[0]?.result
      ? formatUnits(data[0].result as bigint, 5)
      : "0",
    formattedUsdc: data?.[1]?.result
      ? formatUnits(data[1].result as bigint, 6)
      : "0",
    isLoading,
    error,
    refetch,
  };
}

// Hook to get token allowance
export function useTokenAllowance(
  tokenAddress: `0x${string}`,
  ownerAddress: `0x${string}` | undefined,
  spenderAddress: `0x${string}`
) {
  const { data, isLoading, error, refetch } = useReadContract({
    address: tokenAddress,
    abi: ERC20_ABI,
    functionName: "allowance",
    args: ownerAddress ? [ownerAddress, spenderAddress] : undefined,
    query: {
      enabled: !!ownerAddress,
    },
  });

  return {
    allowance: data as bigint | undefined,
    isLoading,
    error,
    refetch,
  };
}
