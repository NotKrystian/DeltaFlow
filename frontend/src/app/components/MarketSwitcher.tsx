"use client";

import { useMarket } from "@/app/context/MarketContext";
import { getMarketSnapshot } from "@/app/lib/marketConfig";

export default function MarketSwitcher() {
  const { marketId, setMarketId, hasSecondaryMarket, market } = useMarket();

  if (!hasSecondaryMarket) {
    return (
      <div className="inline-flex items-center gap-2 rounded-xl border border-[var(--border)] bg-[var(--card)] px-3 py-1.5 text-xs text-[var(--text-muted)]">
        <span className="font-medium text-[var(--foreground)]">
          {market.baseSymbol}/USDC
        </span>
        <span className="hidden sm:inline">
          (set <code className="text-[var(--text-secondary)]">NEXT_PUBLIC_POOL_WETH</code>{" "}
          etc. for a second pool)
        </span>
      </div>
    );
  }

  const primarySnap = getMarketSnapshot("primary");
  const secondarySnap = getMarketSnapshot("secondary");
  const primarySym = primarySnap?.baseSymbol ?? "—";
  const secondarySym = secondarySnap?.baseSymbol ?? "—";

  return (
    <div className="inline-flex rounded-xl border border-[var(--border)] bg-[var(--input-bg)] p-0.5 text-sm">
      <button
        type="button"
        onClick={() => setMarketId("primary")}
        className={`rounded-lg px-3 py-1.5 font-medium transition ${
          marketId === "primary"
            ? "bg-[var(--accent)] text-white shadow-sm"
            : "text-[var(--text-muted)] hover:text-[var(--foreground)]"
        }`}
      >
        {primarySym}
      </button>
      <button
        type="button"
        onClick={() => setMarketId("secondary")}
        className={`rounded-lg px-3 py-1.5 font-medium transition ${
          marketId === "secondary"
            ? "bg-[var(--accent)] text-white shadow-sm"
            : "text-[var(--text-muted)] hover:text-[var(--foreground)]"
        }`}
      >
        {secondarySym}
      </button>
    </div>
  );
}
