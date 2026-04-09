"use client";

import Link from "next/link";
import { ArrowRight, Flame } from "lucide-react";

/** Withdraw LP via `withdrawLP` on the vault — full flow lives on `/lp`. */
export default function RemoveLiquidityCard() {
  return (
    <div className="w-full">
      <div className="bg-[var(--card)] rounded-3xl border border-[var(--border)] p-6 shadow-lg glow-green">
        <div className="flex items-center gap-2 mb-3">
          <Flame className="text-[var(--danger)]" size={22} />
          <h2 className="text-lg font-semibold text-[var(--foreground)]">
            Remove liquidity
          </h2>
        </div>
        <p className="text-sm text-[var(--text-muted)] mb-6">
          Burning DeltaFlow LP (<strong>DFLP</strong>) and receiving pro-rata USDC
          and the pool base asset (PURR or WETH) is done with{" "}
          <code className="text-[var(--foreground)]">withdrawLP</code> on the vault.
          Use the LP dashboard for share-based withdrawal and reserves. Pick the
          market (PURR vs WETH) in the header.
        </p>
        <Link
          href="/lp"
          className="flex items-center justify-center gap-2 w-full py-4 rounded-2xl font-semibold bg-[var(--danger)]/90 text-white hover:opacity-95 transition"
        >
          Open LP dashboard
          <ArrowRight size={20} />
        </Link>
      </div>
    </div>
  );
}
