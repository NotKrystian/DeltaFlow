"use client";

import { useEffect, useMemo, useState } from "react";
import {
  useAccount,
  useReadContract,
  useWriteContract,
  useWaitForTransactionReceipt,
} from "wagmi";
import { formatUnits, parseUnits, maxUint256 } from "viem";
import { ArrowDown, ChevronDown, Loader2 } from "lucide-react";
import {
  ERC20_ABI,
  SOVEREIGN_POOL_ABI,
  FEE_MODULE_ABI,
  DELTAFLOW_COMPOSITE_FEE_READ_ABI,
  SOVEREIGN_ALM_ABI,
} from "@/contracts";
import { useMarket } from "@/app/context/MarketContext";
import type { TokenMeta } from "@/app/lib/marketConfig";
import { useMarketEvmDecimals } from "@/app/hooks/useMarketEvmDecimals";
import { extractFeeInBipsFromModuleReturn } from "@/app/lib/feeSkewMath";

const BALANCE_OF_ABI = [
  {
    type: "function",
    name: "balanceOf",
    stateMutability: "view",
    inputs: [{ name: "account", type: "address" }],
    outputs: [{ type: "uint256" }],
  },
] as const;

const ALM_SPOT_ABI = [
  {
    type: "function",
    name: "getSpotPriceUsdcPerBase",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "pxUsdcPerBase", type: "uint256" }],
  },
] as const;

/** Narrow ABI — `SOVEREIGN_POOL_ABI` typings may omit newer pool getters. */
const POOL_HEDGE_PERP_ABI = [
  {
    name: "hedgePerpAssetIndex",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint32" }],
  },
] as const;

function asBigInt(v: unknown): bigint {
  if (typeof v === "bigint") return v;
  if (typeof v === "number") return BigInt(Math.trunc(v));
  return BigInt(String(v));
}

// Minimal ABI for fee module quoting

// amountInMinusFee exactly like pool:
// amountInMinusFee = amountIn * 10000 / (10000 + feeBips)
function amountInMinusFee(amountIn: bigint, feeBips: bigint): bigint {
  const BIPS = 10_000n;
  return (amountIn * BIPS) / (BIPS + feeBips);
}

// Helpers: parse viem return shapes safely
function asBigint(v: any): bigint {
  if (v == null) return 0n;
  if (typeof v === "bigint") return v;
  try {
    return BigInt(v);
  } catch {
    return 0n;
  }
}

function extractAmountOut(almQuoteRaw: any): bigint {
  // Most common: { isCallbackOnSwap, amountOut, amountInFilled }
  if (almQuoteRaw?.amountOut != null) return asBigint(almQuoteRaw.amountOut);

  // Sometimes: [isCallbackOnSwap, amountOut, amountInFilled]
  if (Array.isArray(almQuoteRaw) && almQuoteRaw.length >= 2)
    return asBigint(almQuoteRaw[1]);

  // Sometimes nested
  if (almQuoteRaw?.quote?.amountOut != null)
    return asBigint(almQuoteRaw.quote.amountOut);
  if (almQuoteRaw?.[0]?.amountOut != null)
    return asBigint(almQuoteRaw[0].amountOut);

  return 0n;
}

