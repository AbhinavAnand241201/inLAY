import Link from "next/link";
import { Nav } from "@/components/Nav";
import { Footer } from "@/components/Footer";
import { Terminal } from "@/components/Terminal";
import { components } from "@/lib/registry";

export default function Home() {
  return (
    <>
      <Nav />
      <main>
        <Hero />
        <Marquee />
        <HowItWorks />
        <WhyInlay />
        <About />
        <CTA />
      </main>
      <Footer />
    </>
  );
}

function Hero() {
  return (
    <section className="border-b-[3px] border-ink">
      <div className="mx-auto max-w-6xl px-5 py-16 md:py-24">
        <div className="label inline-block border-[3px] border-ink px-3 py-1">
          shadcn/ui — but for iOS
        </div>
        <h1 className="mt-6 font-sans text-5xl font-black uppercase leading-[0.95] tracking-tight md:text-8xl">
          Copy-paste
          <br />
          UIKit
          <br />
          <span className="bg-ink px-2 text-paper">components.</span>
        </h1>
        <p className="mt-8 max-w-2xl font-mono text-base leading-relaxed md:text-lg">
          Search a component, run one command, and the source lands in your Xcode
          project — animated, polished, ready to customize. You{" "}
          <span className="bg-ink px-1 text-paper">own the code</span>. Inlay isn&apos;t a
          dependency you import.
        </p>
        <div className="mt-10 max-w-2xl">
          <Terminal command="inlay add floating-toolbar" />
        </div>
        <div className="mt-8 flex flex-wrap gap-4">
          <Link href="/components" className="brut-btn text-base">
            Browse components →
          </Link>
          <Link href="/#how" className="brut-btn-ghost text-base">
            How it works
          </Link>
        </div>
      </div>
    </section>
  );
}

function Marquee() {
  const words = [
    "ZERO DEPENDENCIES",
    "100% PROGRAMMATIC",
    "iOS 16+",
    "DARK MODE READY",
    "SPRING ANIMATIONS",
    "BUILDABLE-FOLDER INSTALL",
    "YOU OWN THE CODE",
  ];
  const strip = [...words, ...words];
  return (
    <section className="overflow-hidden border-b-[3px] border-ink bg-ink py-3 text-paper">
      <div className="flex w-max animate-marquee gap-8 whitespace-nowrap font-mono text-sm font-bold uppercase tracking-widest">
        {strip.map((w, i) => (
          <span key={i} className="flex items-center gap-8">
            {w} <span className="text-paper/40">✦</span>
          </span>
        ))}
      </div>
    </section>
  );
}

function HowItWorks() {
  const steps = [
    {
      n: "01",
      t: "Find it",
      d: "Browse the gallery. Every component has live previews, every variant, and the exact install command.",
    },
    {
      n: "02",
      t: "Run one command",
      d: "inlay add <name> writes the Swift into your project's source folder. Dependencies resolve automatically. It compiles instantly.",
    },
    {
      n: "03",
      t: "Own it",
      d: "The code is yours — customize through one Configuration struct, or rewrite it entirely. No package, no lock-in, no updates breaking your app.",
    },
  ];
  return (
    <section id="how" className="border-b-[3px] border-ink">
      <div className="mx-auto max-w-6xl px-5 py-16 md:py-24">
        <SectionTitle kicker="The flow" title="Three steps. Under five minutes." />
        <div className="mt-12 grid gap-6 md:grid-cols-3">
          {steps.map((s) => (
            <div key={s.n} className="brut-card p-6">
              <div className="font-mono text-5xl font-black">{s.n}</div>
              <div className="mt-4 font-sans text-2xl font-black uppercase">{s.t}</div>
              <p className="mt-3 font-mono text-sm leading-relaxed text-ink/80">{s.d}</p>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}

function WhyInlay() {
  const features = [
    { t: "Self-contained", d: "A single pasted component compiles with zero setup. No shared theme required." },
    { t: "Zero external deps", d: "Only UIKit + Foundation and other Inlay pieces (copied in). Never an SPM package." },
    { t: "Collision-safe", d: "Shared primitives nest under the Inlay namespace; helper types nest inside the component." },
    { t: "Animation-first", d: "One spring vocabulary across every component. Custom UIKit animation, already done for you." },
    { t: "Auto dark mode", d: "Dynamic system colors throughout — light and dark just work." },
    { t: "Buildable-folder install", d: "Files land inside your Xcode 16 synchronized folder, so they build with no project edits." },
  ];
  return (
    <section className="border-b-[3px] border-ink bg-ink text-paper">
      <div className="mx-auto max-w-6xl px-5 py-16 md:py-24">
        <SectionTitle kicker="Why Inlay" title="The hard part, handed to you." invert />
        <div className="mt-12 grid gap-px border-[3px] border-paper bg-paper md:grid-cols-2 lg:grid-cols-3">
          {features.map((f) => (
            <div key={f.t} className="bg-ink p-6">
              <div className="font-sans text-xl font-black uppercase">{f.t}</div>
              <p className="mt-2 font-mono text-sm leading-relaxed text-paper/70">{f.d}</p>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}

function About() {
  return (
    <section id="about" className="border-b-[3px] border-ink">
      <div className="mx-auto max-w-6xl px-5 py-16 md:py-24">
        <SectionTitle kicker="The creator" title="Built by Abhinav." />
        <div className="mt-12 grid gap-8 md:grid-cols-[200px_1fr]">
          <div className="brut-card flex aspect-square items-center justify-center bg-ink text-paper shadow-brut-lg">
            <span className="font-sans text-7xl font-black">A</span>
          </div>
          <div>
            <p className="font-mono text-lg leading-relaxed">
              I&apos;m <span className="bg-ink px-1 text-paper">Abhinav</span>, an iOS
              developer. I kept rewriting the same animated UIKit boilerplate on every
              project — floating bars, loaders, success checkmarks, settings rows — so I
              built Inlay to never write them again, and to hand them to you the way
              shadcn hands React devs their components.
            </p>
            <p className="mt-4 font-mono text-sm leading-relaxed text-ink/70">
              Every component is real, compiling Swift — programmatic, collision-safe,
              dark-mode ready, and animated with one shared spring vocabulary. Take the
              code, make it yours, ship it.
            </p>
            <div className="mt-6 flex flex-wrap gap-3">
              <a href="https://github.com/" target="_blank" rel="noreferrer" className="brut-btn-ghost">
                GitHub
              </a>
              <a href="https://twitter.com/" target="_blank" rel="noreferrer" className="brut-btn-ghost">
                Twitter / X
              </a>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}

function CTA() {
  return (
    <section className="border-b-[3px] border-ink">
      <div className="mx-auto max-w-6xl px-5 py-16 text-center md:py-24">
        <h2 className="font-sans text-4xl font-black uppercase leading-tight md:text-6xl">
          {components.length} components.
          <br />
          One command each.
        </h2>
        <div className="mt-10 flex justify-center">
          <Link href="/components" className="brut-btn text-lg">
            Open the gallery →
          </Link>
        </div>
      </div>
    </section>
  );
}

function SectionTitle({
  kicker,
  title,
  invert,
}: {
  kicker: string;
  title: string;
  invert?: boolean;
}) {
  return (
    <div>
      <div className={`label ${invert ? "text-paper/60" : "text-ink/60"}`}>{kicker}</div>
      <h2 className="mt-3 max-w-3xl font-sans text-4xl font-black uppercase leading-[1.05] tracking-tight md:text-6xl">
        {title}
      </h2>
    </div>
  );
}
