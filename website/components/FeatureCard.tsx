"use client";
import { motion, useInView } from "motion/react";
import { useEffect, useRef } from "react";
import { Icon } from "./icons";
import { MEDIA_V } from "@/lib/site";

/** A looping clip that only loads and plays while it's on screen. */
export function Clip({ name, label, className }: { name: string; label: string; className?: string }) {
  const ref = useRef<HTMLVideoElement>(null);
  const visible = useInView(ref, { amount: 0.35 });
  useEffect(() => {
    const v = ref.current; if (!v) return;
    if (visible && !window.matchMedia("(prefers-reduced-motion: reduce)").matches) { v.preload = "auto"; v.play().catch(() => {}); }
    else v.pause();
  }, [visible]);
  return (
    <video ref={ref} muted loop playsInline preload="none" poster={`/media/${name}.jpg?v=${MEDIA_V}`} aria-label={label} className={className}>
      <source src={`/media/${name}.mp4?v=${MEDIA_V}`} type="video/mp4" />
    </video>
  );
}

export function IconTile({ name, color }: { name: string; color: string }) {
  return (
    <span className="flex size-9 items-center justify-center rounded-[10px] text-white shadow-[inset_0_1px_0_rgba(255,255,255,0.3),0_4px_10px_-4px_rgba(0,0,0,0.3)]" style={{ background: color }}>
      <Icon name={name} className="size-[18px]" />
    </span>
  );
}

export function Chips({ items, dark = false }: { items: readonly string[]; dark?: boolean }) {
  return (
    <ul className="flex flex-wrap gap-1.5">
      {items.map((c) => (
        <li key={c} className={`rounded-full px-2.5 py-1 text-[12.5px] font-medium tracking-[-0.01em] ring-1 ring-inset ${
          dark ? "bg-white/5 text-zinc-300 ring-white/10" : "bg-zinc-50 text-zinc-600 ring-black/[0.06]"}`}>{c}</li>
      ))}
    </ul>
  );
}

export default function FeatureCard({ f }: { f: { slug: string; icon: string; color: string; title: string; text: string; chips: string[]; label: string; portrait?: boolean } }) {
  return (
    <motion.article whileHover={{ y: -4 }} transition={{ type: "spring", stiffness: 300, damping: 24 }}
      className="group flex h-full flex-col rounded-[26px] border border-black/[0.06] bg-white p-2 shadow-[0_1px_2px_rgba(0,0,0,0.04)] transition-shadow duration-300 hover:shadow-[0_30px_60px_-30px_rgba(17,17,19,0.35)]">
      <div className="overflow-hidden rounded-[20px] bg-zinc-100">
        {f.portrait ? (
          <div className="flex aspect-[1120/734] w-full items-center justify-center bg-[radial-gradient(circle_at_50%_30%,#e4e4ea,#d4d5dc)] py-5">
            <Clip name={f.slug} label={f.label} className="h-full rounded-[14px] shadow-[0_20px_40px_-18px_rgba(0,0,0,0.5)]" />
          </div>
        ) : (
          <Clip name={f.slug} label={f.label} className="aspect-[1120/734] w-full object-cover transition-transform duration-700 group-hover:scale-[1.015]" />
        )}
      </div>
      <div className="flex flex-1 flex-col gap-3 px-4 pb-5 pt-5 sm:px-5">
        <IconTile name={f.icon} color={f.color} />
        <h3 className="text-[24px] font-semibold leading-tight tracking-[-0.04em]">{f.title}</h3>
        <p className="text-[15.5px] leading-relaxed tracking-[-0.01em] text-muted">{f.text}</p>
        <div className="mt-auto pt-1"><Chips items={f.chips} /></div>
      </div>
    </motion.article>
  );
}

/** One feature per row: the clip on one side, the words on the other, swapping sides each row. */
export function FeatureRow({ f, flip }: { f: Parameters<typeof FeatureCard>[0]["f"]; flip: boolean }) {
  return (
    <motion.article
      initial={{ opacity: 0, y: 32 }} whileInView={{ opacity: 1, y: 0 }} viewport={{ once: true, margin: "-80px" }}
      transition={{ duration: 0.8, ease: [0.22, 1, 0.36, 1] }}
      className={`grid items-center gap-8 md:gap-14 lg:gap-16 ${flip ? "md:grid-cols-[1fr_1.5fr]" : "md:grid-cols-[1.5fr_1fr]"}`}>
      <motion.div
        initial={{ opacity: 0, x: flip ? 40 : -40 }} whileInView={{ opacity: 1, x: 0 }} viewport={{ once: true, margin: "-80px" }}
        transition={{ duration: 0.9, ease: [0.22, 1, 0.36, 1] }}
        className={`group rounded-[28px] border border-black/[0.06] bg-white p-2 shadow-[0_30px_70px_-40px_rgba(17,17,19,0.45)] ${flip ? "md:order-2" : ""}`}>
        <div className="overflow-hidden rounded-[22px] bg-zinc-100">
          {f.portrait ? (
            <div className="flex aspect-[1120/734] w-full items-center justify-center bg-[radial-gradient(circle_at_50%_30%,#e4e4ea,#d4d5dc)] py-6">
              <Clip name={f.slug} label={f.label} className="h-full rounded-[14px] shadow-[0_20px_40px_-18px_rgba(0,0,0,0.5)]" />
            </div>
          ) : (
            <Clip name={f.slug} label={f.label} className="aspect-[1120/734] w-full object-cover transition-transform duration-700 group-hover:scale-[1.01]" />
          )}
        </div>
      </motion.div>
      <div className={`flex flex-col items-start gap-4 ${flip ? "md:order-1" : ""}`}>
        <IconTile name={f.icon} color={f.color} />
        <h3 className="text-balance text-[clamp(1.7rem,3vw,2.4rem)] font-semibold leading-[1.05] tracking-[-0.045em]">{f.title}</h3>
        <p className="max-w-md text-[16.5px] leading-relaxed tracking-[-0.01em] text-muted md:text-[17.5px]">{f.text}</p>
        <div className="pt-1"><Chips items={f.chips} /></div>
      </div>
    </motion.article>
  );
}
