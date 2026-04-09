"use client";

import { useCallback, useMemo } from "react";
import { useAccount, useReadContract, useReadContracts } from "wagmi";
import { formatUnits } from "viem";
import {
  ERC20_ABI,
  SOVEREIGN_VAULT_ABI,
  SOVEREIGN_ALM_ABI,
  FEE_SURPLUS_ABI,
} from "@/contracts";
import { useMarket } from "@/app/context/MarketContext";
import { useMarketEvmDecimals } from "./useMarketEvmDecimals";

const WAD = 10n ** 18n;

/** LP token (DFLP) lives on the SovereignVault contract address. */
export function useVaultLp() {
  const { address } = useAccount();
  const { market } = useMarket();
  const vault = market.vault;
  const feeSurplus = market.feeSurplus;
  const base = market.tokens.BASE;
  const usdc = market.tokens.USDC;
  const { baseDecimals, usdcDecimals } = useMarketEvmDecimals();
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
          address: market.alm,
          abi: SOVEREIGN_ALM_ABI,
          functionName: "getSpotPriceUsdcPerBase",
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
  const reserveBase = reserveTuple?.[1];

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
        reserveBase === undefined ||
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

      const baseDec = BigInt(baseDecimals);
      const scale = 10n ** baseDec;
      const basePart = (reserveBase * spotPriceRaw) / scale;
      const poolValue = reserveUsdcOnly + basePart;
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
      reserveBase,
      totalSupply,
      spotPriceRaw,
      userShares,
      surplusUsdc,
      baseDecimals,
    ]);

  return {
    vault,
    lpSymbol,
    reserveUsdc: reserveUsdcOnly,
    reservePurr: reserveBase,
    reserveBase,
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
    baseSymbol: market.baseSymbol,
    formatUsdc: (v: bigint | undefined) =>
      v === undefined ? "—" : formatUnits(v, usdcDecimals),
    formatPurr: (v: bigint | undefined) =>
      v === undefined ? "—" : formatUnits(v, baseDecimals),
    formatBase: (v: bigint | undefined) =>
      v === undefined ? "—" : formatUnits(v, baseDecimals),
    lpDecimals,
    formatShares: (v: bigint | undefined) =>
      v === undefined ? "—" : formatUnits(v, lpDecimals),
    isLoading,
    error,
    refetch,
  };
}
