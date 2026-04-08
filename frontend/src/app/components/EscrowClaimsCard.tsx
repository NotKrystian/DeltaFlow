"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { useAccount, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { ADDRESSES, HEDGE_ESCROW_ABI } from "@/contracts";

const API_BASE =
  typeof process !== "undefined"
    ? process.env.NEXT_PUBLIC_BACKEND_URL ?? "http://127.0.0.1:8000"
    : "http://127.0.0.1:8000";

type EscrowTradeRow = {
  id: number;
  user?: string;
  claimed?: boolean;
  canClaimBuy?: boolean;
  limitPx?: number;
  sz?: number;
  error?: string;
};

export default function EscrowClaimsCard() {
  const { address, isConnected } = useAccount();
  const [rows, setRows] = useState<Record<number, EscrowTradeRow>>({});
  const [loading, setLoading] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  const escrowConfigured = useMemo(
    () => ADDRESSES.HEDGE_ESCROW !== "0x0000000000000000000000000000000000000000",
    []
  );

  const fetchTrades = useCallback(async () => {
    if (!escrowConfigured) return;
    setLoading(true);
    setErr(null);
    try {
      const r = await fetch(`${API_BASE}/escrow/trades`);
      const j = await r.json();
      if (!j.ok) {
        setErr(j.reason ?? "escrow unavailable");
        return;
      }
      setRows(j.trades ?? {});
    } catch (e: unknown) {
      setErr(e instanceof Error ? e.message : "fetch failed");
    } finally {
      setLoading(false);
    }
  }, [escrowConfigured]);

  useEffect(() => {
    fetchTrades();
    const t = setInterval(fetchTrades, 5000);
    return () => clearInterval(t);
  }, [fetchTrades]);

  const { writeContract, data: hash, isPending, error: writeErr, reset } = useWriteContract();
  const { isLoading: confirming, isSuccess } = useWaitForTransactionReceipt({ hash });

  useEffect(() => {
    if (isSuccess) {
      reset();
      fetchTrades();
    }
  }, [isSuccess, reset, fetchTrades]);

  const mine = useMemo(() => {
    if (!address) return [];
    return Object.values(rows).filter(
      (x) =>
        x.user &&
        address.toLowerCase() === String(x.user).toLowerCase() &&
        !x.error
    );
  }, [rows, address]);

  const claim = (id: number) => {
    writeContract({
      address: ADDRESSES.HEDGE_ESCROW,
      abi: HEDGE_ESCROW_ABI,
      functionName: "claimPurrBuy",
      args: [BigInt(id)],
    });
  };

  if (!escrowConfigured) {
    return (
      <div className="rounded-2xl border border-[var(--border)] bg-[var(--card)] p-6 text-sm text-[var(--text-muted)]">
        Set <code className="text-xs">NEXT_PUBLIC_HEDGE_ESCROW</code> to the deployed{" "}
        <code className="text-xs">HedgeEscrow</code> address to track CoreWriter hedges and claims.
      </div>
    );
  }

  return (
    <div className="space-y-4 rounded-2xl border border-[var(--border)] bg-[var(--card)] p-6">
      <div className="flex items-center justify-between gap-2">
        <h2 className="text-lg font-semibold text-[var(--foreground)]">Hedge escrow (CoreWriter)</h2>
        <button
          type="button"
          onClick={() => fetchTrades()}
          className="text-xs px-3 py-1.5 rounded-lg bg-[var(--accent)] text-white"
        >
          {loading ? "…" : "Refresh"}
        </button>
      </div>
      <p className="text-sm text-[var(--text-muted)]">
        Trades are opened on-chain via <code className="text-xs">HedgeEscrow</code> → CoreWriter. This panel uses the
        backend snapshot (precompile + <code className="text-xs">canClaimBuy</code>) so you know when to call{" "}
        <code className="text-xs">claimPurrBuy</code>.
      </p>
      {err && <p className="text-sm text-red-400">{err}</p>}
      {writeErr && <p className="text-sm text-red-400">{writeErr.message}</p>}

      {!isConnected && (
        <p className="text-sm text-[var(--text-muted)]">Connect a wallet to see your trades.</p>
      )}

      {isConnected && mine.length === 0 && !loading && (
        <p className="text-sm text-[var(--text-muted)]">No escrow trades for this wallet.</p>
      )}

      <ul className="space-y-3">
        {mine.map((t) => (
          <li
            key={t.id}
            className="flex flex-wrap items-center justify-between gap-2 rounded-xl border border-[var(--border)] p-4"
          >
            <div className="text-sm">
              <div className="font-medium text-[var(--foreground)]">Trade #{t.id}</div>
              <div className="text-[var(--text-muted)] text-xs mt-1">
                limitPx×1e8={t.limitPx ?? "—"} · sz×1e8={t.sz ?? "—"} ·{" "}
                {t.claimed ? "claimed" : t.canClaimBuy ? "ready to claim" : "awaiting fill"}
              </div>
            </div>
            {t.canClaimBuy && !t.claimed && (
              <button
                type="button"
                disabled={isPending || confirming}
                onClick={() => claim(t.id)}
                className="text-sm px-4 py-2 rounded-lg bg-emerald-600 text-white disabled:opacity-50"
              >
                {isPending || confirming ? "Confirming…" : "Claim PURR"}
              </button>
            )}
          </li>
        ))}
      </ul>

      {hash && (
        <p className="text-xs text-[var(--text-muted)] break-all">
          Tx: {hash}
        </p>
      )}
    </div>
  );
}
