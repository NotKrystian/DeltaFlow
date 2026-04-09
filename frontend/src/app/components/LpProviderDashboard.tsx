"use client";

import { useCallback, useMemo, useState } from "react";
import {
  useAccount,
  usePublicClient,
  useReadContract,
  useWriteContract,
  useWaitForTransactionReceipt,
} from "wagmi";
import { formatUnits, parseUnits } from "viem";
import {
  Wallet,
  PieChart,
  Coins,
  Loader2,
  RefreshCw,
  ArrowDownCircle,
  ArrowUpCircle,
  Info,
} from "lucide-react";
import {
  ADDRESSES,
  ERC20_ABI,
  SOVEREIGN_VAULT_ABI,
  TOKENS,
} from "@/contracts";
import { useVaultLp } from "../hooks/useVaultLp";

function Stat({
  label,
  value,
  sub,
}: {
  label: string;
  value: string;
  sub?: string;
}) {
  return (
    <div className="rounded-2xl bg-[var(--input-bg)] border border-[var(--border)] p-4">
      <p className="text-xs uppercase tracking-wide text-[var(--text-muted)] mb-1">
        {label}
      </p>
      <p className="text-lg font-semibold text-[var(--foreground)] tabular-nums">
        {value}
      </p>
      {sub && (
        <p className="text-xs text-[var(--text-secondary)] mt-1">{sub}</p>
      )}
    </div>
  );
}

