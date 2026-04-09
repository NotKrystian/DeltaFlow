import type { Metadata } from "next";
import Link from "next/link";
import DocsPageShell from "@/app/components/DocsPageShell";

export const metadata: Metadata = {
  title: "Swap · Docs · Delta Flow",
  description: "How to swap USDC and PURR using the DeltaFlow pool.",
};

export default function DocsSwapPage() {
  return (
    <DocsPageShell
      title="Swap"
      description="Trade one side of the pair for the other at the ALM’s spot-based quote, after pool fees."
    >
      <p>
        Go to <Link href="/">Trade</Link>, choose the <strong>Swap</strong> tab, then connect
        your wallet.
      </p>
      <h2>Steps</h2>
      <ol>
        <li>
          Pick direction (e.g. USDC → PURR or PURR → USDC). Amounts use the token decimals for
          the deployed pair (PURR is often 5 decimals on testnet; USDC is 6).
        </li>
        <li>
          If prompted, <strong>approve</strong> the pool (or router path the UI uses) to spend
          your input token.
        </li>
        <li>
          Review the quoted output and fee display. Set a <strong>slippage</strong> tolerance if
          the card exposes it — large moves can change the executable amount.
        </li>
        <li>
          Submit <strong>Swap</strong> and wait for confirmation. On failure, read the revert
          reason in your wallet or explorer (liquidity, hedge, or oracle constraints can revert the
          whole transaction).
        </li>
      </ol>
      <h2>What you should know</h2>
      <ul>
        <li>
          Pricing comes from the on-chain ALM and spot index — not a simple x*y=k reserve formula.
        </li>
        <li>
          The vault may process a per-swap perp hedge or escrow payouts depending on deployment;
          that is transparent to you as a swapper but can affect whether the swap succeeds in one
          tx.
        </li>
      </ul>
    </DocsPageShell>
  );
}
