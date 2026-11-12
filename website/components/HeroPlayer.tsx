"use client";
import { motion } from "motion/react";
import { useEffect, useRef, useState } from "react";
import { Pause, Play } from "lucide-react";
import { HERO_TRACKS, MEDIA_V } from "@/lib/site";

const TOTAL = 12;

/** The hero clip with a copy of Framecast's timeline underneath, kept in step with the video. */
export default function HeroPlayer() {
  const video = useRef<HTMLVideoElement>(null);
  const head = useRef<HTMLSpanElement>(null);
  const clock = useRef<HTMLSpanElement>(null);
  const lanes = useRef<HTMLDivElement>(null);
  const [paused, setPaused] = useState(false);

  useEffect(() => {
    const v = video.current!;
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) { v.pause(); setPaused(true); }
    else v.play().catch(() => setPaused(true));
    let raf = 0;
    const tick = () => {
      const t = Math.min(v.currentTime || 0, TOTAL);
      if (head.current) head.current.style.left = `calc(${(t / TOTAL) * 100}% - 1px)`;
      if (clock.current) clock.current.textContent = `0:${t.toFixed(1).padStart(4, "0")}`;
      lanes.current?.querySelectorAll<HTMLElement>("[data-s]").forEach((p) => {
        p.dataset.on = String(t >= +p.dataset.s! && t < +p.dataset.e!);
      });
      raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, []);

  const toggle = () => { const v = video.current!; if (v.paused) { v.play(); setPaused(false); } else { v.pause(); setPaused(true); } };
  const seek = (e: React.MouseEvent<HTMLDivElement>) => {
    const r = e.currentTarget.getBoundingClientRect();
    video.current!.currentTime = Math.min(Math.max((e.clientX - r.left) / r.width, 0), 1) * TOTAL;
  };

  return (
    <motion.div initial={{ opacity: 0, y: 40, scale: 0.97 }} animate={{ opacity: 1, y: 0, scale: 1 }}
      transition={{ delay: 0.55, duration: 1.1, ease: [0.22, 1, 0.36, 1] }} className="relative">
      <div aria-hidden className="pointer-events-none absolute -inset-x-10 -top-10 bottom-10 -z-10 rounded-[48px] bg-[radial-gradient(60%_60%_at_50%_40%,rgba(91,91,214,0.22),transparent_70%),radial-gradient(40%_50%_at_80%_70%,rgba(229,55,43,0.14),transparent_70%)] blur-2xl" />
      <div className="rounded-[28px] border border-black/[0.06] bg-white p-2 shadow-[0_40px_100px_-40px_rgba(17,17,19,0.45)] sm:p-2.5">
        <video ref={video} muted loop playsInline preload="auto" poster={`/media/hero.jpg?v=${MEDIA_V}`}
          className="aspect-[1600/1048] w-full rounded-[20px] bg-zinc-200 object-cover"
          aria-label="A presenter talks to camera full screen, then shrinks into a rounded corner as a dashboard recording appears. The video zooms in on a click, spotlights a card and zooms on a chart, then she fills the screen again.">
          <source src={`/media/hero.mp4?v=${MEDIA_V}`} type="video/mp4" />
        </video>
      </div>
      <div className="mt-2.5 rounded-[20px] bg-[#18181b] p-3.5 text-left text-zinc-300 shadow-[0_20px_60px_-30px_rgba(0,0,0,0.6)] sm:p-4" aria-label="The Framecast timeline for this clip">
        <div className="mb-3 flex items-center justify-between text-[12.5px] font-medium tracking-[-0.01em] text-zinc-400">
          <button type="button" onClick={toggle} className="flex items-center gap-1.5 text-zinc-200 hover:text-white" aria-label={paused ? "Play" : "Pause"}>
            {paused ? <Play className="size-3.5 fill-current" /> : <Pause className="size-3.5 fill-current" />}{paused ? "Play" : "Pause"}
          </button>
          <span className="tnum"><span ref={clock} className="text-white">0:00.0</span> / 0:12.0</span>
        </div>
        <div className="grid grid-cols-[58px_1fr] gap-x-2.5 sm:grid-cols-[76px_1fr] sm:gap-x-3">
          <div className="grid gap-1.5">
            {HERO_TRACKS.map((t) => <div key={t.name} className="h-[22px] text-[11px] font-medium leading-[22px] text-zinc-500 sm:text-[12px]">{t.name}</div>)}
          </div>
          <div ref={lanes} onClick={seek} className="relative grid cursor-pointer gap-1.5">
            {HERO_TRACKS.map((t) => (
              <div key={t.name} className="relative h-[22px] rounded-md bg-white/[0.05]">
                {t.pills.map(([s, e, label]) => (
                  <span key={label} data-s={s} data-e={e}
                    className="absolute inset-y-0 truncate rounded-md px-1.5 text-[10.5px] font-medium leading-[22px] text-white opacity-50 transition-opacity duration-200 data-[on=true]:opacity-100 sm:px-2 sm:text-[11.5px]"
                    style={{ left: `${(s / TOTAL) * 100}%`, width: `${((e - s) / TOTAL) * 100}%`, background: t.color }}>{label}</span>
                ))}
              </div>
            ))}
            <span ref={head} className="pointer-events-none absolute -bottom-1 -top-1 w-0.5 rounded bg-white shadow-[0_0_0_1px_rgba(0,0,0,0.4)]" />
          </div>
        </div>
      </div>
    </motion.div>
  );
}
