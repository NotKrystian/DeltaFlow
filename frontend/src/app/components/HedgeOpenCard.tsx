"use client";

import { useEffect, useMemo, useState } from "react";
import {
  useAccount,
  useReadContract,
  useWriteContract,
  useWaitForTransactionReceipt,
} from "wagmi";
import { parseUnits, maxUint256 } from "viem";
import { ADDRESSES, ERC20_ABI, HEDGE_ESCROW_ABI } from "@/contracts";

const HL_INFO =
  typeof process !== "undefined"
    ? process.env.NEXT_PUBLIC_HL_INFO_URL ?? "https://api.hyperliquid-testnet.xyz/info"
    : "https://api.hyperliquid-testnet.xyz/info";

type SpotMetaUniverse = {
  name: string;
  index: number;
  tokens: [number, number];
};

type TokenMeta = { name: string; szDecimals: number; weiDecimals: number };

type SpotMeta = {
  universe?: SpotMetaUniverse[];
  tokens?: TokenMeta[];
};

async function fetchPurrSpotSzDecimals(): Promise<number | null> {
  try {
    const r = await fetch(HL_INFO, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ type: "spotMeta" }),
    });
    const j: SpotMeta = await r.json();
    const pair = j.universe?.find((u) => u.name === "PURR/USDC" || u.name.startsWith("PURR/"));
    if (!pair || !j.tokens?.length) return null;
    const baseIdx = pair.tokens[0];
    const dec = j.tokens[baseIdx]?.szDecimals;
    return typeof dec === "number" ? dec : null;
  } catch {
    return null;
  }
}

