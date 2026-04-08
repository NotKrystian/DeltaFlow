"use client";

import { useEffect, useMemo, useState } from "react";
import {
  useAccount,
  useReadContract,
  useWriteContract,
  useWaitForTransactionReceipt,
} from "wagmi";
import { formatUnits, parseUnits, maxUint256 } from "viem";
import { ArrowDown, ChevronDown, Loader2, Settings } from "lucide-react";
import {
  TOKENS,
  ERC20_ABI,
  SOVEREIGN_POOL_ABI,
  FEE_MODULE_ABI,
  SOVEREIGN_ALM_ABI,
  ADDRESSES,
} from "@/contracts";

// Re-export for other components
export { TOKENS };

// Hard-set to your deployed pool

// Fallback if pool.swapFeeModule() is zero — matches `NEXT_PUBLIC_SWAP_FEE_MODULE`
const SWAP_FEE_MODULE_FALLBACK = ADDRESSES.SWAP_FEE_MODULE;

// --- Debug ABIs ---
const DECIMALS_ABI = [
  {
    type: "function",
    name: "decimals",
    stateMutability: "view",
    inputs: [],
    outputs: [{ type: "uint8" }],
  },
] as const;

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
    name: "getSpotPriceUSDCperPURR",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "pxUSDCperPURR", type: "uint256" }],
  },
] as const;

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

