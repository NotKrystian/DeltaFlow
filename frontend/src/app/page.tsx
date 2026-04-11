"use client";

import Link from "next/link";
import { useState } from "react";
import SwapCard from "./components/SwapCard";
import AddLiquidityCard from "./components/AddLiquidityCard";
import RemoveLiquidityCard from "./components/RemoveLiquidityCard";
import EscrowClaimsCard from "./components/EscrowClaimsCard";
import HedgeOpenCard from "./components/HedgeOpenCard";

type Tab = "swap" | "add" | "remove" | "escrow";

export default function Home() {
  const [activeTab, setActiveTab] = useState<Tab>("swap");

  return (
    <main className="min-h-screen bg-[var(--background)] flex flex-col items-center px-4 sm:px-6 lg:px-8 pt-10 pb-20">
      <div className="w-full max-w-5xl space-y-12 md:space-y-16">
        <div className="text-center space-y-3">
          <p className="text-[var(--text-muted)] text-lg sm:text-xl max-w-lg mx-auto">
            DeltaFlow: USDC/UETH liquidity vaults on{" "}
            <span className="text-[var(--foreground)]">Hyperliquid</span> — swap,
            hedge, and LP fees in ETH-only mode.
          </p>
          <p className="text-sm text-[var(--text-secondary)]">
            <Link
              href="/lp"
              className="text-[var(--accent)] hover:underline font-medium"
            >
              LP dashboard
            </Link>
            {" · "}
            <Link
              href="/strategist"
              className="text-[var(--accent)] hover:underline font-medium"
            >
              Strategist
            </Link>
            {" · "}
            <Link
              href="/docs"
              className="text-[var(--accent)] hover:underline font-medium"
            >
              Docs
            </Link>
          </p>
        </div>

        <div className="w-full flex justify-center">
          <div
            className={`w-full ${activeTab === "escrow" ? "max-w-[700px]" : "max-w-[500px]"}`}
          >
            <div className="flex gap-2 p-1 bg-[var(--card)] rounded-2xl border border-[var(--border)] mb-6">
              {(["swap", "add", "remove", "escrow"] as const).map((tab) => (
                <button
                  key={tab}
                  type="button"
                  onClick={() => setActiveTab(tab)}
                  className={`flex-1 py-3 px-4 rounded-xl font-medium text-sm transition ${
                    activeTab === tab
                      ? "bg-[var(--accent)] text-white glow-green"
                      : "text-[var(--text-muted)] hover:text-[var(--foreground)]"
                  }`}
                >
                  {tab === "swap"
                    ? "Swap"
                    : tab === "add"
                      ? "Add"
                      : tab === "remove"
                        ? "Remove"
                        : "Hedge"}
                </button>
              ))}
            </div>

            {activeTab === "swap" && <SwapCard />}
            {activeTab === "add" && <AddLiquidityCard />}
            {activeTab === "remove" && <RemoveLiquidityCard />}
            {activeTab === "escrow" && (
              <div className="space-y-8 w-full">
                <HedgeOpenCard />
                <EscrowClaimsCard />
              </div>
            )}
          </div>
        </div>
      </div>
    </main>
  );
}