export default function HedgeOpenCard() {
  const { address, isConnected } = useAccount();
  const [usdcIn, setUsdcIn] = useState("");
  const [limitPrice, setLimitPrice] = useState(""); // USDC per 1 PURR
  const [sizePurr, setSizePurr] = useState("");
  const [tif, setTif] = useState<1 | 2 | 3>(3); // Ioc default
  const [cloidStr, setCloidStr] = useState("");
  const [szDecimalsHint, setSzDecimalsHint] = useState<number | null>(null);

  const escrowConfigured = useMemo(
    () => ADDRESSES.HEDGE_ESCROW !== "0x0000000000000000000000000000000000000000",
    []
  );

  useEffect(() => {
    fetchPurrSpotSzDecimals().then(setSzDecimalsHint);
  }, []);

  const usdcAmountWei = useMemo(() => {
    try {
      if (!usdcIn.trim()) return 0n;
      return parseUnits(usdcIn, 6);
    } catch {
      return 0n;
    }
  }, [usdcIn]);

  const { data: allowance, refetch: refetchAllowance } = useReadContract({
    address: ADDRESSES.USDC,
    abi: ERC20_ABI,
    functionName: "allowance",
    args:
      address && escrowConfigured
        ? [address, ADDRESSES.HEDGE_ESCROW]
        : undefined,
    query: {
      enabled: Boolean(address && escrowConfigured),
    },
  });

  const { writeContract, data: hash, isPending, error: writeErr, reset } = useWriteContract();

  const { isLoading: confirming, isSuccess: txSuccess } = useWaitForTransactionReceipt({
    hash,
  });

  useEffect(() => {
    if (txSuccess) {
      refetchAllowance();
      reset();
    }
  }, [txSuccess, refetchAllowance, reset]);

  const needsApprove = useMemo(() => {
    if (!allowance || usdcAmountWei === 0n) return true;
    return allowance < usdcAmountWei;
  }, [allowance, usdcAmountWei]);

  const approve = async () => {
    if (!escrowConfigured || usdcAmountWei === 0n) return;
    writeContract({
      address: ADDRESSES.USDC,
      abi: ERC20_ABI,
      functionName: "approve",
      args: [ADDRESSES.HEDGE_ESCROW, maxUint256],
    });
  };

  const openHedge = () => {
    if (!escrowConfigured || usdcAmountWei === 0n) return;
    if (needsApprove) return;
    const limitPx1e8 = parseUnits(limitPrice || "0", 8);
    const sz1e8 = parseUnits(sizePurr || "0", 8);
    if (limitPx1e8 === 0n || sz1e8 === 0n) return;

    let cloid = 0n;
    if (cloidStr.trim()) {
      try {
        cloid = BigInt(cloidStr.trim());
      } catch {
        return;
      }
    }
    if (cloid > (1n << 128n) - 1n) return;

    writeContract({
      address: ADDRESSES.HEDGE_ESCROW,
      abi: HEDGE_ESCROW_ABI,
      functionName: "openBuyPurrWithUsdc",
      args: [usdcAmountWei, limitPx1e8, sz1e8, tif, cloid],
    });
  };

  if (!escrowConfigured) {
    return (
      <div className="rounded-2xl border border-[var(--border)] bg-[var(--card)] p-6 text-sm text-[var(--text-muted)]">
        Run <code className="text-xs">DeployAll</code> and <code className="text-xs">scripts/sync_env_from_broadcast.py</code>{" "}
        so <code className="text-xs">NEXT_PUBLIC_HEDGE_ESCROW</code> is set (hedging ships with every stack).
      </div>
    );
  }

  return (
    <div className="space-y-4 rounded-2xl border border-[var(--border)] bg-[var(--card)] p-6">
      <h2 className="text-lg font-semibold text-[var(--foreground)]">Open hedge (CoreWriter)</h2>
      <p className="text-sm text-[var(--text-muted)]">
        Bridges USDC to HyperCore spot and places a <strong>buy PURR</strong> limit order via the system contract{" "}
        <code className="text-xs">0x3333…3333</code>. Limit price and size use HL scaling (1e8 × human). Spot order
        asset id in the contract is <code className="text-xs">10000 + spotIndex</code> (not the perp universe id).
      </p>
      {szDecimalsHint !== null && (
        <p className="text-xs text-[var(--text-muted)]">
          spotMeta PURR <code className="text-xs">szDecimals={szDecimalsHint}</code> (hint for manual size checks)
        </p>
      )}

      <div className="grid gap-3">
        <label className="block text-sm">
          <span className="text-[var(--text-muted)]">USDC amount</span>
          <input
            type="text"
            value={usdcIn}
            onChange={(e) => setUsdcIn(e.target.value)}
            placeholder="0.0"
            className="mt-1 w-full rounded-lg border border-[var(--border)] bg-[var(--background)] px-3 py-2 text-[var(--foreground)]"
          />
        </label>
        <label className="block text-sm">
          <span className="text-[var(--text-muted)]">Limit price (USDC per 1 PURR)</span>
          <input
            type="text"
            value={limitPrice}
            onChange={(e) => setLimitPrice(e.target.value)}
            placeholder="e.g. 5.0"
            className="mt-1 w-full rounded-lg border border-[var(--border)] bg-[var(--background)] px-3 py-2 text-[var(--foreground)]"
          />
        </label>
        <label className="block text-sm">
          <span className="text-[var(--text-muted)]">Size (PURR, human — encoded × 1e8)</span>
          <input
            type="text"
            value={sizePurr}
            onChange={(e) => setSizePurr(e.target.value)}
            placeholder="e.g. 10"
            className="mt-1 w-full rounded-lg border border-[var(--border)] bg-[var(--background)] px-3 py-2 text-[var(--foreground)]"
          />
        </label>
        <label className="block text-sm">
          <span className="text-[var(--text-muted)]">TIF</span>
          <select
            value={tif}
            onChange={(e) => setTif(Number(e.target.value) as 1 | 2 | 3)}
            className="mt-1 w-full rounded-lg border border-[var(--border)] bg-[var(--background)] px-3 py-2 text-[var(--foreground)]"
          >
            <option value={1}>Alo (1)</option>
            <option value={2}>Gtc (2)</option>
            <option value={3}>Ioc (3)</option>
          </select>
        </label>
        <label className="block text-sm">
          <span className="text-[var(--text-muted)]">Client order id (optional, uint128; 0 = none)</span>
          <input
            type="text"
            value={cloidStr}
            onChange={(e) => setCloidStr(e.target.value)}
            placeholder="0"
            className="mt-1 w-full rounded-lg border border-[var(--border)] bg-[var(--background)] px-3 py-2 text-[var(--foreground)]"
          />
        </label>
      </div>

      {writeErr && <p className="text-sm text-red-400">{writeErr.message}</p>}

      {!isConnected && (
        <p className="text-sm text-[var(--text-muted)]">Connect your wallet.</p>
      )}

      {isConnected && (
        <div className="flex flex-wrap gap-2">
          {needsApprove && usdcAmountWei > 0n && (
            <button
              type="button"
              disabled={isPending || confirming}
              onClick={() => approve()}
              className="rounded-lg bg-amber-600 px-4 py-2 text-sm text-white disabled:opacity-50"
            >
              {isPending || confirming ? "Confirming…" : "Approve USDC"}
            </button>
          )}
          <button
            type="button"
            disabled={isPending || confirming || usdcAmountWei === 0n || needsApprove}
            onClick={() => openHedge()}
            className="rounded-lg bg-[var(--accent)] px-4 py-2 text-sm text-white disabled:opacity-50"
          >
            {isPending || confirming ? "Confirming…" : "Place limit order"}
          </button>
        </div>
      )}

      {address && (
        <p className="text-xs text-[var(--text-muted)]">
          Allowance:{" "}
          {allowance !== undefined ? allowance.toString() : "…"} (USDC raw)
        </p>
      )}
    </div>
  );
}
