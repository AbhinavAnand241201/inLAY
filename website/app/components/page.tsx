import Link from "next/link";
import type { Metadata } from "next";
import { Nav } from "@/components/Nav";
import { Footer } from "@/components/Footer";
import { Preview } from "@/components/Preview";
import { CopyButton } from "@/components/CopyButton";
import { groupedByCategory, components } from "@/lib/registry";

export const metadata: Metadata = {
  title: "Components — Inlay",
  description: "Browse Inlay's UIKit components and animations for iOS.",
};

export default function ComponentsPage() {
  const groups = groupedByCategory();

  return (
    <>
      <Nav />
      <main>
        <header className="border-b-[3px] border-ink">
          <div className="mx-auto max-w-6xl px-5 py-14">
            <div className="label text-ink/60">The catalog</div>
            <h1 className="mt-3 font-sans text-5xl font-black uppercase tracking-tight md:text-7xl">
              Components
            </h1>
            <p className="mt-5 max-w-2xl font-mono text-sm leading-relaxed md:text-base">
              {components.length} components and animations. Click any one for live
              previews, the install command, every variant, and the full source.
            </p>
          </div>
        </header>

        {groups.map(([category, list]) => (
          <section key={category} className="border-b-[3px] border-ink">
            <div className="mx-auto max-w-6xl px-5 py-12">
              <div className="label mb-8 inline-block border-[3px] border-ink px-3 py-1">
                {category} — {list.length}
              </div>
              <div className="grid gap-8 md:grid-cols-2">
                {list.map((c) => (
                  <div key={c.name} className="brut-card flex flex-col">
                    <Link
                      href={`/components/${c.name}`}
                      className="flex min-h-[200px] items-center justify-center border-b-[3px] border-ink bg-[repeating-linear-gradient(45deg,#fff,#fff_12px,#f4f4f4_12px,#f4f4f4_24px)] p-8"
                    >
                      <Preview name={c.name} />
                    </Link>
                    <div className="flex flex-1 flex-col p-5">
                      <div className="flex items-start justify-between gap-3">
                        <h3 className="font-sans text-2xl font-black uppercase leading-none">
                          {c.title}
                        </h3>
                        <span className="label shrink-0 border-[3px] border-ink px-2 py-0.5">
                          {c.kind}
                        </span>
                      </div>
                      <p className="mt-3 flex-1 font-mono text-sm leading-relaxed text-ink/80">
                        {c.description}
                      </p>
                      {c.variants && c.variants.length > 0 && (
                        <div className="mt-4 flex flex-wrap gap-2">
                          {c.variants.map((v) => (
                            <span
                              key={v.id}
                              className="border-2 border-ink px-2 py-0.5 font-mono text-[10px] font-bold uppercase tracking-wider"
                            >
                              {v.title}
                            </span>
                          ))}
                        </div>
                      )}
                      <div className="mt-5 flex items-center justify-between gap-3 border-[3px] border-ink bg-ink px-3 py-2 text-paper">
                        <code className="overflow-x-auto whitespace-nowrap font-mono text-xs">
                          <span className="text-paper/50">$ </span>inlay add {c.name}
                        </code>
                        <CopyButton
                          text={`inlay add ${c.name}`}
                          className="border-paper bg-ink text-paper hover:bg-paper hover:text-ink"
                        />
                      </div>
                      <Link
                        href={`/components/${c.name}`}
                        className="brut-btn mt-4 w-full"
                      >
                        View component →
                      </Link>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          </section>
        ))}
      </main>
      <Footer />
    </>
  );
}
