"use client";

import Link from "next/link";
import { useMemo, useState } from "react";
import {
  useAccount,
  useReadContract,
  useWriteContract,
  useWaitForTransactionReceipt,
} from "wagmi";
import { parseUnits, formatUnits } from "viem";
import { Plus, Loader2, ChevronDown, ArrowRight } from "lucide-react";
import { ERC20_ABI } from "@/contracts";
import { useMarket } from "@/app/context/MarketContext";
import type { TokenMeta } from "@/app/lib/marketConfig";
import { useMarketEvmDecimals } from "@/app/hooks/useMarketEvmDecimals";

// ═══════════════════════════════════════════════════════════════
// Token Input Component
// ═══════════════════════════════════════════════════════════════
function TokenInput({
  label,
  token,
  amount,
  onAmountChange,
  balance,
  onMaxClick,
}: {
  label: string;
  token: TokenMeta;
  amount: string;
  onAmountChange?: (value: string) => void;
  balance?: string;
  onMaxClick?: () => void;
}) {
  return (
    <div className="rounded-2xl bg-[var(--card)] border border-[var(--border)] p-4">
      <div className="flex justify-between text-sm text-[var(--text-muted)] mb-2">
        <span>{label}</span>
        {balance && (
          <span className="flex items-center gap-1">
            Balance: {balance}
            {onMaxClick && (
              <button
                onClick={onMaxClick}
                className="text-[var(--accent)] font-medium hover:text-[var(--accent-hover)] ml-1"
                type="button"
              >
                MAX
              </button>
            )}
          </span>
        )}
      </div>

      <div className="flex items-center gap-3">
        <input
          type="text"
          value={amount}
          onChange={(e) =>
            onAmountChange?.(e.target.value.replace(/[^0-9.]/g, ""))
          }
          placeholder="0"
          className="bg-transparent text-3xl font-medium text-[var(--foreground)] placeholder-[var(--text-secondary)] outline-none flex-1 min-w-0"
          inputMode="decimal"
        />
        <button
          className="flex items-center gap-2 bg-[var(--input-bg)] px-3 py-2 rounded-xl font-medium text-[var(--foreground)] hover:bg-[var(--card-hover)] border border-[var(--border)]"
          type="button"
        >
          <div className="w-6 h-6 rounded-full bg-[var(--accent-muted)] flex items-center justify-center text-xs font-bold text-[var(--accent)]">
            {token.symbol[0]}
          </div>
          {token.symbol}
          <ChevronDown size={16} className="text-[var(--text-muted)]" />
        </button>
      </div>
    </div>
  );
}

