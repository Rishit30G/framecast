"use client";
import { AnimatePresence, motion } from "motion/react";
import { Plus } from "lucide-react";
import { useState } from "react";
import { FAQ } from "@/lib/site";

export default function Faq() {
  const [open, setOpen] = useState<number | null>(0);
  return (
    <div className="mx-auto max-w-3xl divide-y divide-line rounded-[24px] border border-line bg-white px-5 sm:px-8">
      {FAQ.map(([q, a], i) => {
        const on = open === i;
        return (
          <div key={q}>
            <button type="button" onClick={() => setOpen(on ? null : i)} aria-expanded={on}
              className="flex w-full items-center justify-between gap-6 py-5 text-left text-[16.5px] font-medium tracking-[-0.02em]">
              {q}
              <motion.span animate={{ rotate: on ? 45 : 0 }} className="flex size-7 shrink-0 items-center justify-center rounded-full bg-zinc-100 text-zinc-500">
                <Plus className="size-4" />
              </motion.span>
            </button>
            <AnimatePresence initial={false}>
              {on && (
                <motion.div initial={{ height: 0, opacity: 0 }} animate={{ height: "auto", opacity: 1 }} exit={{ height: 0, opacity: 0 }}
                  transition={{ duration: 0.35, ease: [0.22, 1, 0.36, 1] }} className="overflow-hidden">
                  <p className="pb-5 pr-10 text-[15.5px] leading-relaxed text-muted">{a}</p>
                </motion.div>
              )}
            </AnimatePresence>
          </div>
        );
      })}
    </div>
  );
}
