import Link from "next/link";

export function Footer() {
  return (
    <footer className="border-t-[3px] border-ink bg-ink text-paper">
      <div className="mx-auto grid max-w-6xl gap-8 px-5 py-12 md:grid-cols-3">
        <div>
          <div className="font-sans text-2xl font-black uppercase">Inlay</div>
          <p className="mt-2 max-w-xs font-mono text-xs leading-relaxed text-paper/70">
            Copy-paste UIKit components for iOS. You own the code — it&apos;s not a
            dependency you import.
          </p>
        </div>
        <div>
          <div className="label text-paper/50">Explore</div>
          <ul className="mt-3 space-y-2 font-mono text-sm">
            <li><Link href="/components" className="hover:underline">Components</Link></li>
            <li><Link href="/#how" className="hover:underline">How it works</Link></li>
            <li><Link href="/#about" className="hover:underline">The creator</Link></li>
          </ul>
        </div>
        <div>
          <div className="label text-paper/50">Install</div>
          <code className="mt-3 block border-[3px] border-paper/40 px-3 py-2 font-mono text-xs">
            brew install AbhinavAnand241201/tap/inlay
          </code>
        </div>
      </div>
      <div className="border-t-[3px] border-paper/20 px-5 py-4 text-center font-mono text-xs uppercase tracking-widest text-paper/50">
        Built by Abhinav · iOS Developer
      </div>
    </footer>
  );
}
