import type { Metadata } from "next";
import Link from "next/link";
import DocsPageShell from "@/app/components/DocsPageShell";

export const metadata: Metadata = {
  title: "Trade · Docs · Delta Flow",
  description: "Overview of the Trade page: swap, liquidity, and hedge tabs.",
};

export default function DocsTradePage() {
  return (
    <DocsPageShell
      title="Trade (home page)"
      description="The Trade page is the default route. Use the tab row to switch features without leaving the page."
    >
      <p>
        Open <Link href="/">Trade</Link> from the header. Connect your wallet on the HyperEVM
        network your deployment targets (see <code>NEXT_PUBLIC_*</code> env in{" "}
        <code>.env.local</code>).
      </p>
      <h2>Tabs</h2>
      <ul>
        <li>
          <strong>Swap</strong> — On-chain swap via <code>SovereignPool.swap</code>. See{" "}
          <Link href="/docs/swap">Swap</Link>.
        </li>
        <li>
          <strong>Add</strong> — Quick ERC-20 transfers into the vault (does not mint LP shares).
          For minting LP, use <Link href="/lp">LP</Link>. See{" "}
          <Link href="/docs/add-liquidity">Add liquidity</Link>.
        </li>
        <li>
          <strong>Remove</strong> — Shortcut to proportional withdrawal via the LP dashboard. See{" "}
          <Link href="/docs/remove-liquidity">Remove liquidity</Link>.
        </li>
        <li>
          <strong>Hedge</strong> — HedgeEscrow: spot limit flow and claims. See{" "}
          <Link href="/docs/hedge">Hedge (escrow)</Link>.
        </li>
      </ul>
      <div className="callout">
        Vault per-swap perp hedging runs inside pool swaps; it is not configured from this tab.
        Strategists monitor queue sizes on the <Link href="/strategist">Strategist</Link> page.
      </div>
    </DocsPageShell>
  );
}
