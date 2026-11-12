import type { Metadata } from "next";
import DownloadButton from "@/components/DownloadButton";
import Link from "next/link";
import { notFound } from "next/navigation";
import { Check, Minus } from "lucide-react";
import Nav from "@/components/Nav";
import Footer from "@/components/Footer";
import { Reveal, Stagger, StaggerItem } from "@/components/motion";
import { Badge, GhostButton } from "@/components/ui";
import { COMPARISONS, type Cell } from "@/lib/compare";
import { COMPARE } from "@/lib/site";

export const dynamicParams = false;
export function generateStaticParams() { return Object.keys(COMPARISONS).map((slug) => ({ slug })); }

export async function generateMetadata({ params }: { params: Promise<{ slug: string }> }): Promise<Metadata> {
  const c = COMPARISONS[(await params).slug];
  if (!c) return {};
  return { title: { absolute: c.title }, description: c.description, alternates: { canonical: `/compare/${(await params).slug}/` },
    openGraph: { title: c.title, description: c.description, url: `/compare/${(await params).slug}/`, images: ["/media/hero.jpg"] } };
}

function Value({ v }: { v: Cell }) {
  if (v === true) return <span className="inline-flex items-center gap-1.5 font-medium text-emerald-700"><Check className="size-4" strokeWidth={2.6} />Yes</span>;
  if (v === false) return <span className="inline-flex items-center gap-1.5 text-zinc-400"><Minus className="size-4" />No</span>;
  return <span>{v}</span>;
}

export default async function ComparePage({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const c = COMPARISONS[slug];
  if (!c) notFound();
  const W = "mx-auto w-full max-w-[1100px] px-4 sm:px-8";
  return (
    <>
      <Nav home="/" />
      <main>
        <section className="pb-12 pt-16 md:pt-24">
          <div className={W}>
            <Reveal>
              <div className="mx-auto flex max-w-3xl flex-col items-center text-center">
                <Badge>Compare</Badge>
                <h1 className="mt-6 text-[clamp(2.4rem,6vw,4.6rem)] font-semibold leading-[1] tracking-[-0.055em]">Framecast vs {c.name}</h1>
                <p className="mt-6 text-[17px] leading-relaxed tracking-[-0.01em] text-muted md:text-[18px]">{c.lede}</p>
                <div className="mt-8 flex flex-wrap justify-center gap-3">
                  <DownloadButton>Download Framecast free</DownloadButton>
                  <GhostButton href="/#features">See the features</GhostButton>
                </div>
              </div>
            </Reveal>
            <Stagger className="mt-14 grid gap-4 md:grid-cols-2">
              {[[`Choose ${c.name} for`, c.theirs, false], ["Choose Framecast for", c.ours, true]].map(([h, items, ours]) => (
                <StaggerItem key={h as string} className={`rounded-[24px] border p-6 sm:p-8 ${ours ? "border-ink bg-ink text-white" : "border-black/[0.06] bg-white"}`}>
                  <h2 className="text-[19px] font-semibold tracking-[-0.03em]">{h as string}</h2>
                  <ul className="mt-5 grid gap-3">
                    {(items as string[]).map((i) => (
                      <li key={i} className={`flex gap-2.5 text-[15px] leading-snug ${ours ? "text-zinc-300" : "text-zinc-700"}`}>
                        <Check className={`mt-0.5 size-4 shrink-0 ${ours ? "text-record" : "text-zinc-400"}`} strokeWidth={2.6} />{i}
                      </li>
                    ))}
                  </ul>
                </StaggerItem>
              ))}
            </Stagger>
          </div>
        </section>
        <section className="pb-24">
          <div className={W}>
            <Reveal>
              <div className="overflow-x-auto rounded-[24px] border border-black/[0.06] bg-white">
                <table className="w-full min-w-[560px] border-collapse text-left text-[15px] tracking-[-0.01em]">
                  <thead>
                    <tr className="border-b border-line text-[13px] text-zinc-500">
                      <th scope="col" className="px-6 py-4 font-medium"><span className="sr-only">Feature</span></th>
                      <th scope="col" className="px-6 py-4 font-semibold text-ink">Framecast</th>
                      <th scope="col" className="px-6 py-4 font-medium">{c.name}</th>
                    </tr>
                  </thead>
                  <tbody>
                    {c.rows.map(([k, a, b]) => (
                      <tr key={k} className="border-b border-line last:border-0">
                        <th scope="row" className="w-[34%] px-6 py-4 font-medium">{k}</th>
                        <td className="px-6 py-4"><Value v={a} /></td>
                        <td className="px-6 py-4 text-zinc-600"><Value v={b} /></td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
              <p className="mt-4 text-center text-[13px] text-zinc-500">Based on public information as of November 2026. Prices and features change, so check {c.name}&apos;s own site before deciding. {c.name} is a trademark of its owner; Framecast is not affiliated with it.</p>
              <div className="mt-8 flex flex-wrap justify-center gap-2">
                {COMPARE.filter((o) => o.slug !== slug).map((o) => (
                  <Link key={o.slug} href={`/compare/${o.slug}/`} className="rounded-full border border-black/10 bg-white px-4 py-2 text-[14px] font-medium tracking-[-0.01em] transition-colors hover:border-black/30">Framecast vs {o.name}</Link>
                ))}
              </div>
            </Reveal>
          </div>
        </section>
      </main>
      <Footer />
    </>
  );
}
