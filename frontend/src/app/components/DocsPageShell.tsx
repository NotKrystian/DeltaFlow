import Link from "next/link";
import { ArrowLeft } from "lucide-react";
import type { ReactNode } from "react";

export default function DocsPageShell({
  title,
  description,
  children,
  backHref = "/docs",
  backLabel = "Documentation",
}: {
  title: string;
  description?: string;
  children: ReactNode;
  backHref?: string;
  backLabel?: string;
}) {
  return (
    <main className="min-h-screen bg-[var(--background)] px-4 sm:px-6 lg:px-8 pt-8 pb-20">
      <article className="max-w-3xl mx-auto space-y-8">
        <div>
          <Link
            href={backHref}
            className="inline-flex items-center gap-2 text-sm text-[var(--accent)] hover:underline mb-4"
          >
            <ArrowLeft size={16} />
            {backLabel}
          </Link>
          <h1 className="text-2xl sm:text-3xl font-semibold text-[var(--foreground)] tracking-tight">
            {title}
          </h1>
          {description && (
            <p className="mt-2 text-[var(--text-muted)] text-base leading-relaxed">
              {description}
            </p>
          )}
        </div>
        <div className="docs-prose space-y-5 text-[var(--foreground)] text-[15px] leading-relaxed">
          {children}
        </div>
      </article>
    </main>
  );
}
