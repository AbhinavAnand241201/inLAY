"use client";

import { useState } from "react";
import { Preview } from "./Preview";

/**
 * The demo surface for a component. Shows a screen recording at
 * /demos/<name>.mp4 if one exists, otherwise an animated CSS preview.
 * Drop a .mp4 into website/public/demos to light up the real footage.
 */
export function DemoFrame({ name }: { name: string }) {
  const [hasVideo, setHasVideo] = useState(true);

  return (
    <div className="relative flex min-h-[280px] items-center justify-center overflow-hidden border-[3px] border-ink bg-[repeating-linear-gradient(45deg,#fff,#fff_12px,#f4f4f4_12px,#f4f4f4_24px)] p-8">
      <span className="absolute left-3 top-3 label text-ink/50">DEMO</span>
      {hasVideo ? (
        <video
          className="max-h-[360px] border-[3px] border-ink bg-paper"
          autoPlay
          loop
          muted
          playsInline
          onError={() => setHasVideo(false)}
        >
          <source src={`/demos/${name}.mp4`} type="video/mp4" />
        </video>
      ) : (
        <Preview name={name} />
      )}
    </div>
  );
}
