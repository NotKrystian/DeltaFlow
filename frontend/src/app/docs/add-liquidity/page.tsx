import type { Metadata } from "next";
import Link from "next/link";
import DocsPageShell from "@/app/components/DocsPageShell";

export const metadata: Metadata = {
  title: "Add liquidity · Docs · Delta Flow",
  description: "Quick token transfers to the vault vs minting LP on the LP dashboard.",
};

export default function DocsAddLiquidityPage() {
  return (
    <DocsPageShell
      title="Add liquidity (quick transfer)"
      description="The Add tab sends USDC and/or UETH into the sovereign vault as plain transfers."
    >
      <p>
        Open <Link href="/">Trade</Link> → <strong>Add</strong>. This path uses ERC-20 transfers
        to the vault address — it does <strong>not</strong> call <code>depositLP</code> or mint
        vault LP tokens.
      </p>
      <h2>When to use this tab</h2>
      <ul>
        <li>Move inventory into the vault for testing or operational funding.</li>
        <li>Top up one side if you already know the vault’s accounting you want.</li>
      </ul>
      <h2>When to use the LP dashboard instead</h2>
      <p>
        To receive a <strong>pro-rata share</strong> of the pool and show up in LP metrics, use{" "}
        <Link href="/lp">LP provider</Link> and <code>depositLP</code> after approving the vault.
        See <Link href="/docs/lp">LP provider docs</Link>.
      </p>
      <div className="callout">
        Always verify the vault address matches your deployment (<code>NEXT_PUBLIC_*</code> /
        app config). Sending tokens to the wrong address is irreversible.
      </div>
    </DocsPageShell>
  );
}