// ═══════════════════════════════════════════════════════════════
// Main "Deposit to Vault" Card (plain ERC20 transfers)
// ═══════════════════════════════════════════════════════════════
export default function AddLiquidityCard() {
  const { address, isConnected } = useAccount();
  const { market } = useMarket();
  const VAULT_ADDRESS = market.vault as `0x${string}`;

  const [amount0, setAmount0] = useState("");
  const [amount1, setAmount1] = useState("");

  // We'll track 2 separate tx hashes (one for each token transfer)
  const [txHash0, setTxHash0] = useState<`0x${string}` | undefined>();
  const [txHash1, setTxHash1] = useState<`0x${string}` | undefined>();

  const token0 = market.tokens.BASE;
  const token1 = market.tokens.USDC;
  const { baseDecimals, usdcDecimals } = useMarketEvmDecimals();

  // Parse amounts
  const amount0Parsed = useMemo(() => {
    if (!amount0 || isNaN(Number(amount0))) return 0n;
    try {
      return parseUnits(amount0, baseDecimals);
    } catch {
      return 0n;
    }
  }, [amount0, baseDecimals]);

  const amount1Parsed = useMemo(() => {
    if (!amount1 || isNaN(Number(amount1))) return 0n;
    try {
      return parseUnits(amount1, usdcDecimals);
    } catch {
      return 0n;
    }
  }, [amount1, usdcDecimals]);

  // Read balances
  const { data: balance0Raw, refetch: refetchBalance0 } = useReadContract({
    address: token0.address,
    abi: ERC20_ABI,
    functionName: "balanceOf",
    args: address ? [address] : undefined,
    query: { enabled: !!address },
  });

  const { data: balance1Raw, refetch: refetchBalance1 } = useReadContract({
    address: token1.address,
    abi: ERC20_ABI,
    functionName: "balanceOf",
    args: address ? [address] : undefined,
    query: { enabled: !!address },
  });

  const balance0 = balance0Raw
    ? formatUnits(balance0Raw, baseDecimals)
    : undefined;
  const balance1 = balance1Raw
    ? formatUnits(balance1Raw, usdcDecimals)
    : undefined;

  // Write
  const { writeContractAsync, isPending } = useWriteContract();

  // Wait for receipts
  const { isLoading: confirming0, isSuccess: success0 } =
    useWaitForTransactionReceipt({
      hash: txHash0,
    });

  const { isLoading: confirming1, isSuccess: success1 } =
    useWaitForTransactionReceipt({
      hash: txHash1,
    });

  const isLoading = isPending || confirming0 || confirming1;

  const handleMax0 = () => {
    if (balance0) setAmount0(balance0);
  };

  const handleMax1 = () => {
    if (balance1) setAmount1(balance1);
  };

  // Do two transfers sequentially (PURR then USDC) if the user entered both.
  const handleSendToVault = async () => {
    if (!address) return;

    try {
      // Transfer token0 if amount > 0
      if (amount0Parsed > 0n) {
        const hash0 = await writeContractAsync({
          address: token0.address,
          abi: ERC20_ABI,
          functionName: "transfer",
          args: [VAULT_ADDRESS, amount0Parsed],
        });
        setTxHash0(hash0);
        // optional: wait for confirmation before sending the second
        // (keeps UX simple / predictable)
        // NOTE: wagmi receipt hook will also confirm, but we can proceed anyway.
      }

      // Transfer token1 if amount > 0
      if (amount1Parsed > 0n) {
        const hash1 = await writeContractAsync({
          address: token1.address,
          abi: ERC20_ABI,
          functionName: "transfer",
          args: [VAULT_ADDRESS, amount1Parsed],
        });
        setTxHash1(hash1);
      }

      // Refresh balances
      refetchBalance0?.();
      refetchBalance1?.();
    } catch (err) {
      console.error("Transfer to vault failed:", err);
    }
  };

  const buttonState = useMemo(() => {
    if (!isConnected)
      return { text: "Connect Wallet", disabled: true as const };

    const hasAny =
      (amount0 && Number(amount0) > 0) || (amount1 && Number(amount1) > 0);

    if (!hasAny) return { text: "Enter amounts", disabled: true as const };
    if (isLoading) return { text: "Confirming...", disabled: true as const };

    return {
      text: "Send to Vault",
      disabled: false as const,
      action: handleSendToVault,
    };
  }, [isConnected, amount0, amount1, isLoading]);

  return (
    <div className="w-full space-y-4">
      <Link
        href="/lp"
        className="flex items-center justify-between gap-3 p-4 rounded-2xl bg-[var(--accent-muted)] border border-[var(--border)] text-sm text-[var(--foreground)] hover:border-[var(--accent)] transition group"
      >
        <span>
          <strong className="text-[var(--accent)]">Mint DFLP</strong> — use the
          LP dashboard for <code>depositLP</code>, share %, and fee surplus
          view.
        </span>
        <ArrowRight
          size={18}
          className="shrink-0 text-[var(--accent)] group-hover:translate-x-0.5 transition"
        />
      </Link>

      <div className="bg-[var(--card)] rounded-3xl border border-[var(--border)] p-4 shadow-lg glow-green">
        <h2 className="text-lg font-semibold text-[var(--foreground)] mb-1">
          Quick transfer to vault
        </h2>
        <p className="text-xs text-[var(--text-muted)] mb-3">
          Plain ERC-20 transfers increase vault balance but do{" "}
          <strong>not</strong> mint LP shares. Prefer{" "}
          <Link href="/lp" className="text-[var(--accent)] underline">
            /lp
          </Link>
          .
        </p>

        {/* Token 0 */}
        <TokenInput
          label={market.baseSymbol}
          token={token0}
          amount={amount0}
          onAmountChange={setAmount0}
          balance={balance0}
          onMaxClick={handleMax0}
        />

        {/* Plus icon */}
        <div className="flex justify-center -my-2 relative z-10">
          <div className="bg-[var(--card)] p-2 rounded-xl border border-[var(--border)]">
            <Plus size={20} className="text-[var(--accent)]" />
          </div>
        </div>

        {/* Token 1 */}
        <TokenInput
          label="USDC"
          token={token1}
          amount={amount1}
          onAmountChange={setAmount1}
          balance={balance1}
          onMaxClick={handleMax1}
        />

        {/* Action button */}
        <button
          onClick={buttonState.action}
          disabled={buttonState.disabled}
          className={`w-full mt-4 py-4 rounded-2xl font-semibold text-lg transition ${
            buttonState.disabled
              ? "bg-[var(--input-bg)] text-[var(--text-secondary)] cursor-not-allowed"
              : "bg-[var(--accent)] text-white hover:bg-[var(--accent-hover)] glow-green-strong"
          }`}
          type="button"
        >
          <span className="flex items-center justify-center gap-2">
            {isLoading && <Loader2 size={20} className="animate-spin" />}
            {buttonState.text}
          </span>
        </button>

        {/* Success messages */}
        {(success0 || success1) && (
          <div className="mt-4 space-y-2">
            {success0 && txHash0 && (
              <div className="p-3 rounded-xl bg-[var(--accent-muted)] border border-[var(--accent)] text-center">
                <p className="text-[var(--accent)] text-sm">
                  {market.baseSymbol} transfer confirmed.{" "}
                  <a
                    href={`https://explorer.hyperliquid-testnet.xyz/tx/${txHash0}`}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="underline font-medium"
                  >
                    View
                  </a>
                </p>
              </div>
            )}
            {success1 && txHash1 && (
              <div className="p-3 rounded-xl bg-[var(--accent-muted)] border border-[var(--accent)] text-center">
                <p className="text-[var(--accent)] text-sm">
                  USDC transfer confirmed.{" "}
                  <a
                    href={`https://explorer.hyperliquid-testnet.xyz/tx/${txHash1}`}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="underline font-medium"
                  >
                    View
                  </a>
                </p>
              </div>
            )}
          </div>
        )}
      </div>
    </div>
  );
}
