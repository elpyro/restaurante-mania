"use client";

import { useState } from "react";
import { Play } from "lucide-react";

type Props = {
  src: string;
  title?: string;
  poster?: string;
};

export function LazyVideo({ src, title, poster }: Props) {
  const [playing, setPlaying] = useState(false);

  if (playing) {
    return (
      <video
        src={src}
        controls
        autoPlay
        playsInline
        preload="metadata"
        className="aspect-video w-full rounded-xl bg-black object-contain"
      />
    );
  }

  return (
    <button
      type="button"
      onClick={() => setPlaying(true)}
      className="group relative aspect-video w-full overflow-hidden rounded-xl bg-black"
      aria-label={title ? `Reproducir video: ${title}` : "Reproducir video"}
    >
      {poster ? (
        // eslint-disable-next-line @next/next/no-img-element
        <img src={poster} alt="" className="h-full w-full object-cover opacity-80 transition group-hover:opacity-100" />
      ) : (
        <div className="h-full w-full bg-gradient-to-br from-stone-800 to-stone-900" />
      )}
      <span className="absolute inset-0 grid place-items-center">
        <span className="grid h-16 w-16 place-items-center rounded-full bg-white/90 text-brand shadow-lg transition group-hover:scale-110">
          <Play size={28} className="ml-1 fill-current" />
        </span>
      </span>
      <span className="absolute bottom-3 left-3 rounded-full bg-black/60 px-3 py-1 text-xs font-semibold text-white">
        Ver video
      </span>
    </button>
  );
}