// ═══════════════════════════════════════════════════════════════
// Token Input
// ═══════════════════════════════════════════════════════════════
function TokenInput({
  label,
  token,
  amount,
  onAmountChange,
  balance,
  readOnly = false,
  onMaxClick,
}: {
  label: string;
  token: TokenMeta;
  amount: string;
  onAmountChange?: (value: string) => void;
  balance?: string;
  readOnly?: boolean;
  onMaxClick?: () => void;
}) {
  return (
    <div className="rounded-3xl bg-[var(--input-bg)] border border-[var(--border)] p-4 sm:p-5">
      <div className="flex items-center justify-between gap-3 text-xs sm:text-sm text-[var(--text-muted)]">
        <span className="leading-none">{label}</span>

        {balance && (
          <span className="flex items-center gap-2 leading-none">
            <span className="whitespace-nowrap">Balance: {balance}</span>
            {onMaxClick && (
              <button
                type="button"
                onClick={onMaxClick}
                className="text-[var(--accent)] font-semibold hover:text-[var(--accent-hover)]"
                aria-label="Use max balance"
              >
                MAX
              </button>
            )}
          </span>
        )}
      </div>

      <div className="mt-3 flex items-center gap-3">
        <input
          type="text"
          value={amount}
          onChange={(e) =>
            onAmountChange?.(e.target.value.replace(/[^0-9.]/g, ""))
          }
          placeholder="0"
          readOnly={readOnly}
          className="min-w-0 bg-transparent w-full text-3xl sm:text-4xl font-semibold text-[var(--foreground)] placeholder-[var(--text-secondary)] outline-none leading-none"
          inputMode="decimal"
        />

        <button
          type="button"
          className="shrink-0 inline-flex items-center gap-2 h-11 px-3 rounded-2xl font-semibold text-[var(--foreground)] bg-[var(--card)] hover:bg-[var(--card-hover)] border border-[var(--border)]"
          aria-label={`Select ${token.symbol}`}
        >
          <div className="w-7 h-7 rounded-full bg-[var(--accent-muted)] flex items-center justify-center text-xs font-bold text-[var(--accent)]">
            {token.symbol[0]}
          </div>
          <span className="text-sm sm:text-base">{token.symbol}</span>
          <ChevronDown size={16} className="text-[var(--text-muted)]" />
        </button>
      </div>
    </div>
  );
}

