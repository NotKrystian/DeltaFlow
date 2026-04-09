import type { Metadata } from "next";
import Link from "next/link";
import DocsPageShell from "@/app/components/DocsPageShell";

export const metadata: Metadata = {
  title: "Hedge (escrow) · Docs · Delta Flow",
  description: "HedgeEscrow spot orders and claims in the app.",
};

export default function DocsHedgePage() {
  return (
    <DocsPageShell
      title="Hedge (escrow)"
      description="User-initiated CoreWriter spot flow: open a limit buy with USDC, then claim PURR when fillable."
    >
      <p>
        On <Link href="/">Trade</Link>, open the <strong>Hedge</strong> tab. You will see{" "}
        <strong>Open hedge</strong> (place order) and <strong>Claims</strong> (status / claim)
        when the escrow contract is configured in the frontend addresses.
      </p>
      <h2>Open a buy</h2>
      <ol>
        <li>Connect the wallet that will own the order.</li>
        <li>
          Approve USDC to the HedgeEscrow contract if required.
        </li>
        <li>
          Enter USDC size, limit price (USDC per 1 PURR), and size in PURR as the UI requests.
          Size decimals should match Hyperliquid spot metadata where the UI fetches hints.
        </li>
        <li>
          Submit the transaction. The contract bridges to Core and places the spot limit order.
        </li>
      </ol>
      <h2>Claims</h2>
      <p>
        Use the claims card to see whether a position can be claimed and to run the claim
        transaction when the protocol allows it. A backend may expose <code>/escrow/trades</code>{" "}
        for monitoring — that is separate from swap execution.
      </p>
      <div className="callout">
        This surface is <strong>not</strong> the vault’s automatic per-swap perp hedge. Perp IOC
        batching and escrow of swap outputs are configured on-chain and surfaced on the{" "}
        <Link href="/strategist">Strategist</Link> page under the perp hedge queue.
      </div>
    </DocsPageShell>
  );
}
