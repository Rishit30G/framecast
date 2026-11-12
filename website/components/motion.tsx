"use client";
import { MotionConfig, motion, useInView, animate, type Variants } from "motion/react";
import { useEffect, useRef, type ReactNode } from "react";

export function MotionProvider({ children }: { children: ReactNode }) {
  return <MotionConfig reducedMotion="user" transition={{ ease: [0.22, 1, 0.36, 1], duration: 0.7 }}>{children}</MotionConfig>;
}

export function Reveal({ children, className, delay = 0 }: { children: ReactNode; className?: string; delay?: number }) {
  return (
    <motion.div className={className} initial={{ opacity: 0, y: 18 }} whileInView={{ opacity: 1, y: 0 }}
      viewport={{ once: true, margin: "-60px" }} transition={{ delay }}>
      {children}
    </motion.div>
  );
}

const parent: Variants = { hidden: {}, show: { transition: { staggerChildren: 0.08 } } };
const child: Variants = { hidden: { opacity: 0, y: 18 }, show: { opacity: 1, y: 0 } };

export function Stagger({ children, className }: { children: ReactNode; className?: string }) {
  return <motion.div className={className} variants={parent} initial="hidden" whileInView="show" viewport={{ once: true, margin: "-60px" }}>{children}</motion.div>;
}
export function StaggerItem({ children, className }: { children: ReactNode; className?: string }) {
  return <motion.div className={className} variants={child}>{children}</motion.div>;
}

/** Counts up from zero the first time it scrolls into view. */
export function Counter({ to, className }: { to: number; className?: string }) {
  const ref = useRef<HTMLSpanElement>(null);
  const seen = useInView(ref, { once: true, amount: 0.6 });
  useEffect(() => {
    if (!seen || !ref.current) return;
    const el = ref.current;
    const c = animate(0, to, { duration: 1.1, ease: [0.22, 1, 0.36, 1], onUpdate: (v) => { el.textContent = Math.round(v).toString(); } });
    return () => c.stop();
  }, [seen, to]);
  return <span ref={ref} className={className}>{to}</span>;
}

/** Hero headline: words rise in one after another. */
export function Words({ text, accent }: { text: string; accent?: string }) {
  const words = text.split(" ");
  return (
    <>
      {words.map((w, i) => (
        <motion.span key={i} className={`inline-block ${accent && w.includes(accent) ? "text-record" : ""}`}
          initial={{ opacity: 0, y: 24, filter: "blur(8px)" }} animate={{ opacity: 1, y: 0, filter: "blur(0px)" }}
          transition={{ delay: 0.08 + i * 0.06, duration: 0.8 }}>
          {w}{i < words.length - 1 ? " " : ""}
        </motion.span>
      ))}
    </>
  );
}

export const Fade = motion.div;
