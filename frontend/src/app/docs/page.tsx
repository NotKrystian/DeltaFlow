import Link from "next/link";
import { BookOpen, ArrowRight } from "lucide-react";

const sections = [
  {
    title: "Trade (home)",
    href: "/docs/trade",
    blurb: "Tabs for swap, liquidity transfers, and hedge escrow — how the main page fits together.",
  },
  {
    title: "Swap",
    href: "/docs/swap",
    blurb: "Execute USDC ↔ PURR swaps against the pool with wallet approvals and slippage.",
  },
  {
    title: "Add liquidity (quick transfer)",
    href: "/docs/add-liquidity",
    blurb: "Send tokens to the vault without minting LP; when to use the LP dashboard instead.",
  },
  {
    title: "Remove liquidity",
    href: "/docs/remove-liquidity",
    blurb: "Withdraw proportional vault LP through the LP dashboard.",
  },
  {
    title: "Hedge (escrow)",
    href: "/docs/hedge",
    blurb: "HedgeEscrow spot orders and claims — separate from vault per-swap perp hedging.",
  },
  {
    title: "LP provider",
    href: "/docs/lp",
    blurb: "Deposit and withdraw vault LP, view pool share, surplus attribution, and position value.",
  },
  {
    title: "Strategist",
    href: "/docs/strategist",
    blurb: "Bridges, allocation, pool/vault monitoring, and perp hedge queue settings.",
  },
] as const;

export default function DocsIndexPage() {
  return (
    <main className="min-h-screen bg-[var(--background)] px-4 sm:px-6 lg:px-8 pt-10 pb-20">
      <div className="max-w-3xl mx-auto space-y-10">
        <div className="flex items-start gap-3">
          <div className="mt-1 p-2 rounded-xl bg-[var(--accent-muted)] border border-[var(--border)] text-[var(--accent)]">
            <BookOpen size={22} />
          </div>
          <div>
            <h1 className="text-2xl sm:text-3xl font-semibold text-[var(--foreground)] tracking-tight">
              DeltaFlow app documentation
            </h1>
            <p className="mt-2 text-[var(--text-muted)] leading-relaxed">
              How to use each screen in this frontend. Connect a wallet on the correct HyperEVM
              network, then follow the guides below. On-chain behavior follows the deployed
              contracts; numbers shown are estimates where noted.
            </p>
          </div>
        </div>

        <ul className="space-y-3">
          {sections.map(({ title, href, blurb }) => (
            <li key={href}>
              <Link
                href={href}
                className="group flex items-start justify-between gap-4 rounded-2xl border border-[var(--border)] bg-[var(--card)] p-4 sm:p-5 hover:border-[var(--border-hover)] hover:bg-[var(--card-hover)] transition"
              >
                <div>
                  <h2 className="text-base font-semibold text-[var(--foreground)] group-hover:text-[var(--accent)] transition">
                    {title}
                  </h2>
                  <p className="mt-1 text-sm text-[var(--text-muted)] leading-relaxed">{blurb}</p>
                </div>
                <ArrowRight
                  size={20}
                  className="shrink-0 mt-0.5 text-[var(--text-secondary)] group-hover:text-[var(--accent)] transition"
                />
              </Link>
            </li>
          ))}
        </ul>

        <p className="text-sm text-[var(--text-secondary)]">
          Protocol-level detail lives in the repository{" "}
          <code className="text-[var(--accent)]">docs/</code> folder (for example{" "}
          <span className="text-[var(--text-muted)]">architecture/current-implementation.md</span>
          ).
        </p>
      </div>
    </main>
  );
}
