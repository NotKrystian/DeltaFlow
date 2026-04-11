import StrategistCard from "../components/StrategistCard";

export default function StrategistPage() {
  return (
    <main className="min-h-screen bg-[var(--background)] flex flex-col items-center px-4 sm:px-6 lg:px-8 pt-10 pb-20">
      <div className="w-full max-w-4xl">
        <h1 className="text-2xl font-bold text-[var(--foreground)] mb-2">
          Strategist console
        </h1>
        <p className="text-[var(--text-muted)] text-sm mb-8 max-w-2xl">
          Treasury, HyperCore allocation, and vault health for the ETH/UETH
          testnet market. Hedge queue and mark-based batching are read directly
          from the deployed vault.
        </p>
        <StrategistCard />
      </div>
    </main>
  );
}
