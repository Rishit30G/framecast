"use client";
import { motion } from "motion/react";
import { Check, Sparkles, Undo2 } from "lucide-react";

const STYLE = [
  ["Sound", "Always clean up my voice."],
  ["Fades", "None by default. Fade only on long cuts."],
  ["Look", "Start with no background, edge to edge."],
  ["Camera", "Full screen when I'm only talking. Normal view when I'm showing something."],
  ["Text", "Small, short, never over my face."],
  ["Private things", "Always blur keys, emails and passwords."],
];

const STEPS = [
  ["Read your style, the transcript and 12 pauses", "0.4s"],
  ["Cleaned up your voice", ""],
  ["Removed 8 pauses", "−13.4s"],
  ["Camera full screen while you talk", "15.0–28.0"],
  ["Zoomed in on the settings panel", "31.8–34.6"],
  ["Blurred an API key on screen", "41.2–46.1"],
  ["Turned on captions", "32 lines"],
];

export default function AiDemo() {
  return (
    <div className="grid gap-4 md:grid-cols-2">
      <motion.div initial={{ opacity: 0, y: 24 }} whileInView={{ opacity: 1, y: 0 }} viewport={{ once: true, margin: "-60px" }}
        className="rounded-[24px] bg-[#f7f5ef] p-6 text-[#26272b] sm:p-8">
        <div className="mb-5 flex items-baseline justify-between">
          <p className="text-[15px] font-semibold tracking-[-0.02em]">My editing style</p>
          <p className="text-[12.5px] text-zinc-500">plain English, any text editor</p>
        </div>
        <dl className="grid gap-4">
          {STYLE.map(([h, t]) => (
            <div key={h} className="grid gap-1 border-t border-black/[0.07] pt-3">
              <dt className="text-[13px] font-semibold tracking-[-0.01em] text-zinc-500">{h}</dt>
              <dd className="text-[15px] leading-snug tracking-[-0.01em]">{t}</dd>
            </div>
          ))}
        </dl>
      </motion.div>
      <motion.div initial="hidden" whileInView="show" viewport={{ once: true, margin: "-60px" }}
        variants={{ hidden: {}, show: { transition: { staggerChildren: 0.28, delayChildren: 0.3 } } }}
        className="flex flex-col rounded-[24px] border border-white/10 bg-white/[0.04] p-6 sm:p-8">
        <div className="mb-5 flex items-center gap-2.5 text-[15px] font-semibold tracking-[-0.02em] text-white">
          <span className="flex size-7 items-center justify-center rounded-lg bg-[#d97757]"><Sparkles className="size-4 text-white" /></span>
          Claude edited “Product walkthrough”
        </div>
        <ul className="grid gap-1">
          {STEPS.map(([t, d]) => (
            <motion.li key={t} variants={{ hidden: { opacity: 0, x: -10 }, show: { opacity: 1, x: 0 } }}
              className="flex items-center gap-3 rounded-xl px-2 py-2 text-[14.5px] tracking-[-0.01em] text-zinc-300">
              <span className="flex size-5 items-center justify-center rounded-full bg-emerald-500/15 text-emerald-400"><Check className="size-3" strokeWidth={3} /></span>
              <span className="flex-1">{t}</span>
              <span className="tnum text-[13px] text-zinc-500">{d}</span>
            </motion.li>
          ))}
        </ul>
        <motion.div variants={{ hidden: { opacity: 0, y: 8 }, show: { opacity: 1, y: 0 } }}
          className="mt-auto flex flex-wrap items-center justify-between gap-3 border-t border-white/10 pt-5 text-[14px]">
          <span className="font-medium text-white">93.6s → 73.6s</span>
          <span className="flex items-center gap-1.5 rounded-full bg-white/10 px-3 py-1.5 text-[13px] text-zinc-200"><Undo2 className="size-3.5" />Updated by Claude · ⌘Z to undo</span>
        </motion.div>
      </motion.div>
    </div>
  );
}
