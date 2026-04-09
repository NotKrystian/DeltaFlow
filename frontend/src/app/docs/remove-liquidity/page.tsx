import type { Metadata } from "next";
import Link from "next/link";
import DocsPageShell from "@/app/components/DocsPageShell";

export const metadata: Metadata = {
  title: "Remove liquidity · Docs · Delta Flow",
  description: "Withdraw vault LP proportionally from the LP dashboard.",
};

export default function DocsRemoveLiquidityPage() {
  return (
    <DocsPageShell
      title="Remove liquidity"
      description="Proportional withdrawal burns vault LP and returns underlying reserves."
    >
      <p>
        The <strong>Remove</strong> tab on <Link href="/">Trade</Link> links you to the LP flow.
        Actual withdrawal uses <code>withdrawLP</code> on the sovereign vault (or the app’s
        wrapped helper), not a bare ERC-20 transfer out.
      </p>
      <h2>Steps</h2>
      <ol>
        <li>
          Open <Link href="/lp">LP provider</Link>.
        </li>
        <li>
          Enter the percentage of your LP to burn (or the amount, depending on the current UI).
        </li>
        <li>
          Confirm the transaction. Underlying USDC and PURR are sent according to vault reserves
          and your share.
        </li>
      </ol>
      <p>
        Read the share and value estimates on the LP page before withdrawing — they are
        indicative and depend on spot price and on-chain state.
      </p>
    </DocsPageShell>
  );
}
