import Link from "next/link";

export function Nav() {
  return (
    <header className="sticky top-0 z-50 border-b-[3px] border-ink bg-paper">
      <div className="mx-auto flex max-w-6xl items-center justify-between px-5 py-3">
        <Link href="/" className="flex items-center gap-2">
          <span className="flex h-8 w-8 items-center justify-center bg-ink font-mono text-lg font-black text-paper">
            ▣
          </span>
          <span className="font-sans text-xl font-black uppercase tracking-tight">Inlay</span>
        </Link>
        <nav className="flex items-center gap-2 md:gap-3">
          <Link
            href="/components"
            className="px-3 py-2 font-mono text-xs font-bold uppercase tracking-wider hover:underline md:text-sm"
          >
            Components
          </Link>
          <Link
            href="/#about"
            className="px-3 py-2 font-mono text-xs font-bold uppercase tracking-wider hover:underline md:text-sm"
          >
            Creator
          </Link>
          <a
            href="https://github.com/"
            target="_blank"
            rel="noreferrer"
            className="brut-btn-ghost px-3 py-2 text-xs"
          >
            GitHub
          </a>
        </nav>
      </div>
    </header>
  );
}
