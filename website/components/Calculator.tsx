"use client";
import { animate } from "motion/react";
import { useEffect, useRef, useState } from "react";

function Rolling({ value, decimals = 0 }: { value: number; decimals?: number }) {
  const ref = useRef<HTMLSpanElement>(null);
  const last = useRef(value);
  useEffect(() => {
    const el = ref.current; if (!el) return;
    const c = animate(last.current, value, { duration: 0.5, ease: "easeOut",
      onUpdate: (v) => { el.textContent = v.toLocaleString(undefined, { maximumFractionDigits: decimals, minimumFractionDigits: decimals }); } });
    last.current = value;
    return () => c.stop();
  }, [value, decimals]);
  return <span ref={ref} className="tnum">{value.toLocaleString()}</span>;
}

function Slider({ id, label, value, set, min, max, step = 1, show }: {
  id: string; label: string; value: number; set: (n: number) => void; min: number; max: number; step?: number; show: string;
}) {
  return (
    <div className="grid gap-2.5">
      <label htmlFor={id} className="flex items-baseline justify-between gap-4 text-[14.5px] tracking-[-0.01em] text-zinc-300">
        {label}<span className="tnum shrink-0 font-semibold text-white">{show}</span>
      </label>
      <input id={id} type="range" min={min} max={max} step={step} value={value} onChange={(e) => set(+e.target.value)}
        className="h-1.5 w-full cursor-pointer appearance-none rounded-full bg-white/10 accent-[#e5372b]" />
    </div>
  );
}

export default function Calculator() {
  const [videos, setVideos] = useState(8);
  const [minutes, setMinutes] = useState(45);
  const hours = (videos * minutes * 12) / 60;
  return (
    <div className="grid overflow-hidden rounded-[28px] bg-ink text-white shadow-[0_40px_80px_-40px_rgba(17,17,19,0.6)] md:grid-cols-2">
      <div className="grid min-w-0 content-center gap-8 p-6 sm:p-10">
        <div>
          <h3 className="text-[24px] font-semibold tracking-[-0.035em]">How much editing could you hand off?</h3>
          <p className="mt-2 text-[15px] text-zinc-400">Two questions about how you work today.</p>
        </div>
        <Slider id="v" label="Videos you make each month" value={videos} set={setVideos} min={1} max={40} show={`${videos}`} />
        <Slider id="m" label="Minutes you spend editing each one" value={minutes} set={setMinutes} min={5} max={180} step={5} show={`${minutes} min`} />
      </div>
      <div className="relative grid min-w-0 content-center gap-3 bg-white/[0.04] p-6 sm:p-10" aria-live="polite">
        <div aria-hidden className="pointer-events-none absolute -right-20 -top-20 size-72 rounded-full bg-record/25 blur-3xl" />
        <p className="relative text-[15px] text-zinc-400">Each year, that&apos;s</p>
        <p className="relative text-[clamp(2.8rem,6.5vw,4.6rem)] font-semibold leading-none tracking-[-0.05em]">
          <Rolling value={Math.round(hours)} /> hours
        </p>
        <p className="relative text-[17px] text-zinc-300">
          or <span className="font-semibold text-white"><Rolling value={hours / 8} decimals={1} /> working days</span> of editing you could give to Claude.
        </p>
      </div>
    </div>
  );
}
