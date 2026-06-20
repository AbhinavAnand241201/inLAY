# Inlay website

A Next.js (App Router, TypeScript, Tailwind) gallery for Inlay — a **brutalist,
black & white** take on the shadcn/ui docs site.

- **Landing** (`/`) — hero, marquee, how-it-works, why-Inlay, and the *About the
  creator* section. No component gallery here, by design.
- **Components** (`/components`) — the catalog, grouped by category, read from
  `data/registry.json`. Each card has an animated preview + the install command.
- **Component detail** (`/components/[name]`) — demo surface, install command,
  dependencies, variants, an auto-generated **Customize** table parsed from the
  Swift `Configuration`, the usage snippet, and the full source.

## Develop

```bash
npm install
npm run dev          # http://localhost:3000
```

## Build (static export)

```bash
npm run build        # → out/  (fully static, host anywhere)
npx serve out        # preview the production build
```

`next.config.mjs` sets `output: "export"`, so the site is plain static files —
deploy `out/` to GitHub Pages, Netlify, Vercel, or any bucket.

## Data

The catalog is driven by `data/registry.json`, a synced copy of the generated
artifact. Refresh it (after changing components) from the repo root:

```bash
./scripts/sync-registry.sh
```

## Demo videos

Each component detail page looks for a screen recording at
`public/demos/<component-name>.mp4`. If none exists, it falls back to an animated
CSS/SVG preview. Drop `.mp4` files into `public/demos/` to show real footage —
no code changes needed.

## Theme

Pure black & white, 3px borders, hard offset shadows (`shadow-brut`), Space
Grotesk + Space Mono. Tokens live in `tailwind.config.ts`; reusable classes
(`.brut-card`, `.brut-btn`, `.label`) are in `app/globals.css`.
