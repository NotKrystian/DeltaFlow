"use client";

import { useEffect, useMemo, useState } from "react";
import { useReadContract } from "wagmi";
import { getAddress } from "viem";
import {
  ERC20_ABI,
  FEE_MODULE_ABI,
  SOVEREIGN_ALM_ABI,
  SOVEREIGN_POOL_ABI,
} from "@/contracts";
import { useMarket } from "@/app/context/MarketContext";
import { useMarketEvmDecimals } from "@/app/hooks/useMarketEvmDecimals";
import {
  dynamicFeeBipsFromSides,
  extractFeeInBipsFromModuleReturn,
  feeAtUsdcShareTenths,
  inferBaseFeeBipsFromProbeTotal,
  isZeroAddr,
  valueSplitFromVault,
} from "@/app/lib/feeSkewMath";

const ZERO = "0x0000000000000000000000000000000000000000" as const;

type Props = {
  poolAddress: string;
  vaultAddress: string;
  almAddress: string;
};

export default function PoolSkewFeeCard({
  poolAddress,
  vaultAddress,
  almAddress,
}: Props) {
  const { market } = useMarket();
  const { baseDecimals, usdcDecimals } = useMarketEvmDecimals();
  const baseTok = market.tokens.BASE;
  const usdcTok = market.tokens.USDC;

  const pool = poolAddress as `0x${string}`;
  const vault = vaultAddress as `0x${string}`;
  const alm = almAddress as `0x${string}`;

  const enabled =
    !isZeroAddr(poolAddress) &&
    !isZeroAddr(vaultAddress) &&
    !isZeroAddr(almAddress);

  const { data: poolFeeMod } = useReadContract({
    address: pool,
    abi: SOVEREIGN_POOL_ABI,
    functionName: "swapFeeModule",
    query: { enabled },
  });

  const feeModuleAddr = useMemo(() => {
    const mod = (poolFeeMod as string | undefined) || "";
    if (!mod || mod.toLowerCase() === ZERO.toLowerCase()) {
      return market.swapFeeModule as `0x${string}`;
    }
    return mod as `0x${string}`;
  }, [poolFeeMod, market.swapFeeModule]);

  const feeModuleChecksum = useMemo(() => {
    if (!feeModuleAddr || feeModuleAddr.toLowerCase() === ZERO.toLowerCase()) {
      return undefined;
    }
    try {
      return getAddress(feeModuleAddr);
    } catch {
      return feeModuleAddr as `0x${string}`;
    }
  }, [feeModuleAddr]);

  const feeModuleOk = Boolean(feeModuleChecksum);

  const feeQueryEnabled = enabled && feeModuleOk;

  const { data: baseFeeBips, isLoading: lBaseFee } = useReadContract({
    address: feeModuleChecksum,
    abi: FEE_MODULE_ABI,
    functionName: "baseFeeBips",
    query: { enabled: feeQueryEnabled },
  });
  const { data: minFeeBips, isLoading: lMinFee } = useReadContract({
    address: feeModuleChecksum,
    abi: FEE_MODULE_ABI,
    functionName: "minFeeBips",
    query: { enabled: feeQueryEnabled },
  });
  const { data: maxFeeBips, isLoading: lMaxFee } = useReadContract({
    address: feeModuleChecksum,
    abi: FEE_MODULE_ABI,
    functionName: "maxFeeBips",
    query: { enabled: feeQueryEnabled },
  });

  const { data: poolDefaultFeeBips, isLoading: lPoolDefFee } = useReadContract({
    address: pool,
    abi: SOVEREIGN_POOL_ABI,
    functionName: "defaultSwapFeeBips",
    query: { enabled },
  });

  const {
    data: spotPxRaw,
    isLoading: spotLoading,
    isError: spotError,
    error: spotErr,
  } = useReadContract({
    address: alm,
    abi: SOVEREIGN_ALM_ABI,
    functionName: "getSpotPriceUsdcPerBase",
    query: { enabled },
  });

  const { data: usdcRaw, isLoading: lUsdcBal } = useReadContract({
    address: usdcTok.address,
    abi: ERC20_ABI,
    functionName: "balanceOf",
    args: [vault],
    query: { enabled },
  });

  const { data: baseRaw, isLoading: lBaseBal } = useReadContract({
    address: baseTok.address,
    abi: ERC20_ABI,
    functionName: "balanceOf",
    args: [vault],
    query: { enabled },
  });

  const probeAmountIn = useMemo(
    () => 10n ** BigInt(usdcDecimals),
    [usdcDecimals]
  );

  const probeEnabled =
    feeQueryEnabled &&
    usdcRaw !== undefined &&
    baseRaw !== undefined &&
    spotPxRaw !== undefined &&
    BigInt(spotPxRaw as bigint) > 0n;

  const {
    data: feeProbeRaw,
    isError: feeProbeError,
    isLoading: feeProbeLoading,
    error: feeProbeErr,
  } = useReadContract({
    address: feeModuleChecksum,
    abi: FEE_MODULE_ABI,
    functionName: "getSwapFeeInBips",
    args: [
      usdcTok.address,
      baseTok.address,
      probeAmountIn,
      ZERO as `0x${string}`,
      "0x",
    ],
    query: { enabled: probeEnabled, retry: false },
  });

  const probeFeeBips = useMemo(() => {
    if (feeProbeLoading || feeProbeError || feeProbeRaw == null) return undefined;
    return extractFeeInBipsFromModuleReturn(feeProbeRaw);
  }, [feeProbeLoading, feeProbeError, feeProbeRaw]);

  const px = spotPxRaw !== undefined ? BigInt(spotPxRaw as bigint) : 0n;

  const split = useMemo(() => {
    if (usdcRaw === undefined || baseRaw === undefined || px === 0n) {
      return null;
    }
    return valueSplitFromVault(usdcRaw, baseRaw, px, baseDecimals);
  }, [usdcRaw, baseRaw, px, baseDecimals]);

  const feeImmutableSettled = !lBaseFee && !lMinFee && !lMaxFee;
  const hasV3Immutables =
    baseFeeBips !== undefined &&
    minFeeBips !== undefined &&
    maxFeeBips !== undefined;
  const isLikelyComposite = feeImmutableSettled && !hasV3Immutables;

  /**
   * Prefer V3 immutables; else infer base by binary search so
   * `balanceSeekingFeeBipsFuture` matches the on-chain probe; else pool default.
   */
  const baseF = useMemo(() => {
    if (baseFeeBips !== undefined) return BigInt(baseFeeBips as bigint);
    if (!feeImmutableSettled || isLikelyComposite) return undefined;
    if (baseFeeBips === undefined && feeProbeLoading) return undefined;
    const imin = minFeeBips !== undefined ? BigInt(minFeeBips as bigint) : 0n;
    const imax = maxFeeBips !== undefined ? BigInt(maxFeeBips as bigint) : 10000n;
    if (
      probeFeeBips !== undefined &&
      split &&
      usdcRaw !== undefined &&
      baseRaw !== undefined
    ) {
      const inferred = inferBaseFeeBipsFromProbeTotal(
        probeFeeBips,
        usdcRaw as bigint,
        baseRaw as bigint,
        px,
        baseDecimals,
        probeAmountIn,
        true,
        imin,
        imax
      );
      if (inferred > 0n && inferred <= 10000n) return inferred;
    }
    if (poolDefaultFeeBips !== undefined) return BigInt(poolDefaultFeeBips as bigint);
    return 30n;
  }, [
    baseFeeBips,
    feeImmutableSettled,
    isLikelyComposite,
    feeProbeLoading,
    probeFeeBips,
    split,
    usdcRaw,
    baseRaw,
    px,
    baseDecimals,
    probeAmountIn,
    minFeeBips,
    maxFeeBips,
    poolDefaultFeeBips,
  ]);

  const minF = useMemo(() => {
    if (minFeeBips !== undefined) return BigInt(minFeeBips as bigint);
    if (!feeImmutableSettled || isLikelyComposite) return undefined;
    return 0n;
  }, [minFeeBips, feeImmutableSettled, isLikelyComposite]);

  const maxF = useMemo(() => {
    if (maxFeeBips !== undefined) return BigInt(maxFeeBips as bigint);
    if (!feeImmutableSettled || isLikelyComposite) return undefined;
    return 10000n;
  }, [maxFeeBips, feeImmutableSettled, isLikelyComposite]);

  const usingFallbackImmutableFees =
    feeImmutableSettled && !isLikelyComposite &&
    (baseFeeBips === undefined || minFeeBips === undefined || maxFeeBips === undefined);

  const currentFeeBips = useMemo(() => {
    if (
      isLikelyComposite ||
      !split ||
      usdcRaw === undefined ||
      baseF === undefined ||
      minF === undefined ||
      maxF === undefined
    ) {
      return null;
    }
    const right = split.baseValueRaw;
    return dynamicFeeBipsFromSides(
      usdcRaw as bigint,
      right,
      baseF,
      minF,
      maxF
    );
  }, [isLikelyComposite, split, usdcRaw, baseF, minF, maxF]);

  /** Prefer same on-chain call as Swap (`getSwapFeeInBips`); else modeled curve. */
  const displayCurrentFeeBips = useMemo(() => {
    if (probeFeeBips !== undefined) return probeFeeBips;
    if (isLikelyComposite) return null;
    return currentFeeBips;
  }, [probeFeeBips, isLikelyComposite, currentFeeBips]);

  const [sliderTenths, setSliderTenths] = useState(500);

  useEffect(() => {
    if (split && Number.isFinite(split.usdcSharePct)) {
      setSliderTenths(Math.round(split.usdcSharePct * 10));
    }
  }, [split]);

  const simulatedFeeBips = useMemo(() => {
    if (!split || baseF === undefined || minF === undefined || maxF === undefined) {
      return null;
    }
    return feeAtUsdcShareTenths(
      split.totalValueRaw,
      sliderTenths,
      baseF,
      minF,
      maxF
    );
  }, [split, sliderTenths, baseF, minF, maxF]);

  const bipsToPct = (b: bigint) => Number(b) / 100;

  const feeParamsLoading = lBaseFee || lMinFee || lMaxFee;
  const vaultBalLoading = lUsdcBal || lBaseBal;
  const waitingPoolDefaultFee =
    feeImmutableSettled &&
    baseFeeBips === undefined &&
    poolDefaultFeeBips === undefined &&
    lPoolDefFee;

  const loading =
    enabled &&
    (vaultBalLoading ||
      feeParamsLoading ||
      spotLoading ||
      waitingPoolDefaultFee ||
      (probeEnabled && feeProbeLoading));

  const feeParamsReady =
    baseF !== undefined && minF !== undefined && maxF !== undefined;

  const ready =
    split !== null &&
    displayCurrentFeeBips !== null &&
    (isLikelyComposite || (simulatedFeeBips !== null && feeParamsReady));

  const spotFailed = enabled && !spotLoading && (spotError || spotPxRaw === undefined);

  if (!enabled) {
    return (
      <div className="rounded-2xl bg-[var(--input-bg)] border border-[var(--border)] p-4 text-sm text-[var(--text-muted)]">
        Set pool, vault, and ALM addresses to see value skew and dynamic fee.
      </div>
    );
  }

  if (!feeModuleOk) {
    return (
      <div className="rounded-2xl bg-[var(--input-bg)] border border-[var(--border)] p-4 text-sm text-[var(--text-muted)]">
        No swap fee module on this pool (and no fallback in env).
      </div>
    );
  }

  return (
    <div className="rounded-2xl bg-[var(--input-bg)] border border-[var(--border)] overflow-hidden">
      <div className="p-4 border-b border-[var(--border)]">
        <h3 className="text-[var(--foreground)] font-medium">
          Pool value skew & dynamic fee
        </h3>
        <p className="text-xs text-[var(--text-muted)] mt-1 leading-relaxed">
          Vault balances valued at ALM spot (USDC raw vs base × px). Target is{" "}
          <strong className="text-[var(--text-secondary)]">50/50</strong> by
          value. Swap fee imbalance uses{" "}
          <strong className="text-[var(--text-secondary)]">projected</strong>{" "}
          post-trade vault value split (fixed-point with{" "}
          <code className="text-[10px]">amountInNet</code>), not pre-trade balances
          alone. Slider below uses hypothetical splits without simulating a trade leg.
        </p>
      </div>

      <div className="p-4 space-y-4">
        {loading && (
          <p className="text-sm text-[var(--text-muted)]">
            Loading vault, fee module, and spot price…
          </p>
        )}

        {!loading && usingFallbackImmutableFees && (
          <p className="text-xs text-[var(--text-secondary)] border border-[var(--border)] rounded-xl p-3 bg-[var(--card)]">
            Fee module immutables (<code className="text-[10px]">baseFeeBips</code> / min / max) did not return from RPC.
            Current fee uses on-chain <code className="text-[10px]">getSwapFeeInBips</code> (1 USDC probe, USDC→
            {market.baseSymbol}). Skew curve infers base from that quote minus the imbalance term; bounds default to 0–10000
            bips. Pool <code className="text-[10px]">defaultSwapFeeBips</code> is unrelated once a module is deployed.
          </p>
        )}

        {!loading && isLikelyComposite && (
          <p className="text-xs text-[var(--text-secondary)] border border-[var(--border)] rounded-xl p-3 bg-[var(--card)]">
            Composite fee module detected (no <code className="text-[10px]">baseFeeBips/min/max</code> immutables).
            Current fee is shown from on-chain{" "}
            <code className="text-[10px]">getSwapFeeInBips</code> probe (1 USDC, USDC→{market.baseSymbol}).
            Skew slider modeling is disabled for this module type.
          </p>
        )}

        {!loading && isLikelyComposite && probeFeeBips === undefined && (
          <p className="text-sm text-amber-500/90">
            On-chain fee probe unavailable right now (RPC/module call failed). Retry refresh.
            {feeProbeErr && (
              <span className="block font-mono text-xs mt-1 opacity-90">
                {(feeProbeErr as Error).message?.slice(0, 220)}
              </span>
            )}
          </p>
        )}

        {!loading && feeParamsReady && spotFailed && (
          <p className="text-sm text-amber-500/90">
            ALM spot price unavailable
            {spotErr && (
              <span className="block font-mono text-xs mt-1 opacity-90">
                {(spotErr as Error).message?.slice(0, 200)}
              </span>
            )}
          </p>
        )}

        {!loading && feeParamsReady && !spotFailed && px === 0n && (
          <p className="text-sm text-amber-500/90">
            Spot price returned zero — ALM may be misconfigured.
          </p>
        )}

        {!loading &&
          feeParamsReady &&
          !spotFailed &&
          px > 0n &&
          split === null && (
            <p className="text-sm text-amber-500/90">
              Could not read vault token balances (check vault address and RPC).
            </p>
          )}

        {ready && split && (
          <>
            <div>
              <div className="flex justify-between text-xs text-[var(--text-muted)] mb-1.5">
                <span>USDC value</span>
                <span>
                  {split.usdcSharePct.toFixed(1)}% /{" "}
                  {(100 - split.usdcSharePct).toFixed(1)}%{" "}
                  <span className="text-[var(--text-secondary)]">
                    {market.baseSymbol}
                  </span>
                </span>
                <span>{market.baseSymbol} value</span>
              </div>
              <div className="relative h-3 rounded-full overflow-hidden bg-[var(--card)] border border-[var(--border)]">
                <div
                  className="absolute inset-y-0 left-0 bg-emerald-500/40"
                  style={{ width: `${split.usdcSharePct}%` }}
                />
                <div
                  className="absolute inset-y-0 top-0 w-0.5 bg-[var(--foreground)] shadow-[0_0_8px_rgba(255,255,255,0.4)]"
                  style={{ left: `calc(${split.usdcSharePct}% - 1px)` }}
                  title="Current skew"
                />
                <div
                  className="absolute inset-y-0 top-0 w-0.5 bg-[var(--accent)] opacity-80"
                  style={{ left: `calc(${sliderTenths / 10}% - 1px)` }}
                  title="Slider (explore)"
                />
              </div>
              <div className="flex justify-between text-[10px] text-[var(--text-muted)] mt-1">
                <span>0%</span>
                <span>50/50</span>
                <span>100% USDC</span>
              </div>
            </div>

            <div className={`grid grid-cols-1 ${isLikelyComposite ? "" : "sm:grid-cols-2"} gap-3 text-sm`}>
              <div className="rounded-xl bg-[var(--card)] border border-[var(--border)] p-3">
                <p className="text-xs text-[var(--text-muted)] uppercase tracking-wide">
                  Current (vault)
                </p>
                <p className="text-lg font-semibold text-[var(--foreground)] tabular-nums mt-1">
                  {bipsToPct(displayCurrentFeeBips!).toFixed(2)}%
                </p>
                <p className="text-[10px] text-[var(--text-muted)] mt-0.5">
                  {probeFeeBips !== undefined ? (
                    <>
                      On-chain <code className="text-[9px]">getSwapFeeInBips</code> (1 USDC, USDC→{market.baseSymbol}
                      ), same API as Swap
                    </>
                  ) : isLikelyComposite ? (
                    <>On-chain probe unavailable</>
                  ) : (
                    <>Modeled from vault skew (probe unavailable)</>
                  )}
                </p>
                {!isLikelyComposite && (
                  <p className="text-[10px] text-[var(--text-muted)] mt-1">
                    Curve base {bipsToPct(baseF!).toFixed(2)}% · bounds {bipsToPct(minF!).toFixed(2)}–
                    {bipsToPct(maxF!).toFixed(2)}%
                  </p>
                )}
              </div>
              {!isLikelyComposite && (
                <div className="rounded-xl bg-[var(--card)] border border-[var(--border)] p-3">
                <p className="text-xs text-[var(--text-muted)] uppercase tracking-wide">
                  At slider (same total value)
                </p>
                <p className="text-lg font-semibold text-[var(--accent)] tabular-nums mt-1">
                  {bipsToPct(simulatedFeeBips!).toFixed(2)}%
                </p>
                <p className="text-[10px] text-[var(--text-muted)] mt-0.5">
                  USDC share {(sliderTenths / 10).toFixed(1)}% ·{" "}
                  {(100 - sliderTenths / 10).toFixed(1)}% {market.baseSymbol}{" "}
                  value
                </p>
                </div>
              )}
            </div>

            {!isLikelyComposite && (
              <div>
              <label className="block text-xs text-[var(--text-muted)] mb-2">
                Explore skew — same total value as current vault inventory; fee
                vs hypothetical USDC/base split
              </label>
              <input
                type="range"
                min={0}
                max={1000}
                value={sliderTenths}
                onChange={(e) => setSliderTenths(Number(e.target.value))}
                className="w-full h-2 rounded-full appearance-none cursor-pointer bg-[var(--card)] accent-[var(--accent)]"
              />
              <div className="flex justify-between text-[10px] text-[var(--text-muted)] mt-1">
                <span>Heavy {market.baseSymbol}</span>
                <span>Balanced</span>
                <span>Heavy USDC</span>
              </div>
              </div>
            )}
          </>
        )}
      </div>
    </div>
  );
}
