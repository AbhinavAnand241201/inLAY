import Link from "next/link";
import { notFound } from "next/navigation";
import type { Metadata } from "next";
import { Nav } from "@/components/Nav";
import { Footer } from "@/components/Footer";
import { Terminal } from "@/components/Terminal";
import { CodeBlock } from "@/components/CodeBlock";
import { DemoFrame } from "@/components/DemoFrame";
import { allComponents, getComponent, parseConfiguration } from "@/lib/registry";

export function generateStaticParams() {
  return allComponents.map((c) => ({ name: c.name }));
}

export function generateMetadata({ params }: { params: { name: string } }): Metadata {
  const c = getComponent(params.name);
  if (!c) return { title: "Not found — Inlay" };
  return { title: `${c.title} — Inlay`, description: c.description };
}

export default function ComponentPage({ params }: { params: { name: string } }) {
  const component = getComponent(params.name);
  if (!component) notFound();

  const knobs = parseConfiguration(component.files.map((f) => f.source).join("\n\n"));
  const typeName = component.title.replace(/\s+/g, "");

  return (
    <>
      <Nav />
      <main className="mx-auto max-w-5xl px-5 py-10">
        <Link href="/components" className="font-mono text-sm font-bold uppercase tracking-wider hover:underline">
          ← All components
        </Link>

        {/* Header */}
        <div className="mt-6 flex flex-wrap items-end justify-between gap-4 border-b-[3px] border-ink pb-8">
          <div>
            <div className="flex items-center gap-3">
              <span className="label border-[3px] border-ink px-2 py-0.5">{component.category}</span>
              <span className="label border-[3px] border-ink px-2 py-0.5">iOS {component.minIOS}</span>
            </div>
            <h1 className="mt-4 font-sans text-5xl font-black uppercase tracking-tight md:text-7xl">
              {component.title}
            </h1>
            <p className="mt-4 max-w-2xl font-mono text-sm leading-relaxed md:text-base">
              {component.description}
            </p>
          </div>
        </div>

        {/* Demo */}
        <Section kicker="Demo">
          <DemoFrame name={component.name} />
          <p className="mt-3 font-mono text-xs text-ink/50">
            Animated preview. Drop a screen recording at{" "}
            <code className="bg-ink px-1 text-paper">public/demos/{component.name}.mp4</code> to
            show real footage.
          </p>
        </Section>

        {/* Install */}
        <Section kicker="Install">
          <Terminal command={`inlay add ${component.name}`} />
          {component.dependencies.length > 0 && (
            <div className="mt-4 flex flex-wrap items-center gap-2">
              <span className="label text-ink/60">Pulls in automatically:</span>
              {component.dependencies.map((d) => (
                <Link
                  key={d}
                  href={`/components/${d}`}
                  className="border-[3px] border-ink px-2 py-0.5 font-mono text-xs font-bold hover:bg-ink hover:text-paper"
                >
                  {d}
                </Link>
              ))}
            </div>
          )}
        </Section>

        {/* Variants */}
        {component.variants && component.variants.length > 0 && (
          <Section kicker="Variants">
            <div className="grid gap-4 md:grid-cols-3">
              {component.variants.map((v) => (
                <div key={v.id} className="brut-card p-5">
                  <div className="font-sans text-xl font-black uppercase">{v.title}</div>
                  {v.description && (
                    <p className="mt-2 font-mono text-xs leading-relaxed text-ink/70">
                      {v.description}
                    </p>
                  )}
                </div>
              ))}
            </div>
          </Section>
        )}

        {/* Customize */}
        {knobs.length > 0 && (
          <Section kicker="Customize">
            <div className="brut-card overflow-hidden">
              <table className="w-full border-collapse font-mono text-sm">
                <thead>
                  <tr className="border-b-[3px] border-ink text-left">
                    <th className="px-4 py-3 label">Property</th>
                    <th className="px-4 py-3 label">Type</th>
                    <th className="px-4 py-3 label">Default</th>
                  </tr>
                </thead>
                <tbody>
                  {knobs.map((k, i) => (
                    <tr key={k.name} className={i < knobs.length - 1 ? "border-b-2 border-ink/20" : ""}>
                      <td className="px-4 py-2.5 font-bold">{k.name}</td>
                      <td className="px-4 py-2.5 text-ink/70">{k.type}</td>
                      <td className="px-4 py-2.5">{k.def}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            <p className="mt-3 font-mono text-xs text-ink/60">
              Set these on <code className="bg-ink px-1 text-paper">{typeName}.Configuration</code>{" "}
              and pass it to the initializer.
            </p>
          </Section>
        )}

        {/* Usage */}
        {component.usage && (
          <Section kicker="Usage">
            <CodeBlock code={component.usage} filename="usage.swift" maxHeight="auto" />
          </Section>
        )}

        {/* Source */}
        <Section kicker="Source">
          <div className="space-y-6">
            {component.files.map((f) => (
              <CodeBlock key={f.to} code={f.source} filename={f.to} />
            ))}
          </div>
        </Section>
      </main>
      <Footer />
    </>
  );
}

function Section({ kicker, children }: { kicker: string; children: React.ReactNode }) {
  return (
    <section className="mt-12">
      <div className="label mb-4 inline-block border-[3px] border-ink px-3 py-1">{kicker}</div>
      {children}
    </section>
  );
}