export default function LpProviderDashboard() {
  const { address, isConnected } = useAccount();
  const vault = ADDRESSES.VAULT;
  const {
    lpSymbol,
    lpDecimals,
    poolValueUsdc,
    userShares,
    userValueUsdc,
    userSharePct,
    surplusUsdc,
    userSurplusAttribution,
    hasFeeSurplus,
    totalSupply,
    formatUsdc,
    formatPurr,
    formatShares,
    isLoading,
    refetch,
    reserveUsdc,
    reservePurr,
  } = useVaultLp();

  const [depUsdc, setDepUsdc] = useState("");
  const [depPurr, setDepPurr] = useState("");
  const [wdPct, setWdPct] = useState("");
  const [txHash, setTxHash] = useState<`0x${string}` | undefined>();

  const { data: usdcAllowance, refetch: refetchAllowUsdc } = useReadContract({
    address: TOKENS.USDC.address,
    abi: ERC20_ABI,
    functionName: "allowance",
    args: address ? [address, vault] : undefined,
    query: { enabled: !!address },
  });
  const { data: purrAllowance, refetch: refetchAllowPurr } = useReadContract({
    address: TOKENS.PURR.address,
    abi: ERC20_ABI,
    functionName: "allowance",
    args: address ? [address, vault] : undefined,
    query: { enabled: !!address },
  });

  const depUsdcParsed = useMemo(() => {
    try {
      return depUsdc ? parseUnits(depUsdc, TOKENS.USDC.decimals) : 0n;
    } catch {
      return 0n;
    }
  }, [depUsdc]);
  const depPurrParsed = useMemo(() => {
    try {
      return depPurr ? parseUnits(depPurr, TOKENS.PURR.decimals) : 0n;
    } catch {
      return 0n;
    }
  }, [depPurr]);

  const withdrawShares = useMemo(() => {
    if (!userShares || !wdPct) return 0n;
    const p = parseFloat(wdPct);
    if (!Number.isFinite(p) || p <= 0 || p > 100) return 0n;
    const bps = Math.round(p * 100);
    return (userShares * BigInt(bps)) / 10000n;
  }, [userShares, wdPct]);

  const publicClient = usePublicClient();
  const { writeContractAsync, isPending } = useWriteContract();
  const { isLoading: confirming } = useWaitForTransactionReceipt({
    hash: txHash,
  });

  const busy = isPending || confirming;

  const needsUsdcApprove =
    depUsdcParsed > 0n &&
    (usdcAllowance === undefined || usdcAllowance < depUsdcParsed);
  const needsPurrApprove =
    depPurrParsed > 0n &&
    (purrAllowance === undefined || purrAllowance < depPurrParsed);

  const refresh = useCallback(() => {
    refetch();
    refetchAllowUsdc();
    refetchAllowPurr();
  }, [refetch, refetchAllowUsdc, refetchAllowPurr]);

  const handleApproveAndDeposit = async () => {
    if (!address || (depUsdcParsed === 0n && depPurrParsed === 0n)) return;
    if (!publicClient) return;
    try {
      if (needsUsdcApprove && depUsdcParsed > 0n) {
        const h = await writeContractAsync({
          address: TOKENS.USDC.address,
          abi: ERC20_ABI,
          functionName: "approve",
          args: [vault, depUsdcParsed],
        });
        setTxHash(h);
        await publicClient.waitForTransactionReceipt({ hash: h });
      }
      if (needsPurrApprove && depPurrParsed > 0n) {
        const h = await writeContractAsync({
          address: TOKENS.PURR.address,
          abi: ERC20_ABI,
          functionName: "approve",
          args: [vault, depPurrParsed],
        });
        setTxHash(h);
        await publicClient.waitForTransactionReceipt({ hash: h });
      }
      const h = await writeContractAsync({
        address: vault,
        abi: SOVEREIGN_VAULT_ABI,
        functionName: "depositLP",
        args: [depUsdcParsed, depPurrParsed, 0n],
      });
      setTxHash(h);
      await publicClient.waitForTransactionReceipt({ hash: h });
      setDepUsdc("");
      setDepPurr("");
      refresh();
    } catch (e) {
      console.error(e);
    }
  };

  const handleWithdraw = async () => {
    if (!address || withdrawShares === 0n || !publicClient) return;
    try {
      const h = await writeContractAsync({
        address: vault,
        abi: SOVEREIGN_VAULT_ABI,
        functionName: "withdrawLP",
        args: [withdrawShares, 0n, 0n],
      });
      setTxHash(h);
      await publicClient.waitForTransactionReceipt({ hash: h });
      setWdPct("");
      refresh();
    } catch (e) {
      console.error(e);
    }
  };

  return (
    <div className="w-full max-w-3xl mx-auto space-y-8">
      <div className="flex items-start justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold text-[var(--foreground)] tracking-tight">
            LP provider
          </h1>
          <p className="text-[var(--text-muted)] mt-1 text-sm max-w-lg">
            DeltaFlow LP ({lpSymbol}) is the vault share token. Deposits mint
            shares pro-rata to pool value; swap fees build the Fee Surplus buffer
            (shown below as protocol-side accounting).
          </p>
        </div>
        <button
          type="button"
          onClick={() => refresh()}
          className="flex items-center gap-2 px-3 py-2 rounded-xl bg-[var(--card)] border border-[var(--border)] text-[var(--text-muted)] hover:text-[var(--foreground)]"
        >
          <RefreshCw size={16} className={isLoading ? "animate-spin" : ""} />
          Refresh
        </button>
      </div>

      {/* Overview */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-3">
        <Stat
          label="Pool TVL (USDC)"
          value={
            poolValueUsdc !== undefined ? formatUsdc(poolValueUsdc) : isLoading ? "…" : "—"
          }
          sub="USDC + PURR at ALM spot"
        />
        <Stat
          label={`Your ${lpSymbol}`}
          value={
            userShares && userShares > 0n
              ? formatShares(userShares)
              : isConnected
                ? "0"
                : "—"
          }
          sub={
            userSharePct !== undefined
              ? `${userSharePct.toFixed(2)}% of supply`
              : undefined
          }
        />
        <Stat
          label="Est. position (USDC)"
          value={
            userValueUsdc !== undefined
              ? formatUsdc(userValueUsdc)
              : isConnected
                ? "0.00"
                : "—"
          }
          sub="Pro-rata vault reserves"
        />
        <Stat
          label="Fee surplus (USDC)"
          value={
            hasFeeSurplus && surplusUsdc !== undefined
              ? formatUsdc(surplusUsdc)
              : "—"
          }
          sub={
            userSurplusAttribution !== undefined && userSurplusAttribution > 0n
              ? `Your pro-rata ~${formatUsdc(userSurplusAttribution)}`
              : "DeltaFlow buffer"
          }
        />
      </div>

      <div className="flex items-start gap-2 p-3 rounded-xl bg-[var(--accent-muted)] border border-[var(--border)] text-xs text-[var(--text-muted)]">
        <Info size={16} className="shrink-0 mt-0.5 text-[var(--accent)]" />
        <p>
          Pro-rata surplus is illustrative: surplus accrues in{" "}
          <code className="text-[var(--foreground)]">FeeSurplus</code> as a risk
          buffer, not an automatic claim. Your LP value tracks vault reserves
          (USDC + PURR + allocated Core USDC) via{" "}
          <code className="text-[var(--foreground)]">getReserves</code>.
        </p>
      </div>

      {!isConnected ? (
        <div className="rounded-3xl border border-[var(--border)] bg-[var(--card)] p-10 text-center text-[var(--text-muted)]">
          Connect a wallet to deposit or withdraw LP.
        </div>
      ) : (
        <div className="grid md:grid-cols-2 gap-6">
          {/* Deposit */}
          <div className="rounded-3xl border border-[var(--border)] bg-[var(--card)] p-6 shadow-lg glow-green">
            <div className="flex items-center gap-2 mb-4 text-[var(--foreground)] font-semibold">
              <ArrowDownCircle className="text-[var(--accent)]" size={22} />
              Mint {lpSymbol}
            </div>
            <p className="text-xs text-[var(--text-muted)] mb-4">
              Calls <code>depositLP</code> on the vault. First deposit must be
              two-sided; later you can single-side with ALM pricing.
            </p>
            <label className="block text-sm text-[var(--text-muted)] mb-1">
              USDC
            </label>
            <input
              value={depUsdc}
              onChange={(e) =>
                setDepUsdc(e.target.value.replace(/[^0-9.]/g, ""))
              }
              placeholder="0"
              className="w-full mb-3 px-4 py-3 rounded-xl bg-[var(--input-bg)] border border-[var(--border)] text-[var(--foreground)]"
            />
            <label className="block text-sm text-[var(--text-muted)] mb-1">
              PURR
            </label>
            <input
              value={depPurr}
              onChange={(e) =>
                setDepPurr(e.target.value.replace(/[^0-9.]/g, ""))
              }
              placeholder="0"
              className="w-full mb-4 px-4 py-3 rounded-xl bg-[var(--input-bg)] border border-[var(--border)] text-[var(--foreground)]"
            />
            <button
              type="button"
              disabled={
                busy ||
                (depUsdcParsed === 0n && depPurrParsed === 0n)
              }
              onClick={handleApproveAndDeposit}
              className="w-full py-3 rounded-xl font-medium bg-[var(--accent)] text-white hover:bg-[var(--accent-hover)] disabled:opacity-50 flex justify-center gap-2"
            >
              {busy ? (
                <Loader2 className="animate-spin" size={20} />
              ) : (
                <Coins size={20} />
              )}
              {needsUsdcApprove || needsPurrApprove
                ? "Approve & deposit"
                : "Deposit"}
            </button>
          </div>

          {/* Withdraw */}
          <div className="rounded-3xl border border-[var(--border)] bg-[var(--card)] p-6 shadow-lg">
            <div className="flex items-center gap-2 mb-4 text-[var(--foreground)] font-semibold">
              <ArrowUpCircle className="text-[var(--danger)]" size={22} />
              Burn {lpSymbol}
            </div>
            <p className="text-xs text-[var(--text-muted)] mb-4">
              <code>withdrawLP</code> — requires enough EVM USDC for your USDC
              leg (strategist may need to deallocate).
            </p>
            <label className="block text-sm text-[var(--text-muted)] mb-1">
              Percent of your shares
            </label>
            <input
              value={wdPct}
              onChange={(e) =>
                setWdPct(e.target.value.replace(/[^0-9.]/g, ""))
              }
              placeholder="e.g. 25"
              className="w-full mb-2 px-4 py-3 rounded-xl bg-[var(--input-bg)] border border-[var(--border)] text-[var(--foreground)]"
            />
            <p className="text-xs text-[var(--text-secondary)] mb-4">
              {withdrawShares > 0n
                ? `${formatShares(withdrawShares)} ${lpSymbol}`
                : "—"}
            </p>
            <button
              type="button"
              disabled={busy || withdrawShares === 0n}
              onClick={handleWithdraw}
              className="w-full py-3 rounded-xl font-medium bg-[var(--danger)]/90 text-white hover:opacity-95 disabled:opacity-40 flex justify-center gap-2"
            >
              {busy ? (
                <Loader2 className="animate-spin" size={20} />
              ) : (
                <Wallet size={20} />
              )}
              Withdraw
            </button>
          </div>
        </div>
      )}

      {/* Reserves detail */}
      <div className="rounded-3xl border border-[var(--border)] bg-[var(--card)] p-6">
        <h3 className="text-sm font-semibold text-[var(--foreground)] mb-4 flex items-center gap-2">
          <PieChart size={18} className="text-[var(--accent)]" />
          Vault reserves (raw)
        </h3>
        <div className="grid sm:grid-cols-2 gap-3 text-sm">
          <div className="flex justify-between py-2 border-b border-[var(--border)]">
            <span className="text-[var(--text-muted)]">USDC + allocated</span>
            <span className="font-mono text-[var(--foreground)]">
              {reserveUsdc !== undefined ? formatUsdc(reserveUsdc) : "—"}
            </span>
          </div>
          <div className="flex justify-between py-2 border-b border-[var(--border)]">
            <span className="text-[var(--text-muted)]">PURR</span>
            <span className="font-mono text-[var(--foreground)]">
              {reservePurr !== undefined ? formatPurr(reservePurr) : "—"}
            </span>
          </div>
          <div className="flex justify-between py-2 border-b border-[var(--border)]">
            <span className="text-[var(--text-muted)]">Total {lpSymbol} supply</span>
            <span className="font-mono text-[var(--foreground)]">
              {totalSupply !== undefined
                ? formatUnits(totalSupply, lpDecimals)
                : "—"}
            </span>
          </div>
          <div className="flex justify-between py-2 border-b border-[var(--border)]">
            <span className="text-[var(--text-muted)]">Fee surplus</span>
            <span className="font-mono text-[var(--foreground)]">
              {hasFeeSurplus && surplusUsdc !== undefined
                ? formatUsdc(surplusUsdc)
                : "Not configured"}
            </span>
          </div>
        </div>
      </div>
    </div>
  );
}
