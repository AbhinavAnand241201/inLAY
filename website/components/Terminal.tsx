import { CopyButton } from "./CopyButton";

/** A brutalist terminal block showing one install command + a copy button. */
export function Terminal({ command }: { command: string }) {
  return (
    <div className="brut-border bg-ink text-paper">
      <div className="flex items-center gap-2 border-b-[3px] border-paper/30 px-4 py-2">
        <span className="h-3 w-3 border-2 border-paper" />
        <span className="h-3 w-3 border-2 border-paper" />
        <span className="h-3 w-3 border-2 border-paper" />
        <span className="ml-2 font-mono text-xs uppercase tracking-widest text-paper/70">
          terminal
        </span>
      </div>
      <div className="flex items-center justify-between gap-4 px-4 py-4">
        <code className="overflow-x-auto whitespace-nowrap font-mono text-sm md:text-base">
          <span className="select-none text-paper/50">$ </span>
          {command}
        </code>
        <CopyButton text={command} className="border-paper bg-ink text-paper hover:bg-paper hover:text-ink" />
      </div>
    </div>
  );
}
