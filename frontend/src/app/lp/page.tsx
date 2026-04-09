import LpProviderDashboard from "../components/LpProviderDashboard";

export default function LpPage() {
  return (
    <main className="min-h-screen bg-[var(--background)] flex flex-col items-center px-4 sm:px-6 lg:px-8 pt-10 pb-20">
      <LpProviderDashboard />
    </main>
  );
}
