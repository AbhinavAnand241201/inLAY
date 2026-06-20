import { CopyButton } from "./CopyButton";

/**
 * Monochrome code block — no syntax colors, on purpose (black & white only).
 * The brutalist frame + monospace does the work.
 */
export function CodeBlock({
  code,
  filename,
  maxHeight = "32rem",
}: {
  code: string;
  filename?: string;
  maxHeight?: string;
}) {
  return (
    <div className="brut-card">
      <div className="flex items-center justify-between border-b-[3px] border-ink px-4 py-2">
        <span className="font-mono text-xs font-bold uppercase tracking-wider">
          {filename ?? "swift"}
        </span>
        <CopyButton text={code} />
      </div>
      <pre
        className="no-scrollbar overflow-auto p-4 font-mono text-[12px] leading-relaxed"
        style={{ maxHeight }}
      >
        <code>{code}</code>
      </pre>
    </div>
  );
}
