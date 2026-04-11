"use client";

import {
  createContext,
  useCallback,
  useContext,
  useMemo,
  useState,
  type ReactNode,
} from "react";
import {
  getMarketSnapshot,
  isSecondaryMarketAvailable,
  type MarketId,
  type MarketSnapshot,
} from "@/app/lib/marketConfig";

type MarketContextValue = {
  marketId: MarketId;
  setMarketId: (id: MarketId) => void;
  /** Second pool/vault stack is deployed (env addresses set). */
  hasSecondaryMarket: boolean;
  /** @deprecated use hasSecondaryMarket */
  hasWeth: boolean;
  market: MarketSnapshot;
};

const MarketContext = createContext<MarketContextValue | null>(null);

const STORAGE_KEY = "deltaflow-market";

function readStoredMarketId(): MarketId {
  if (isSecondaryMarketAvailable()) return "secondary";
  if (typeof window === "undefined") return "primary";
  try {
    const s = localStorage.getItem(STORAGE_KEY);
    if (s === "primary" || s === "purr") return "primary";
  } catch {
    /* ignore */
  }
  return "primary";
}

export function MarketProvider({ children }: { children: ReactNode }) {
  const hasSecondaryMarket = isSecondaryMarketAvailable();

  const [marketId, setMarketIdState] = useState<MarketId>(readStoredMarketId);

  const setMarketId = useCallback((id: MarketId) => {
    if (isSecondaryMarketAvailable()) return;
    if (id === "secondary") return;
    setMarketIdState(id);
    try {
      localStorage.setItem(STORAGE_KEY, id);
    } catch {
      /* ignore */
    }
  }, []);

  const market = useMemo(() => {
    const effectiveId: MarketId = hasSecondaryMarket ? "secondary" : marketId;
    const snap = getMarketSnapshot(effectiveId);
    if (snap) return snap;
    return getMarketSnapshot("primary")!;
  }, [marketId, hasSecondaryMarket]);

  const value = useMemo(
    () => ({
      marketId: market.id,
      setMarketId,
      hasSecondaryMarket,
      hasWeth: hasSecondaryMarket,
      market,
    }),
    [market, setMarketId, hasSecondaryMarket]
  );

  return (
    <MarketContext.Provider value={value}>{children}</MarketContext.Provider>
  );
}

export function useMarket(): MarketContextValue {
  const ctx = useContext(MarketContext);
  if (!ctx) {
    throw new Error("useMarket must be used within MarketProvider");
  }
  return ctx;
}
