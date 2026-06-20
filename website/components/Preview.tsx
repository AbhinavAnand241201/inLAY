/* Pure CSS/SVG mock previews so the gallery is alive even before screen
   recordings exist. Monochrome to match the brutalist B&W theme. */

function ToolbarPreview() {
  const icons = ["house", "search", "bell", "user"];
  return (
    <div className="flex items-center gap-1 border-[3px] border-ink bg-paper px-3 py-2 shadow-brut-sm">
      {icons.map((k, i) => (
        <div
          key={k}
          className={`flex h-9 w-9 items-center justify-center ${
            i === 0 ? "bg-ink text-paper" : "text-ink"
          }`}
        >
          <span className="h-3 w-3 border-2 border-current" />
        </div>
      ))}
    </div>
  );
}

function LoadingPreview() {
  return (
    <div className="flex items-center gap-8">
      {/* arc */}
      <div className="h-9 w-9 animate-spinArc rounded-full border-[3px] border-ink border-t-transparent" />
      {/* dots */}
      <div className="flex gap-1.5">
        {[0, 1, 2].map((i) => (
          <span
            key={i}
            className="h-2.5 w-2.5 animate-pulseDot rounded-full bg-ink"
            style={{ animationDelay: `${i * 0.16}s` }}
          />
        ))}
      </div>
      {/* bars */}
      <div className="flex items-end gap-1">
        {[0, 1, 2, 3].map((i) => (
          <span
            key={i}
            className="w-1.5 origin-bottom animate-pulseDot bg-ink"
            style={{ height: "28px", animationDelay: `${i * 0.12}s` }}
          />
        ))}
      </div>
    </div>
  );
}

function StatusPreview() {
  return (
    <div className="flex items-center gap-10">
      <svg width="64" height="64" viewBox="0 0 64 64" fill="none">
        <circle cx="32" cy="32" r="27" stroke="#000" strokeWidth="5" />
        <path
          d="M20 33 L28 42 L45 23"
          stroke="#000"
          strokeWidth="5"
          strokeLinecap="round"
          strokeLinejoin="round"
          strokeDasharray="48"
          className="animate-drawCheck"
        />
      </svg>
      <svg width="64" height="64" viewBox="0 0 64 64" fill="none">
        <circle cx="32" cy="32" r="27" stroke="#000" strokeWidth="5" strokeDasharray="6 6" />
        <path d="M23 23 L41 41 M41 23 L23 41" stroke="#000" strokeWidth="5" strokeLinecap="round" />
      </svg>
    </div>
  );
}

function SettingsPreview() {
  const rows = [
    { t: "Notifications", s: "Sounds, badges", acc: "chevron" },
    { t: "Dark Mode", s: null, acc: "toggle" },
  ];
  return (
    <div className="flex w-full max-w-[260px] flex-col gap-2">
      {rows.map((r) => (
        <div
          key={r.t}
          className="flex items-center gap-3 border-[3px] border-ink bg-paper px-3 py-2 shadow-brut-sm"
        >
          <div className="flex h-8 w-8 items-center justify-center bg-ink text-paper">
            <span className="h-3 w-3 border-2 border-current" />
          </div>
          <div className="flex-1">
            <div className="font-sans text-sm font-bold leading-tight">{r.t}</div>
            {r.s && <div className="font-mono text-[10px] uppercase tracking-wider text-ink/60">{r.s}</div>}
          </div>
          {r.acc === "chevron" ? (
            <span className="font-mono text-sm font-bold">›</span>
          ) : (
            <span className="flex h-5 w-9 items-center justify-end border-[3px] border-ink bg-ink p-0.5">
              <span className="h-3 w-3 bg-paper" />
            </span>
          )}
        </div>
      ))}
    </div>
  );
}

export function Preview({ name }: { name: string }) {
  switch (name) {
    case "floating-toolbar":
      return <ToolbarPreview />;
    case "loading-indicator":
      return <LoadingPreview />;
    case "status-feedback":
      return <StatusPreview />;
    case "settings-row":
      return <SettingsPreview />;
    default:
      return (
        <div className="font-mono text-xs uppercase tracking-widest text-ink/50">
          preview
        </div>
      );
  }
}