// ═══════════════════════════════════════════════════════════════
// Swap Card
// ═══════════════════════════════════════════════════════════════
export default function SwapCard() {
  const { address, isConnected } = useAccount();
  const { market } = useMarket();
  const pool = market.pool;
  const SWAP_FEE_MODULE_FALLBACK = market.swapFeeModule;
  const [isHydrated, setIsHydrated] = useState(false);

  useEffect(() => {
    setIsHydrated(true);
  }, []);

  const [sellToken, setSellToken] = useState<"USDC" | "BASE">("USDC");
  const [amountIn, setAmountIn] = useState("");
  const [amountOut, setAmountOut] = useState("");

  const [txHash, setTxHash] = useState<`0x${string}` | undefined>();
  const [approvalNonce, setApprovalNonce] = useState(0);

  const buyKey: "USDC" | "BASE" = sellToken === "USDC" ? "BASE" : "USDC";
  const tokenIn = market.tokens[sellToken];
  const tokenOut = market.tokens[buyKey];

  const { baseDecimals: evmBaseDec, usdcDecimals: evmUsdcDec } =
    useMarketEvmDecimals();
  const tokenInDecimals = sellToken === "BASE" ? evmBaseDec : evmUsdcDec;
  const tokenOutDecimals = sellToken === "USDC" ? evmBaseDec : evmUsdcDec;

  const amountInParsed = useMemo(() => {
    if (!amountIn || isNaN(Number(amountIn))) return 0n;
    try {
      return parseUnits(amountIn, tokenInDecimals);
    } catch {
      return 0n;
    }
  }, [amountIn, tokenInDecimals]);

  // Pool reads
  const { data: poolToken0 } = useReadContract({
    address: pool,
    abi: SOVEREIGN_POOL_ABI,
    functionName: "token0",
    query: { enabled: true },
  });

  const { data: poolAlm } = useReadContract({
    address: pool,
    abi: SOVEREIGN_POOL_ABI,
    functionName: "alm",
    query: { enabled: true },
  });

  const { data: poolSwapFeeModule } = useReadContract({
    address: pool,
    abi: SOVEREIGN_POOL_ABI,
    functionName: "swapFeeModule",
    query: { enabled: true },
  });

  const { data: poolHedgePerpIx } = useReadContract({
    address: pool,
    abi: POOL_HEDGE_PERP_ABI,
    functionName: "hedgePerpAssetIndex",
    query: { enabled: true },
  });

  const isZeroToOne = useMemo(() => {
    if (!poolToken0) return sellToken === "BASE";
    return (
      tokenIn.address.toLowerCase() === (poolToken0 as string).toLowerCase()
    );
  }, [poolToken0, tokenIn.address, sellToken]);

  const feeModuleAddress = useMemo(() => {
    const mod = (poolSwapFeeModule as string | undefined) || "";
    const isZero = !mod || mod === "0x0000000000000000000000000000000000000000";
    return (isZero ? SWAP_FEE_MODULE_FALLBACK : mod) as `0x${string}`;
  }, [poolSwapFeeModule, SWAP_FEE_MODULE_FALLBACK]);

  const feeDiagEnabled =
    !!feeModuleAddress &&
    feeModuleAddress !== "0x0000000000000000000000000000000000000000";

  const { data: feePerpIndex, isError: feePerpIxErr } = useReadContract({
    address: feeModuleAddress,
    abi: DELTAFLOW_COMPOSITE_FEE_READ_ABI,
    functionName: "perpIndex",
    query: { enabled: feeDiagEnabled, retry: false },
  });

  const { data: feeUseMr } = useReadContract({
    address: feeModuleAddress,
    abi: DELTAFLOW_COMPOSITE_FEE_READ_ABI,
    functionName: "useMarketRiskComponent",
    query: { enabled: feeDiagEnabled && !feePerpIxErr, retry: false },
  });

  const { data: feeParamsTuple } = useReadContract({
    address: feeModuleAddress,
    abi: DELTAFLOW_COMPOSITE_FEE_READ_ABI,
    functionName: "feeParams",
    query: { enabled: feeDiagEnabled && !feePerpIxErr, retry: false },
  });

  const { data: snapshotSzi, isError: snapshotSziErr } = useReadContract({
    address: feeModuleAddress,
    abi: DELTAFLOW_COMPOSITE_FEE_READ_ABI,
    functionName: "snapshotPerpSzi",
    query: { enabled: feeDiagEnabled && !feePerpIxErr, retry: false },
  });

  const hMaxSz = feeParamsTuple?.hMaxSz;

  const feeDiagNotes = useMemo(() => {
    if (feePerpIxErr) return [];
    const lines: string[] = [];
    const UINT32_MAX = 4294967295n;
    if (feePerpIndex !== undefined && poolHedgePerpIx !== undefined) {
      const a = asBigInt(feePerpIndex);
      const b = asBigInt(poolHedgePerpIx);
      if (a !== b) {
        lines.push(
          `Fee module perp index (${feePerpIndex}) ≠ pool hedge index (${poolHedgePerpIx}) — on-chain fee snapshot will read the wrong market (often 0 sz). Redeploy the fee module with the correct PERP_INDEX.`
        );
      }
    }
    if (feePerpIndex !== undefined && asBigInt(feePerpIndex) === UINT32_MAX) {
      lines.push(
        "Fee module has perpIndex = uint32.max — perp position is not read; only pending hedge queue counts toward snapshotPerpSzi."
      );
    }
    if (
      snapshotSzi !== undefined &&
      snapshotSzi === 0n &&
      feePerpIndex !== undefined &&
      asBigInt(feePerpIndex) !== UINT32_MAX
    ) {
      lines.push(
        "snapshotPerpSzi is 0 — the fee module does not see an open perp (or hedge is only in a form this snapshot ignores). Compare with Strategist / HL explorer for the vault."
      );
    }
    if (
      hMaxSz !== undefined &&
      hMaxSz > 0n &&
      snapshotSzi !== undefined &&
      snapshotSzi !== 0n
    ) {
      const abs = snapshotSzi < 0n ? -snapshotSzi : snapshotSzi;
      if (abs < hMaxSz / 1000n) {
        lines.push(
          `Hedge utilization |H|/hMaxSz is tiny (|sz|≈${abs.toString()}, hMaxSz=${hMaxSz.toString()}). The unwind marginal curve sits near its 10 bps “flat” end — same ballpark as the 50/50 concentration floor, so the quote often reads ~10 bps. Lower DF_H_MAX_SZ (fee deploy) to match realistic max hedge size.`
        );
      }
    }
    if (feeUseMr === false) {
      lines.push(
        "Concentration-only mode (DF_USE_MARKET_RISK_COMPONENT=false): fee blends unwind integral with inventory concentration; small trades weight heavily toward the ~10 bps concentration floor at balanced pools."
      );
    }
    return lines;
  }, [
    feePerpIxErr,
    feePerpIndex,
    poolHedgePerpIx,
    snapshotSzi,
    hMaxSz,
    feeUseMr,
  ]);

  // Vault address (this is what BOTH contracts use)
  const { data: vaultAddr } = useReadContract({
    address: pool,
    abi: SOVEREIGN_POOL_ABI,
    functionName: "sovereignVault",
    query: { enabled: true },
  });

  const { data: vaultUsdcRaw } = useReadContract({
    address: market.tokens.USDC.address,
    abi: BALANCE_OF_ABI,
    functionName: "balanceOf",
    args: vaultAddr ? [vaultAddr as `0x${string}`] : undefined,
    query: { enabled: !!vaultAddr },
  });

  const { data: vaultBaseRaw } = useReadContract({
    address: market.tokens.BASE.address,
    abi: BALANCE_OF_ABI,
    functionName: "balanceOf",
    args: vaultAddr ? [vaultAddr as `0x${string}`] : undefined,
    query: { enabled: !!vaultAddr },
  });

  // ALM spot px (raw USDC-per-PURR scaled)
  const { data: spotPxRaw } = useReadContract({
    address: (poolAlm as `0x${string}`) || undefined,
    abi: ALM_SPOT_ABI,
    functionName: "getSpotPriceUsdcPerBase",
    query: { enabled: !!poolAlm },
  });

  // Balance
  const { data: balanceRaw } = useReadContract({
    address: tokenIn.address,
    abi: [
      {
        name: "balanceOf",
        type: "function",
        stateMutability: "view",
        inputs: [{ name: "account", type: "address" }],
        outputs: [{ name: "", type: "uint256" }],
      },
    ] as const,
    functionName: "balanceOf",
    args: address ? [address] : undefined,
    query: { enabled: !!address },
  });

  const balance = balanceRaw
    ? formatUnits(balanceRaw, tokenInDecimals)
    : undefined;

  // Allowance
  const { data: allowance, refetch: refetchAllowance } = useReadContract({
    address: tokenIn.address,
    abi: ERC20_ABI,
    functionName: "allowance",
    args: address ? [address, pool] : undefined,
    query: {
      enabled: !!address && amountInParsed > 0n,
      staleTime: 0,
      gcTime: 0,
    },
    scopeKey: `allowance-${sellToken}-${market.id}-${approvalNonce}`,
  });

  const needsApproval = useMemo(() => {
    if (!amountInParsed) return false;
    if (allowance === undefined) return false;
    return allowance < amountInParsed;
  }, [amountInParsed, allowance]);

  // Fee quote
  const {
    data: feeDataRaw,
    error: feeError,
    isError: feeIsError,
    isLoading: feeLoading,
  } = useReadContract({
    address: feeModuleAddress,
    abi: FEE_MODULE_ABI,
    functionName: "getSwapFeeInBips",
    args:
      amountInParsed > 0n
        ? [
            tokenIn.address,
            tokenOut.address,
            amountInParsed,
            (address ??
              "0x0000000000000000000000000000000000000000") as `0x${string}`,
            "0x",
          ]
        : undefined,
    query: {
      enabled: amountInParsed > 0n,
      retry: false, // surface errors immediately
    },
  });

  const feeBips = useMemo(() => {
    if (feeIsError || feeDataRaw == null) return null;
    return extractFeeInBipsFromModuleReturn(feeDataRaw);
  }, [feeDataRaw, feeIsError]);
  const feePct = useMemo(
    () => (feeBips == null ? null : Number(feeBips) / 100),
    [feeBips]
  );

  const amountInMinus = useMemo(() => {
    if (amountInParsed <= 0n) return 0n;
    return amountInMinusFee(amountInParsed, feeBips ?? 0n);
  }, [amountInParsed, feeBips]);

  const effectiveFeeBipsForQuote = feeBips ?? 0n;

  // ALM quote
  const {
    data: almQuoteRaw,
    isLoading: quoteLoading,
    error: quoteError,
    isError: quoteIsError,
  } = useReadContract({
    address: (poolAlm as `0x${string}`) || undefined,
    abi: SOVEREIGN_ALM_ABI,
    functionName: "getLiquidityQuote",
    args:
      amountInParsed > 0n && poolAlm
        ? [
            {
              isZeroToOne,
              amountInMinusFee: amountInMinus,
              feeInBips: effectiveFeeBipsForQuote,
              sender: (address ??
                "0x0000000000000000000000000000000000000000") as `0x${string}`,
              recipient: (address ??
                "0x0000000000000000000000000000000000000000") as `0x${string}`,
              tokenOutSwap: tokenOut.address,
            },
            "0x",
            "0x",
          ]
        : undefined,
    query: {
      enabled: amountInParsed > 0n && !!poolAlm,
      retry: false,
    },
  });

  const quotedOut = useMemo(() => extractAmountOut(almQuoteRaw), [almQuoteRaw]);

  // Sync amountOut UI
  useEffect(() => {
    if (!amountIn || Number(amountIn) === 0 || amountInParsed === 0n) {
      setAmountOut("");
      return;
    }
    if (quotedOut > 0n) setAmountOut(formatUnits(quotedOut, tokenOutDecimals));
    else setAmountOut("");
  }, [amountIn, amountInParsed, quotedOut, tokenOutDecimals]);

  // Writes + receipt
  const { writeContractAsync, isPending } = useWriteContract();
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({
    hash: txHash,
  });
  const isLoading = isPending || isConfirming;

  useEffect(() => {
    if (!isSuccess) return;
    setApprovalNonce((n) => n + 1);
    refetchAllowance?.();
    setTxHash(undefined);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isSuccess]);
  useEffect(() => {
    if (process.env.NEXT_PUBLIC_DEBUG_SWAP !== "true") return;
    if (!vaultAddr) return;

    const usdcDec = evmUsdcDec;
    const baseDec = evmBaseDec;

    const vu = vaultUsdcRaw ?? 0n;
    const vp = vaultBaseRaw ?? 0n;

    const spot = spotPxRaw ?? 0n;

    // Interpreting spot as "USDC per 1 base" scaled by 10^USDCdec (ALM convention)
    const spotAsNumber = usdcDec > 0 ? Number(spot) / 10 ** usdcDec : NaN;

    // Also show implied "base per 1 USDC" (reciprocal)
    const impliedPurrPerUsdc =
      spotAsNumber && spotAsNumber > 0 ? 1 / spotAsNumber : NaN;

    console.groupCollapsed("[SWAP DEBUG]");
    console.log("Pool:", pool);
    console.log("ALM:", poolAlm);
    console.log("FeeModule:", feeModuleAddress);
    console.log("Vault (pool.sovereignVault()):", vaultAddr);

    console.log(
      "USDC address:",
      market.tokens.USDC.address,
      "decimals(onchain):",
      usdcDec,
      "decimals(config):",
      market.tokens.USDC.decimals,
    );
    console.log(
      `${market.baseSymbol} address:`,
      market.tokens.BASE.address,
      "decimals(onchain):",
      baseDec,
      "decimals(config):",
      market.tokens.BASE.decimals,
    );

    console.log(
      "Vault USDC raw:",
      vu.toString(),
      "formatted:",
      usdcDec ? formatUnits(vu, usdcDec) : "(no dec)",
    );
    console.log(
      `Vault ${market.baseSymbol} raw:`,
      vp.toString(),
      "formatted:",
      baseDec ? formatUnits(vp, baseDec) : "(no dec)",
    );

    console.log("Spot px raw:", spot.toString());
    console.log("Spot px interpreted:", spotAsNumber);

    if (amountInParsed > 0n && usdcDec > 0 && baseDec > 0 && spot > 0n) {
      const scale = 10n ** BigInt(baseDec);
      const expectedOutRaw = (amountInParsed * scale) / spot;
      console.log(
        "amountInParsed:",
        amountInParsed.toString(),
        "(",
        formatUnits(amountInParsed, usdcDec),
        "USDC )",
      );
      console.log(
        "expectedOutRaw (using spotPxRaw):",
        expectedOutRaw.toString(),
        "formatted:",
        formatUnits(expectedOutRaw, baseDec),
      );
    }

    console.groupEnd();
  }, [
    vaultAddr,
    poolAlm,
    feeModuleAddress,
    evmUsdcDec,
    evmBaseDec,
    vaultUsdcRaw,
    vaultBaseRaw,
    spotPxRaw,
    amountInParsed,
    pool,
    market,
  ]);

  const handleFlip = () => {
    setSellToken(buyKey);
    setAmountIn(amountOut);
    setAmountOut(amountIn);
  };

  const handleMax = () => {
    if (balance) setAmountIn(balance);
  };

  const handleApprove = async () => {
    if (!address) return;
    try {
      const hash = await writeContractAsync({
        address: tokenIn.address,
        abi: ERC20_ABI,
        functionName: "approve",
        args: [pool, maxUint256],
      });
      setTxHash(hash);
    } catch (err) {
      console.error("Approve failed:", err);
    }
  };

  const handleSwap = async () => {
    if (!address || !amountInParsed) return;

    const deadline = BigInt(Math.floor(Date.now() / 1000) + 60 * 20);
    // No user slippage: min out = ALM quote output (dynamic fee already in quote path)
    const minOut = quotedOut > 0n ? quotedOut : 0n;

    const params = {
      isSwapCallback: false,
      isZeroToOne,
      amountIn: amountInParsed,
      amountOutMin: minOut,
      deadline,
      recipient: address,
      swapTokenOut: tokenOut.address,
      swapContext: {
        externalContext: "0x" as const,
        verifierContext: "0x" as const,
        swapFeeModuleContext: "0x" as const,
        swapCallbackContext: "0x" as const,
      },
    };

    try {
      const hash = await writeContractAsync({
        address: pool,
        abi: SOVEREIGN_POOL_ABI,
        functionName: "swap",
        args: [params],
      });
      setTxHash(hash);
    } catch (err) {
      console.error("Swap failed:", err);
    }
  };

  // Button state
  const buttonState = (() => {
    // Avoid SSR/client hydration mismatch from wallet auto-connect state.
    if (!isHydrated) return { text: "Connect Wallet", disabled: true };
    if (!isConnected) return { text: "Connect Wallet", disabled: true };
    if (!amountIn || Number(amountIn) === 0)
      return { text: "Enter amount", disabled: true };
    if (balance && Number(amountIn) > Number(balance))
      return { text: "Insufficient balance", disabled: true };
    if (isLoading) return { text: "Confirming...", disabled: true };

    if (needsApproval)
      return {
        text: `Approve ${tokenIn.symbol}`,
        disabled: false,
        action: handleApprove,
      };

    // If fee module reverted, show it (this usually means vault liquidity require() failed)
    if (feeIsError) return { text: "Fee module reverted", disabled: true };

    if (amountInParsed > 0n && feeLoading)
      return { text: "Quoting...", disabled: true };

    // If quote reverted, show it (ALM require/price issue)
    if (feeIsError) return { text: "Fee module reverted", disabled: true };

    if (amountInParsed > 0n && quoteLoading)
      return { text: "Quoting...", disabled: true };

    // If quote reverted, show it (ALM require/price issue)
    if (quoteIsError) return { text: "Quote reverted", disabled: true };

    if (quotedOut === 0n) return { text: "No quote", disabled: true };

    return { text: "Swap", disabled: false, action: handleSwap };
  })();

  const shownRate = useMemo(() => {
    const ain = Number(amountIn);
    const aout = Number(amountOut);
    if (!ain || !aout || ain <= 0 || aout <= 0) return "";
    return (aout / ain).toFixed(6);
  }, [amountIn, amountOut]);

  return (
    <div className="w-full">
      <div className="bg-[var(--card)] rounded-3xl border border-[var(--border)] shadow-lg glow-green p-4 sm:p-6 flex flex-col">
        {/* header */}
        <div className="flex items-center justify-between">
          <h2 className="text-lg font-semibold text-[var(--foreground)]">
            Swap
          </h2>
        </div>

        {/* body */}
        <div className="mt-5">
          <div className="relative space-y-3">
            <TokenInput
              label="Sell"
              token={tokenIn}
              amount={amountIn}
              onAmountChange={setAmountIn}
              balance={balance}
              onMaxClick={handleMax}
            />

            <div className="pointer-events-none absolute left-1/2 top-1/2 -translate-x-1/2 -translate-y-1/2">
              <button
                type="button"
                onClick={handleFlip}
                className="pointer-events-auto bg-[var(--card)] p-2.5 rounded-2xl border border-[var(--border)] hover:border-[var(--border-hover)] hover:bg-[var(--card-hover)] transition shadow-sm"
                aria-label="Flip tokens"
              >
                <ArrowDown size={20} className="text-[var(--accent)]" />
              </button>
            </div>

            <TokenInput
              label="Buy"
              token={tokenOut}
              amount={amountOut}
              readOnly
            />
          </div>
        </div>

        {/* details */}
        {amountIn && amountOut && Number(amountOut) > 0 && (
          <div className="mt-4 rounded-2xl bg-[var(--accent-muted)] border border-[var(--border)] p-4 text-sm">
            <div className="flex items-center justify-between gap-3 text-[var(--text-muted)]">
              <span>Rate</span>
              <span className="text-[var(--foreground)] text-right">
                1 {tokenIn.symbol} = {shownRate} {tokenOut.symbol}
              </span>
            </div>

            <div className="flex items-center justify-between gap-3 text-[var(--text-muted)] mt-2">
              <span>Swap fee (module)</span>
              <span className="text-[var(--foreground)]">
                {feeBips == null || feePct == null ? (
                  <span className="text-[var(--text-muted)]">
                    unavailable (module reverted)
                  </span>
                ) : (
                  <>
                    {feePct.toFixed(2)}%{" "}
                    <span className="text-[var(--text-muted)]">
                      ({feeBips.toString()} bips)
                    </span>
                  </>
                )}
              </span>
            </div>
            <p className="text-[10px] text-[var(--text-muted)] mt-1.5 leading-snug">
              From <code className="text-[9px]">getSwapFeeInBips</code> for this
              trade. The pool&apos;s{" "}
              <code className="text-[9px]">defaultSwapFeeBips</code> in Strategist
              is only used when no fee module is set.
            </p>
            {!feePerpIxErr && feeDiagEnabled && (
              <div className="text-[10px] text-[var(--text-muted)] mt-2 space-y-1 border-t border-[var(--border)] pt-2">
                <div className="font-medium text-[var(--foreground)]">
                  Fee hedge snapshot (vault, same as module)
                </div>
                <div>
                  Pool hedge index:{" "}
                  <code className="text-[9px]">
                    {poolHedgePerpIx?.toString() ?? "…"}
                  </code>
                  {" · "}
                  Module perp index:{" "}
                  <code className="text-[9px]">
                    {feePerpIndex?.toString() ?? "…"}
                  </code>
                </div>
                <div>
                  <code className="text-[9px]">snapshotPerpSzi</code>:{" "}
                  {snapshotSziErr ? (
                    <span className="text-amber-600 dark:text-amber-400">
                      unavailable — upgrade fee module bytecode to expose{" "}
                      <code className="text-[9px]">snapshotPerpSzi()</code>
                    </span>
                  ) : (
                    <code className="text-[9px]">{snapshotSzi?.toString() ?? "…"}</code>
                  )}
                  {hMaxSz !== undefined && hMaxSz > 0n && !snapshotSziErr && snapshotSzi !== undefined ? (
                    <>
                      {" "}
                      <span className="text-[var(--text-muted)]">
                        · hMaxSz{" "}
                        <code className="text-[9px]">{hMaxSz.toString()}</code> (util
                        ≈{" "}
                        {(() => {
                          const abs =
                            snapshotSzi < 0n ? -snapshotSzi : snapshotSzi;
                          const pct = (abs * 10000n) / hMaxSz;
                          return `${(Number(pct) / 100).toFixed(2)}%`;
                        })()}
                        )
                      </span>
                    </>
                  ) : null}
                </div>
                {feeDiagNotes.map((t, i) => (
                  <p
                    key={i}
                    className="text-amber-700 dark:text-amber-300 leading-snug"
                  >
                    {t}
                  </p>
                ))}
              </div>
            )}
          </div>
        )}

        {/* show revert reasons */}
        {(feeIsError || quoteIsError) && (
          <div className="mt-4 rounded-2xl bg-[var(--accent-muted)] border border-[var(--border)] p-4 text-xs">
            {feeIsError && (
              <div className="text-[var(--text-muted)]">
                <div className="font-semibold text-[var(--foreground)] mb-1">
                  Fee module error
                </div>
                <div className="font-mono break-all">
                  {(feeError as any)?.shortMessage ||
                    (feeError as any)?.message ||
                    "reverted"}
                </div>
              </div>
            )}
            {quoteIsError && (
              <div className="text-[var(--text-muted)] mt-3">
                <div className="font-semibold text-[var(--foreground)] mb-1">
                  ALM quote error
                </div>
                <div className="font-mono break-all">
                  {(quoteError as any)?.shortMessage ||
                    (quoteError as any)?.message ||
                    "reverted"}
                </div>
              </div>
            )}
          </div>
        )}

        {/* CTA */}
        <div className="mt-6">
          <button
            onClick={buttonState.action}
            disabled={buttonState.disabled}
            className={`w-full py-4 rounded-2xl font-semibold text-lg transition ${
              buttonState.disabled
                ? "bg-[var(--input-bg)] text-[var(--text-secondary)] cursor-not-allowed"
                : "bg-[var(--accent)] text-white hover:bg-[var(--accent-hover)] glow-green-strong"
            }`}
          >
            <span className="flex items-center justify-center gap-2">
              {isLoading && <Loader2 size={20} className="animate-spin" />}
              {buttonState.text}
            </span>
          </button>

          {txHash && (
            <div className="mt-4 rounded-2xl bg-[var(--accent-muted)] border border-[var(--border)] p-4 text-center">
              <p className="text-[var(--text-muted)] text-sm">
                Tx:{" "}
                <a
                  href={`https://explorer.hyperliquid-testnet.xyz/tx/${txHash}`}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="underline font-medium"
                >
                  View transaction
                </a>
              </p>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
