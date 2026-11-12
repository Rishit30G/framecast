import Image from "next/image";

type Mark = { x: number; y: number; w: number; h: number; label?: string; avoid?: boolean; round?: boolean; below?: boolean };

/** A screenshot with pulsing outlines on what to click, and a muted "Not this" over what to avoid.
 *  Positions are percentages of the image. */
export default function InstallShot({ src, w, h, alt, marks = [], arrow, max = 760 }: {
  src: string; w: number; h: number; alt: string; marks?: Mark[]; arrow?: { from: [number, number]; to: [number, number] }; max?: number;
}) {
  return (
    <div className="mx-auto w-full" style={{ maxWidth: max }}>
      <div className="relative">
        <Image src={src} width={w} height={h} alt={alt} className="block h-auto w-full rounded-[18px] bg-zinc-900 shadow-[0_24px_60px_-30px_rgba(17,17,19,0.55)] ring-1 ring-black/10" unoptimized />
        {marks.map((m, i) => m.avoid ? (
          <div key={i} className="absolute flex items-center justify-center rounded-full bg-zinc-900/70 text-[clamp(10px,1.4vw,13px)] font-semibold text-zinc-300 ring-1 ring-white/20"
            style={{ left: `${m.x}%`, top: `${m.y}%`, width: `${m.w}%`, height: `${m.h}%` }}>Not this</div>
        ) : (
          <div key={i} className="absolute" style={{ left: `${m.x}%`, top: `${m.y}%`, width: `${m.w}%`, height: `${m.h}%` }}>
            <span className={`absolute -inset-1.5 animate-pulse ${m.round ? "rounded-full" : "rounded-[14px]"} shadow-[0_0_0_8px_rgba(229,55,43,0.28),0_0_24px_6px_rgba(229,55,43,0.35)] [animation-duration:1.6s] motion-reduce:hidden`} />
            <span className={`absolute -inset-1.5 ${m.round ? "rounded-full" : "rounded-[14px]"} border-[3px] border-record shadow-[0_0_0_4px_rgba(229,55,43,0.18)]`} />
            {m.label && (
              <span className={`absolute left-1/2 -translate-x-1/2 whitespace-nowrap rounded-full bg-record px-2.5 py-1 text-[clamp(10px,1.3vw,13px)] font-semibold text-white shadow-lg ${m.below ? "-bottom-2 translate-y-full" : "-top-2 -translate-y-full"}`}>
                {m.label}
              </span>
            )}
          </div>
        ))}
        {arrow && (
          <svg className="pointer-events-none absolute inset-0 h-full w-full" viewBox="0 0 100 100" preserveAspectRatio="none" aria-hidden>
            <defs><marker id="head" markerWidth="6" markerHeight="6" refX="3" refY="3" orient="auto"><path d="M0,0 L6,3 L0,6 z" fill="#e5372b" /></marker></defs>
            <path d={`M${arrow.from[0]},${arrow.from[1]} Q${(arrow.from[0] + arrow.to[0]) / 2},${Math.min(arrow.from[1], arrow.to[1]) - 22} ${arrow.to[0]},${arrow.to[1]}`}
              fill="none" stroke="#e5372b" strokeWidth="0.9" strokeDasharray="2.2 1.6" markerEnd="url(#head)" vectorEffect="non-scaling-stroke" style={{ strokeWidth: 3 }} />
          </svg>
        )}
      </div>
    </div>
  );
}
