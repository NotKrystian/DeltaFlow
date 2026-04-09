import type { Metadata } from "next";
import Link from "next/link";
import DocsPageShell from "@/app/components/DocsPageShell";

export const metadata: Metadata = {
  title: "Strategist · Docs · Delta Flow",
  description: "Bridges, Core allocation, and perp hedge queue monitoring.",
};

export default function DocsStrategistPage() {
  return (
    <DocsPageShell
      title="Strategist"
      description="Operational console for the vault strategist: bridges, allocation, and health reads."
    >
      <p>
        Open <Link href="/strategist">Strategist</Link>. Only the on-chain strategist address can
        execute privileged vault actions (allocate / deallocate and similar). Everyone else can
        still read pool and vault state if addresses are set.
      </p>
      <h2>Configure addresses</h2>
      <p>
        Enter or confirm <strong>Pool</strong>, <strong>Vault</strong>, and <strong>ALM</strong>{" "}
        when the UI asks — defaults usually come from environment-driven{" "}
        <code>ADDRESSES</code> in the app.
      </p>
      <h2>Bridges</h2>
      <ul>
        <li>
          <strong>bridgeToCoreOnly</strong> — Move USDC from EVM vault balance into HyperCore
          without a Core vault allocation.
        </li>
        <li>
          <strong>bridgeToEvmOnly</strong> — Bring USDC to EVM when Core-side balances are already
          positioned as intended.
        </li>
      </ul>
      <h2>Allocate / deallocate</h2>
      <p>
        Move USDC between EVM and a Core vault for yield or inventory management. Confirm amounts
        and target vault IDs as required by the contract.
      </p>
      <h2>Perp hedge queue</h2>
      <p>
        Read <code>hedgePerpAssetIndex</code>, <code>minPerpHedgeSz</code>,{" "}
        <code>useMarkBasedMinHedgeSz</code>, pending buy/sell size buckets, and thresholds. These
        control when swap outputs are sent immediately vs escrowed until an IOC batch clears
        exchange minimums.
      </p>
      <div className="callout">
        Strategist tools can move protocol funds and risk. Test on testnet and verify addresses
        before mainnet use.
      </div>
      <p>
        For protocol semantics, see the repo doc{" "}
        <span className="text-[var(--text-muted)]">docs/architecture/current-implementation.md</span>
        .
      </p>
    </DocsPageShell>
  );
}
