"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { ConnectButton } from "@rainbow-me/rainbowkit";
import { Wallet } from "lucide-react";
import MarketSwitcher from "@/app/components/MarketSwitcher";

const nav = [
  { href: "/", label: "Trade" },
  { href: "/lp", label: "LP" },
  { href: "/strategist", label: "Strategist" },
  { href: "/docs", label: "Docs" },
] as const;

export default function Header() {
  const pathname = usePathname();

  return (
    <header className="sticky top-0 z-50 bg-[var(--background)]/80 backdrop-blur-sm border-b border-[var(--border)]">
      <div className="max-w-7xl mx-auto px-6 sm:px-10">
        <div className="flex items-center justify-between h-16 gap-4">
          <div className="flex items-center gap-6 min-w-0">
            <Link href="/" className="flex items-center gap-2 shrink-0">
              <img
                src="/deltaFlow.png"
                alt="Delta Flow"
                className="h-7 sm:h-8 w-auto object-contain"
              />
            </Link>
            <nav className="hidden sm:flex items-center gap-1">
              {nav.map(({ href, label }) => {
                const active =
                  href === "/"
                    ? pathname === "/"
                    : href === "/docs"
                      ? pathname === "/docs" || pathname.startsWith("/docs/")
                      : pathname.startsWith(href);
                return (
                  <Link
                    key={href}
                    href={href}
                    className={`px-3 py-1.5 rounded-xl text-sm font-medium transition ${
                      active
                        ? "bg-[var(--accent-muted)] text-[var(--accent)] border border-[var(--border)]"
                        : "text-[var(--text-muted)] hover:text-[var(--foreground)]"
                    }`}
                  >
                    {label}
                  </Link>
                );
              })}
            </nav>
          </div>

          <div className="flex items-center gap-2 sm:gap-3 shrink-0">
            <MarketSwitcher />
            {/* Connect button (custom styled) */}
            <ConnectButton.Custom>
            {({
              account,
              chain,
              openAccountModal,
              openChainModal,
              openConnectModal,
              mounted,
            }) => {
              const ready = mounted;
              const connected = ready && account && chain;

              return (
                <div
                  aria-hidden={!ready}
                  className={
                    !ready ? "opacity-0 pointer-events-none select-none" : ""
                  }
                >
                  {!connected ? (
                    // Not connected — Hyperliquid-ish styling
                    <button
                      onClick={openConnectModal}
                      type="button"
                      className="
                        inline-flex items-center gap-2 h-10 px-4 rounded-2xl
                        bg-[var(--card)] border border-[var(--border)]
                        text-[var(--foreground)] font-semibold text-sm
                        hover:bg-[var(--card-hover)] hover:border-[var(--border-hover)]
                        transition shadow-sm
                      "
                    >
                      <span
                        className="
                          inline-flex items-center justify-center
                          w-7 h-7 rounded-xl
                          bg-[var(--accent-muted)] border border-[var(--border)]
                          text-[var(--accent)]
                        "
                      >
                        <Wallet size={16} />
                      </span>
                      <span className="tracking-tight">Connect Wallet</span>
                      <span
                        className="
                          ml-1 h-2 w-2 rounded-full
                          bg-[var(--accent)]
                          shadow-[0_0_16px_var(--accent)]
                        "
                      />
                    </button>
                  ) : (
                    // Connected — keep clean, but still on-theme
                    <div className="flex items-center gap-2">
                      <button
                        onClick={openChainModal}
                        type="button"
                        className="
                          hidden sm:inline-flex items-center gap-2 h-10 px-3 rounded-2xl
                          bg-[var(--card)] border border-[var(--border)]
                          text-[var(--foreground)] text-sm font-medium
                          hover:bg-[var(--card-hover)] hover:border-[var(--border-hover)]
                          transition
                        "
                      >
                        {chain?.hasIcon && chain.iconUrl ? (
                          <img
                            alt={chain.name ?? "Chain"}
                            src={chain.iconUrl}
                            className="w-5 h-5 rounded-full"
                          />
                        ) : (
                          <span className="w-5 h-5 rounded-full bg-[var(--accent-muted)]" />
                        )}
                        <span className="text-[var(--text-muted)]">
                          {chain?.name}
                        </span>
                      </button>

                      <button
                        onClick={openAccountModal}
                        type="button"
                        className="
                          inline-flex items-center gap-2 h-10 px-4 rounded-2xl
                          bg-[var(--card)] border border-[var(--border)]
                          text-[var(--foreground)] text-sm font-semibold
                          hover:bg-[var(--card-hover)] hover:border-[var(--border-hover)]
                          transition shadow-sm
                        "
                      >
                        <span className="truncate max-w-[140px] sm:max-w-[200px]">
                          {account?.displayName}
                        </span>
                        <span className="h-2 w-2 rounded-full bg-[var(--accent)]" />
                      </button>
                    </div>
                  )}
                </div>
              );
            }}
            </ConnectButton.Custom>
          </div>
        </div>
      </div>
    </header>
  );
}
