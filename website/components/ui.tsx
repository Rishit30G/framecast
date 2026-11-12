import Link from "next/link";
import type { ReactNode } from "react";
import { Download } from "lucide-react";
import { GithubIcon } from "./icons";
import { GITHUB } from "@/lib/site";

export function Badge({ children, dark = false }: { children: ReactNode; dark?: boolean }) {
  return (
    <span className={`inline-flex w-fit shrink-0 items-center gap-2 self-auto rounded-full border px-3 py-1 text-[13px] font-medium tracking-tight shadow-[0_1px_2px_rgba(0,0,0,0.04)] ${
      dark ? "border-white/10 bg-white/[0.06] text-zinc-300" : "border-black/[0.07] bg-white/80 text-zinc-600"}`}>
      <span className="relative flex size-2">
        <span className="absolute inline-flex size-full animate-ping rounded-full bg-record opacity-40 motion-reduce:hidden" />
        <span className="relative inline-flex size-2 rounded-full bg-record" />
      </span>
      {children}
    </span>
  );
}

export function SectionHead({ badge, title, lede, dark = false, center = false }: {
  badge: string; title: ReactNode; lede?: ReactNode; dark?: boolean; center?: boolean;
}) {
  return (
    <div className={`mb-12 flex max-w-3xl flex-col gap-5 md:mb-16 ${center ? "mx-auto items-center text-center" : "items-start"}`}>
      <Badge dark={dark}>{badge}</Badge>
      <h2 className={`text-balance text-[clamp(2.1rem,4.6vw,3.6rem)] font-semibold leading-[1.02] tracking-[-0.045em] ${dark ? "text-white" : "text-ink"}`}>{title}</h2>
      {lede && <p className={`max-w-2xl text-[17px] leading-relaxed tracking-[-0.01em] md:text-lg ${dark ? "text-zinc-400" : "text-muted"}`}>{lede}</p>}
    </div>
  );
}

const base = "inline-flex items-center justify-center gap-2 whitespace-nowrap rounded-full font-medium tracking-[-0.01em] transition-[background-color,transform,box-shadow,border-color] duration-200 active:translate-y-px";

export function recordClasses(size: "sm" | "md" | "lg" = "md") {
  const s = size === "sm" ? "h-9 px-4 text-[14px]" : size === "lg" ? "h-14 px-7 text-[16px]" : "h-12 px-6 text-[15px]";
  return `${base} ${s} bg-record text-white shadow-[inset_0_1px_0_rgba(255,255,255,0.25),0_8px_24px_-10px_rgba(229,55,43,0.8)] hover:bg-record-deep`;
}

export function RecordButton({ href, children, size = "md", download }: { href: string; children: ReactNode; size?: "sm" | "md" | "lg"; download?: boolean }) {
  return (
    <a href={href} download={download} className={recordClasses(size)}>
      <Download className="size-4" strokeWidth={2.2} aria-hidden />{children}
    </a>
  );
}

export function GhostButton({ href, children, dark = false, github = false }: { href: string; children: ReactNode; dark?: boolean; github?: boolean }) {
  const cls = `${base} h-12 px-6 text-[15px] border ${dark ? "border-white/15 text-white hover:border-white/40" : "border-black/10 bg-white/60 text-ink hover:border-black/30"}`;
  const inner = <>{github && <GithubIcon />}{children}</>;
  return href.startsWith("http") ? <a href={href} rel="noopener" className={cls}>{inner}</a> : <Link href={href} className={cls}>{inner}</Link>;
}

export function GithubButton({ dark = false, children = "View on GitHub" }: { dark?: boolean; children?: ReactNode }) {
  return <GhostButton href={GITHUB} dark={dark} github>{children}</GhostButton>;
}

export function Kbd({ children }: { children: ReactNode }) {
  return <kbd className="rounded-md border border-black/10 border-b-2 bg-white px-1.5 py-0.5 text-[0.85em] font-medium">{children}</kbd>;
}
