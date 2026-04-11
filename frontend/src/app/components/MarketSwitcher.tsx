"use client";

import { useMarket } from "@/app/context/MarketContext";

export default function MarketSwitcher() {
  const { market } = useMarket();

  return (
    <div className="inline-flex items-center gap-2 rounded-xl border border-[var(--border)] bg-[var(--card)] px-3 py-1.5 text-xs text-[var(--text-muted)]">
      <span className="font-medium text-[var(--foreground)]">
        {market.baseSymbol}/USDC
      </span>
      <span className="hidden sm:inline">(ETH-only mode)</span>
    </div>
  );
}
