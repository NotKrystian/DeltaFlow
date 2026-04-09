"use client";

import { useCallback, useMemo } from "react";
import { useAccount, useReadContract, useReadContracts } from "wagmi";
import { formatUnits } from "viem";
import {
  ADDRESSES,
  ERC20_ABI,
  SOVEREIGN_VAULT_ABI,
  SOVEREIGN_ALM_ABI,
  FEE_SURPLUS_ABI,
  TOKENS,
} from "@/contracts";

const WAD = 10n ** 18n;

/** LP token (DFLP) lives on the SovereignVault contract address. */
export function useVaultLp() {
  const { address } = useAccount();
  const vault = ADDRESSES.VAULT;
  const feeSurplus = ADDRESSES.FEE_SURPLUS;
  const hasFeeSurplus =
    feeSurplus !== "0x0000000000000000000000000000000000000000";

  const { data, isLoading: loadingBundle, error, refetch: refetchBundle } =
    useReadContracts({
      contracts: [
        {
          address: vault,
          abi: SOVEREIGN_VAULT_ABI,
          functionName: "getReserves",
        },
        {
          address: vault,
          abi: ERC20_ABI,
          functionName: "totalSupply",
        },
        {
          address: vault,
          abi: ERC20_ABI,
          functionName: "balanceOf",
          args: address ? [address] : undefined,
        },
        {
          address: ADDRESSES.ALM,
          abi: SOVEREIGN_ALM_ABI,
          functionName: "getSpotPriceUSDCperPURR",
        },
        {
          address: vault,
          abi: ERC20_ABI,
          functionName: "symbol",
        },
        {
          address: vault,
          abi: ERC20_ABI,
          functionName: "decimals",
        },
      ],
    });

  const {
    data: surplusUsdcRaw,
    isLoading: loadingSurplus,
    refetch: refetchSurplus,
  } = useReadContract({
    address: feeSurplus,
    abi: FEE_SURPLUS_ABI,
    functionName: "surplusUsdc",
    query: { enabled: hasFeeSurplus },
  });

  const refetch = useCallback(() => {
    refetchBundle();
    if (hasFeeSurplus) refetchSurplus();
  }, [refetchBundle, refetchSurplus, hasFeeSurplus]);

  const isLoading = loadingBundle || (hasFeeSurplus && loadingSurplus);

  const reserveTuple = data?.[0]?.result as readonly [bigint, bigint] | undefined;
  const reserveUsdcOnly = reserveTuple?.[0];
  const reservePurr = reserveTuple?.[1];

  const totalSupply = data?.[1]?.result as bigint | undefined;
  const userShares = data?.[2]?.result as bigint | undefined;
  const spotPriceRaw = data?.[3]?.result as bigint | undefined;
  const lpSymbol = (data?.[4]?.result as string | undefined) ?? "DFLP";
  const lpDecimals = Number(data?.[5]?.result ?? 18n);
  const surplusUsdc = hasFeeSurplus
    ? (surplusUsdcRaw as bigint | undefined)
    : undefined;

  const { poolValueUsdc, sharePriceUsdc, userValueUsdc, userSharePct, userSurplusAttribution } =
    useMemo(() => {
      if (
        reserveUsdcOnly === undefined ||
        reservePurr === undefined ||
        totalSupply === undefined ||
        totalSupply === 0n ||
        spotPriceRaw === undefined
      ) {
        return {
          poolValueUsdc: undefined,
          sharePriceUsdc: undefined,
          userValueUsdc: undefined,
          userSharePct: undefined,
          userSurplusAttribution: undefined,
        };
      }

      const purrDec = BigInt(TOKENS.PURR.decimals);
      const scale = 10n ** purrDec;
      const purrPart = (reservePurr * spotPriceRaw) / scale;
      const poolValue = reserveUsdcOnly + purrPart;
      const sharePrice = (poolValue * WAD) / totalSupply;

      let userVal: bigint | undefined;
      let pct: number | undefined;
      let surplusAtt: bigint | undefined;

      if (userShares !== undefined && userShares > 0n) {
        userVal = (userShares * poolValue) / totalSupply;
        pct = Number((userShares * 10000n) / totalSupply) / 100;
        if (surplusUsdc !== undefined && surplusUsdc > 0n) {
          surplusAtt = (userShares * surplusUsdc) / totalSupply;
        }
      }

      return {
        poolValueUsdc: poolValue,
        sharePriceUsdc: sharePrice,
        userValueUsdc: userVal,
        userSharePct: pct,
        userSurplusAttribution: surplusAtt,
      };
    }, [
      reserveUsdcOnly,
      reservePurr,
      totalSupply,
      spotPriceRaw,
      userShares,
      surplusUsdc,
    ]);

  return {
    vault,
    lpSymbol,
    reserveUsdc: reserveUsdcOnly,
    reservePurr,
    totalSupply,
    userShares,
    spotPriceRaw,
    surplusUsdc,
    poolValueUsdc,
    sharePriceUsdc,
    userValueUsdc,
    userSharePct,
    userSurplusAttribution,
    hasFeeSurplus,
    formatUsdc: (v: bigint | undefined) =>
      v === undefined ? "—" : formatUnits(v, TOKENS.USDC.decimals),
    formatPurr: (v: bigint | undefined) =>
      v === undefined ? "—" : formatUnits(v, TOKENS.PURR.decimals),
    lpDecimals,
    formatShares: (v: bigint | undefined) =>
      v === undefined ? "—" : formatUnits(v, lpDecimals),
    isLoading,
    error,
    refetch,
  };
}