function extractFeeBips(feeDataRaw: any): bigint {
  // Most common: { feeInBips, internalContext }
  if (feeDataRaw?.feeInBips != null) return asBigint(feeDataRaw.feeInBips);

  // Sometimes: [feeInBips, internalContext]
  if (Array.isArray(feeDataRaw) && feeDataRaw.length > 0)
    return asBigint(feeDataRaw[0]);

  // Sometimes nested: { data: { feeInBips } } or { 0: { feeInBips } }
  if (feeDataRaw?.data?.feeInBips != null)
    return asBigint(feeDataRaw.data.feeInBips);
  if (feeDataRaw?.[0]?.feeInBips != null)
    return asBigint(feeDataRaw[0].feeInBips);

  return 0n;
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
  token: (typeof TOKENS)[keyof typeof TOKENS];
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

  const [sellToken, setSellToken] = useState<"PURR" | "USDC">("USDC");
  const [amountIn, setAmountIn] = useState("");
  const [amountOut, setAmountOut] = useState("");
  const [slippage, setSlippage] = useState("0.5");
  const [showSettings, setShowSettings] = useState(false);

  const [txHash, setTxHash] = useState<`0x${string}` | undefined>();
  const [approvalNonce, setApprovalNonce] = useState(0);

  const buyToken = sellToken === "PURR" ? "USDC" : "PURR";
  const tokenIn = TOKENS[sellToken];
  const tokenOut = TOKENS[buyToken];

  const amountInParsed = useMemo(() => {
    if (!amountIn || isNaN(Number(amountIn))) return 0n;
    try {
      return parseUnits(amountIn, tokenIn.decimals);
    } catch {
      return 0n;
    }
  }, [amountIn, tokenIn.decimals]);

  // Pool reads
  const { data: poolToken0 } = useReadContract({
    address: ADDRESSES.POOL,
    abi: SOVEREIGN_POOL_ABI,
    functionName: "token0",
    query: { enabled: true },
  });

  const { data: poolAlm } = useReadContract({
    address: ADDRESSES.POOL,
    abi: SOVEREIGN_POOL_ABI,
    functionName: "alm",
    query: { enabled: true },
  });

  const { data: poolSwapFeeModule } = useReadContract({
    address: ADDRESSES.POOL,
    abi: SOVEREIGN_POOL_ABI,
    functionName: "swapFeeModule",
    query: { enabled: true },
  });

  const isZeroToOne = useMemo(() => {
    if (!poolToken0) return sellToken === "PURR";
    return (
      tokenIn.address.toLowerCase() === (poolToken0 as string).toLowerCase()
    );
  }, [poolToken0, tokenIn.address, sellToken]);

  const feeModuleAddress = useMemo(() => {
    const mod = (poolSwapFeeModule as string | undefined) || "";
    const isZero = !mod || mod === "0x0000000000000000000000000000000000000000";
    return (isZero ? SWAP_FEE_MODULE_FALLBACK : mod) as `0x${string}`;
  }, [poolSwapFeeModule]);

  // Vault address (this is what BOTH contracts use)
  const { data: vaultAddr } = useReadContract({
    address: ADDRESSES.POOL,
    abi: SOVEREIGN_POOL_ABI,
    functionName: "sovereignVault",
    query: { enabled: true },
  });

  // On-chain decimals (don’t trust TOKENS config)
  const { data: usdcDecOnchain } = useReadContract({
    address: TOKENS.USDC.address,
    abi: DECIMALS_ABI,
    functionName: "decimals",
    query: { enabled: true },
  });

  const { data: purrDecOnchain } = useReadContract({
    address: TOKENS.PURR.address,
    abi: DECIMALS_ABI,
    functionName: "decimals",
    query: { enabled: true },
  });

  // Vault balances (raw)
  const { data: vaultUsdcRaw } = useReadContract({
    address: TOKENS.USDC.address,
    abi: BALANCE_OF_ABI,
    functionName: "balanceOf",
    args: vaultAddr ? [vaultAddr as `0x${string}`] : undefined,
    query: { enabled: !!vaultAddr },
  });

  const { data: vaultPurrRaw } = useReadContract({
    address: TOKENS.PURR.address,
    abi: BALANCE_OF_ABI,
    functionName: "balanceOf",
    args: vaultAddr ? [vaultAddr as `0x${string}`] : undefined,
    query: { enabled: !!vaultAddr },
  });

  // ALM spot px (raw USDC-per-PURR scaled)
  const { data: spotPxRaw } = useReadContract({
    address: (poolAlm as `0x${string}`) || undefined,
    abi: ALM_SPOT_ABI,
    functionName: "getSpotPriceUSDCperPURR",
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
    ? formatUnits(balanceRaw, tokenIn.decimals)
    : undefined;

  // Allowance
  const { data: allowance, refetch: refetchAllowance } = useReadContract({
    address: tokenIn.address,
    abi: ERC20_ABI,
    functionName: "allowance",
    args: address ? [address, ADDRESSES.POOL] : undefined,
    query: {
      enabled: !!address && amountInParsed > 0n,
      staleTime: 0,
      gcTime: 0,
    },
    scopeKey: `allowance-${sellToken}-${approvalNonce}`,
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

  const feeBips = useMemo(() => extractFeeBips(feeDataRaw), [feeDataRaw]);
  const feePct = useMemo(() => Number(feeBips) / 100, [feeBips]);

  const amountInMinus = useMemo(() => {
    if (amountInParsed <= 0n) return 0n;
    return amountInMinusFee(amountInParsed, feeBips);
  }, [amountInParsed, feeBips]);

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
              feeInBips: feeBips,
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
    if (quotedOut > 0n) setAmountOut(formatUnits(quotedOut, tokenOut.decimals));
    else setAmountOut("");
  }, [amountIn, amountInParsed, quotedOut, tokenOut.decimals]);

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
    if (!vaultAddr) return;

    const usdcDec = 6;
    const purrDec = 5;

    const vu = vaultUsdcRaw ?? 0n;
    const vp = vaultPurrRaw ?? 0n;

    const spot = spotPxRaw ?? 0n;

    // Interpreting spot as "USDC per 1 PURR" scaled by 10^USDCdec (your ALM assumption)
    const spotAsNumber = usdcDec > 0 ? Number(spot) / 10 ** usdcDec : NaN;

    // Also show implied "PURR per 1 USDC" (reciprocal)
    const impliedPurrPerUsdc =
      spotAsNumber && spotAsNumber > 0 ? 1 / spotAsNumber : NaN;

    console.groupCollapsed("[SWAP DEBUG]");
    console.log("Pool:", ADDRESSES.POOL);
    console.log("ALM:", poolAlm);
    console.log("FeeModule:", feeModuleAddress);
    console.log("Vault (pool.sovereignVault()):", vaultAddr);

    console.log(
      "USDC address:",
      TOKENS.USDC.address,
      "decimals(onchain):",
      usdcDec,
      "decimals(config):",
      TOKENS.USDC.decimals,
    );
    console.log(
      "PURR address:",
      TOKENS.PURR.address,
      "decimals(onchain):",
      purrDec,
      "decimals(config):",
      TOKENS.PURR.decimals,
    );

    console.log(
      "Vault USDC raw:",
      vu.toString(),
      "formatted:",
      usdcDec ? formatUnits(vu, usdcDec) : "(no dec)",
    );
    console.log(
      "Vault PURR raw:",
      vp.toString(),
      "formatted:",
      purrDec ? formatUnits(vp, purrDec) : "(no dec)",
    );

    console.log("Spot px raw (PURR per USDC scaled):", spot.toString());
    console.log("Spot px interpreted (PURR/USDC):", spotAsNumber);
    console.log("Implied PURR/USDC:", spotAsNumber);

    // For your specific test: 0.001 USDC -> expected ~0.0047 PURR if 1 USDC = 4.7 PURR
    if (amountInParsed > 0n && usdcDec > 0 && purrDec > 0 && spot > 0n) {
      // expected out using your ALM formula:
      // out = amountInRaw * 10^purrDec / spotPxRaw
      const expectedOutRaw = (amountInParsed * BigInt(10 ** purrDec)) / spot;
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
        formatUnits(expectedOutRaw, purrDec),
      );
    }

    console.groupEnd();
  }, [
    vaultAddr,
    poolAlm,
    feeModuleAddress,
    usdcDecOnchain,
    purrDecOnchain,
    vaultUsdcRaw,
    vaultPurrRaw,
    spotPxRaw,
    amountInParsed,
  ]);

  const handleFlip = () => {
    setSellToken(buyToken);
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
        args: [ADDRESSES.POOL, maxUint256],
      });
      setTxHash(hash);
    } catch (err) {
      console.error("Approve failed:", err);
    }
  };

  const handleSwap = async () => {
    if (!address || !amountInParsed) return;

    const deadline = BigInt(Math.floor(Date.now() / 1000) + 60 * 20);
    const slippageBps = Math.floor(Number(slippage) * 100);

    const minOut =
      quotedOut > 0n
        ? (quotedOut * BigInt(10_000 - slippageBps)) / 10_000n
        : 0n;

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
        address: ADDRESSES.POOL,
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

    if (amountInParsed > 0n && (feeLoading || quoteLoading))
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
              <span>Fee (dynamic)</span>
              <span className="text-[var(--foreground)]">
                {feePct.toFixed(2)}%{" "}
                <span className="text-[var(--text-muted)]">
                  ({feeBips.toString()} bips)
                </span>
              </span>
            </div>

            <div className="flex items-center justify-between gap-3 text-[var(--text-muted)] mt-2">
              <span>Slippage</span>
              <span className="text-[var(--foreground)]">{slippage}%</span>
            </div>
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
