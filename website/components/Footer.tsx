import Link from "next/link";
import { Logo } from "./icons";
import { COMPARE, GITHUB } from "@/lib/site";

export default function Footer() {
  const col = "flex flex-col gap-2.5 text-[14.5px] text-zinc-600";
  const head = "mb-4 text-[13px] font-medium tracking-[-0.01em] text-zinc-400";
  const a = "transition-colors hover:text-ink";
  return (
    <footer className="border-t border-line">
      <div className="mx-auto max-w-[1200px] px-4 pb-10 pt-16 sm:px-8">
        <div className="grid grid-cols-2 gap-10 md:grid-cols-[1.4fr_1fr_1fr_1fr]">
          <div className="col-span-2 md:col-span-1">
            <Link href="/" className="flex items-center gap-2.5 text-[17px] font-semibold tracking-[-0.03em]"><Logo />Framecast</Link>
            <p className="mt-4 max-w-[28ch] text-[14.5px] leading-relaxed text-muted">A free, open-source screen recorder and editor for Mac.</p>
          </div>
          <div><p className={head}>Product</p><div className={col}>
            <Link className={a} href="/#features">Features</Link><Link className={a} href="/#ai">AI editing with Claude</Link>
            <Link className={a} href="/install/">Download and install</Link><Link className={a} href="/#faq">FAQ</Link></div></div>
          <div><p className={head}>Compare</p><div className={col}>
            {COMPARE.map((c) => <Link key={c.slug} className={a} href={`/compare/${c.slug}/`}>Framecast vs {c.name}</Link>)}</div></div>
          <div><p className={head}>Open source</p><div className={col}>
            <a className={a} href={GITHUB} rel="noopener">Source code</a><a className={a} href={`${GITHUB}/releases`} rel="noopener">Releases</a>
            <a className={a} href={`${GITHUB}/issues`} rel="noopener">Report an issue</a></div></div>
        </div>
        <div className="mt-14 flex flex-col justify-between gap-3 border-t border-line pt-6 text-[13px] text-zinc-500 md:flex-row">
          <span>© 2026 Framecast contributors. Free and open source.</span>
          <span>Made by <a href="https://x.com/rishit30g" rel="noopener" className="font-medium text-ink underline-offset-4 hover:underline">Rishit Gupta</a></span>
        </div>
      </div>
    </footer>
  );
}
