"use client";

import { useState } from "react";

export function CopyButton({
  text,
  label = "COPY",
  className = "",
}: {
  text: string;
  label?: string;
  className?: string;
}) {
  const [copied, setCopied] = useState(false);

  async function copy() {
    try {
      await navigator.clipboard.writeText(text);
      setCopied(true);
      setTimeout(() => setCopied(false), 1400);
    } catch {
      /* clipboard blocked — ignore */
    }
  }

  return (
    <button
      onClick={copy}
      className={`shrink-0 border-[3px] border-ink px-3 py-1 font-mono text-xs font-bold uppercase tracking-wider transition-all ${
        copied ? "bg-ink text-paper" : "bg-paper text-ink hover:bg-ink hover:text-paper"
      } ${className}`}
      aria-label="Copy to clipboard"
    >
      {copied ? "COPIED ✓" : label}
    </button>
  );
}
