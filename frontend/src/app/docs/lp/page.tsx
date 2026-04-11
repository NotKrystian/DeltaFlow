import type { Metadata } from "next";
import Link from "next/link";
import DocsPageShell from "@/app/components/DocsPageShell";

export const metadata: Metadata = {
  title: "LP provider · Docs · Delta Flow",
  description: "Deposit and withdraw vault LP, view share and illustrative fee surplus.",
};

export default function DocsLpPage() {
  return (
    <DocsPageShell
      title="LP provider"
      description="Mint and burn vault LP, track pool share, estimated value, and surplus attribution."
    >
      <p>
        Open <Link href="/lp">LP</Link> from the header. You must connect a wallet that holds
        USDC and the deployed base token (UETH in the recommended testnet setup), or receive LP
        after deposit, on the same chain as the deployment.
      </p>
      <h2>Deposit</h2>
      <ol>
        <li>
          Approve the sovereign vault for the token amounts you plan to deposit (USDC and/or base
          token as supported by <code>depositLP</code>).
        </li>
        <li>
          Enter amounts and submit <strong>Deposit</strong>. Confirm in your wallet; wait for the
          receipt before refreshing balances.
        </li>
        <li>
          Your LP balance updates; total supply and reserves drive the <strong>share %</strong>{" "}
          and <strong>estimated USDC value</strong> shown in the dashboard.
        </li>
      </ol>
      <h2>Withdraw</h2>
      <p>
        Use the withdraw control (typically by percentage) to burn LP and receive underlying
        assets. Slippage here is the vault’s reserve math, not a swap slippage field.
      </p>
      <h2>Fee surplus and disclaimers</h2>
      <p>
        If a FeeSurplus contract is wired in config, the UI may show a <strong>surplus</strong>{" "}
        balance and a <strong>pro-rata</strong> share. That illustration is not a guaranteed
        claimable payout in one step — read the on-card disclaimer. Protocol fee routing is defined
        in contracts, not in the frontend.
      </p>
      <h2>Reserves</h2>
      <p>
        Reserve lines reflect <code>getReserves</code> (and related views). Strategist moves
        between EVM and HyperCore can change what you see over time.
      </p>
    </DocsPageShell>
  );
}
