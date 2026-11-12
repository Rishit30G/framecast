import { Check, Circle, Scissors, Wand2, Download, Timer, ZoomIn, ShieldAlert } from "lucide-react";
import DownloadButton from "@/components/DownloadButton";
import Nav from "@/components/Nav";
import Footer from "@/components/Footer";
import HeroPlayer from "@/components/HeroPlayer";
import { FeatureRow } from "@/components/FeatureCard";
import Calculator from "@/components/Calculator";
import Faq from "@/components/Faq";
import AiDemo from "@/components/AiDemo";
import { Counter, Fade, Reveal, Stagger, StaggerItem, Words } from "@/components/motion";
import { Badge, GithubButton, Kbd, SectionHead } from "@/components/ui";
import { Icon, Logo } from "@/components/icons";
import { BOX, DMG, FAQ, FEATURES, SITE } from "@/lib/site";

const W = "mx-auto w-full max-w-[1200px] px-4 sm:px-8";
const SECTION = "py-24 md:py-32";

const jsonLd = [
  { "@context": "https://schema.org", "@type": "SoftwareApplication", name: "Framecast", operatingSystem: "macOS 14 or later",
    applicationCategory: "MultimediaApplication", offers: { "@type": "Offer", price: "0", priceCurrency: "USD" },
    downloadUrl: DMG, url: SITE, image: `${SITE}/media/hero.jpg`, fileSize: "6MB",
    description: "Free, open-source screen recorder and editor for Mac with auto zoom, captions, blur and AI editing with Claude." },
  { "@context": "https://schema.org", "@type": "FAQPage",
    mainEntity: FAQ.map(([q, a]) => ({ "@type": "Question", name: q, acceptedAnswer: { "@type": "Answer", text: a } })) },
];

export default function Home() {
  return (
    <>
      <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd) }} />
      <Nav />
      <main>
        {/* Hero */}
        <section className="pt-16 md:pt-24">
          <div className={`${W} text-center`}>
            <Fade initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} className="mb-7 flex justify-center">
              <Badge>The screen recorder with Claude built in</Badge>
            </Fade>
            <h1 className="mx-auto max-w-[14ch] text-balance text-[clamp(2.75rem,7.4vw,6rem)] font-semibold leading-[0.98] tracking-[-0.055em]">
              <Words text="Hit record. Skip the edit." accent="Skip" />
            </h1>
            <Fade initial={{ opacity: 0, y: 12 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.45 }}>
              <p className="mx-auto mt-7 max-w-[34rem] text-[17px] leading-relaxed tracking-[-0.015em] text-muted md:text-[19px]">
                Framecast records your Mac. Claude edits it to your style: cuts, zooms, captions and blur. Free and open source.
              </p>
              <div className="mt-9 flex flex-wrap justify-center gap-3">
                <DownloadButton>Download for macOS</DownloadButton>
                <GithubButton />
              </div>
              <p className="mt-5 text-[13.5px] tracking-[-0.01em] text-zinc-500">macOS 14 or later · Apple silicon · 6 MB · No account</p>
            </Fade>
            <div className="mx-auto mt-14 max-w-[1080px] md:mt-20"><HeroPlayer /></div>

            <Stagger className="mt-20 grid grid-cols-2 gap-px overflow-hidden rounded-[24px] border border-line bg-line md:mt-28 md:grid-cols-4">
              {[
                [<><Counter to={6} /> MB</>, "The whole app, nothing else to install"],
                ["4K", "Export at up to 60 fps, in any shape"],
                [<Counter key="a" to={10} />, "Entry and exit animations for every cut"],
                [<Counter key="c" to={9} />, "Camera positions, plus full screen"],
              ].map(([n, l], i) => (
                <StaggerItem key={i} className="bg-canvas px-5 py-7 text-left sm:px-7">
                  <p className="text-[clamp(2.2rem,4vw,3.1rem)] font-semibold leading-none tracking-[-0.05em]">{n}</p>
                  <p className="mt-2.5 text-[14.5px] tracking-[-0.01em] text-muted">{l}</p>
                </StaggerItem>
              ))}
            </Stagger>
          </div>
        </section>

        {/* Problem */}
        <section id="problem" className={SECTION}>
          <div className={W}>
            <Reveal><SectionHead badge="The problem" title="Raw recordings aren't ready to share."
              lede="Most demos carry the same three problems, and fixing them by hand turns into a second job." /></Reveal>
            <Stagger className="mb-5 grid gap-4 md:grid-cols-3">
              {[
                [Timer, "var(--color-zoom)", "Dead air and retakes", "Pauses, false starts and the same sentence twice. Viewers leave before the point."],
                [ZoomIn, "var(--color-text)", "Text nobody can read", "A whole desktop squeezed into a video makes every button tiny."],
                [ShieldAlert, "var(--color-record)", "Things you didn't mean to show", "An API key, a customer's email, a notification. One frame is enough."],
              ].map(([I, c, t, d]) => {
                const C = I as typeof Timer;
                return (
                  <StaggerItem key={t as string} className="rounded-[24px] border border-black/[0.06] bg-white p-6 sm:p-7">
                    <span className="flex size-9 items-center justify-center rounded-[10px] text-white" style={{ background: c as string }}><C className="size-[18px]" /></span>
                    <h3 className="mt-5 text-[20px] font-semibold tracking-[-0.035em]">{t as string}</h3>
                    <p className="mt-2 text-[15.5px] leading-relaxed text-muted">{d as string}</p>
                  </StaggerItem>
                );
              })}
            </Stagger>
            <Reveal><Calculator /></Reveal>
          </div>
        </section>

        {/* Features */}
        <section id="features" className={`${SECTION} pt-0 md:pt-0`}>
          <div className={W}>
            <Reveal><SectionHead badge="Features, shown" title="Every clip here was made by Framecast."
              lede="Each one ran through Framecast's own editor and exporter. What you see is what you get." /></Reveal>
            <div className="grid gap-20 md:gap-32">
              {FEATURES.map((f, i) => <FeatureRow key={f.slug} f={f} flip={i % 2 === 1} />)}
            </div>
          </div>
        </section>

        {/* How it works */}
        <section id="how" className={`${SECTION} pt-0 md:pt-0`}>
          <div className={W}>
            <Reveal><SectionHead badge="How it works" title="From screen to share in four steps." /></Reveal>
            <Stagger className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
              {[
                [Circle, "Record", <>Pick full screen, a window or an area. Camera and mic are found for you. Press <Kbd>⌥⌘R</Kbd> from anywhere.</>],
                [Scissors, "Edit", "The editor opens with zooms already on your clicks. Cut, caption, blur and style on a real timeline."],
                [Wand2, "Or hand it to Claude", "Choose Open in Claude. It edits to your style file while the timeline updates in front of you."],
                [Download, "Export", "Save an MP4 up to 4K at 60 fps, in any shape, with captions burned in or as an .srt."],
              ].map(([I, t, d], i) => {
                const C = I as typeof Circle;
                return (
                  <StaggerItem key={i} className="relative rounded-[24px] border border-black/[0.06] bg-white p-6">
                    <div className="flex items-center justify-between">
                      <span className="flex size-9 items-center justify-center rounded-[10px] bg-ink text-white"><C className="size-[18px]" /></span>
                      <span className="tnum text-[13px] font-medium text-zinc-400">Step {i + 1}</span>
                    </div>
                    <h3 className="mt-5 text-[19px] font-semibold tracking-[-0.035em]">{t as string}</h3>
                    <p className="mt-2 text-[15px] leading-relaxed text-muted">{d as React.ReactNode}</p>
                  </StaggerItem>
                );
              })}
            </Stagger>
          </div>
        </section>

        {/* Everything */}
        <section id="everything" className={`${SECTION} pt-0 md:pt-0`}>
          <div className={W}>
            <Reveal><SectionHead badge="Everything in the box" title="And all the details." /></Reveal>
            <Stagger className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
              {BOX.map((g) => (
                <StaggerItem key={g.title} className="rounded-[24px] border border-black/[0.06] bg-white p-6 sm:p-7">
                  <div className="mb-5 flex items-center gap-3">
                    <span className="flex size-9 items-center justify-center rounded-[10px] bg-zinc-100 text-ink"><Icon name={g.icon} className="size-[18px]" /></span>
                    <h3 className="text-[18px] font-semibold tracking-[-0.03em]">{g.title}</h3>
                  </div>
                  <ul className="grid gap-2.5">
                    {g.items.map((it) => (
                      <li key={it} className="flex gap-2.5 text-[14.5px] leading-snug tracking-[-0.01em] text-zinc-700">
                        <Check className="mt-0.5 size-4 shrink-0 text-emerald-600" strokeWidth={2.4} />{it}
                      </li>
                    ))}
                  </ul>
                </StaggerItem>
              ))}
            </Stagger>
          </div>
        </section>

        {/* AI */}
        <section id="ai" className="bg-ink py-24 text-white md:py-32">
          <div className={W}>
            <Reveal><SectionHead dark badge="AI first" title="Write down how you edit. Claude does it every time."
              lede="Framecast comes with a Claude skill and a style file in plain English. Claude reads your transcript, pauses, clicks and the moments your screen sits still, then edits the way your file says. Everyone writes their own." /></Reveal>
            <AiDemo />
            <Stagger className="mt-12 grid gap-x-8 gap-y-6 sm:grid-cols-2 lg:grid-cols-3">
              {[
                ["Cuts the waiting", "Removes pauses and keeps the last clean take of a repeated line."],
                ["Zooms where you work", "Uses your clicks and cursor to zoom into small details."],
                ["Moves the camera", "Full screen while you talk, back to the corner when you show something."],
                ["Hides secrets", "Finds keys, emails and passwords on screen and blurs them."],
                ["Checks its work", "Looks at frames to see where text and blur boxes land."],
                ["Never locks you in", "Every change shows in the editor and undoes with ⌘Z."],
              ].map(([t, d]) => (
                <StaggerItem key={t} className="border-t border-white/10 pt-5">
                  <p className="text-[16px] font-semibold tracking-[-0.02em]">{t}</p>
                  <p className="mt-1.5 text-[15px] leading-relaxed text-zinc-400">{d}</p>
                </StaggerItem>
              ))}
            </Stagger>
          </div>
        </section>

        {/* Privacy */}
        <section id="privacy" className={SECTION}>
          <div className={`${W} grid items-center gap-12 md:grid-cols-2`}>
            <Reveal><SectionHead badge="Private by design" title="Your recordings never leave your Mac."
              lede="Capture, transcription and voice clean-up all use Apple's own frameworks, so the heavy lifting happens on your machine." /></Reveal>
            <Reveal delay={0.1}>
              <ul className="divide-y divide-line rounded-[24px] border border-black/[0.06] bg-white px-6">
                {[["Account", "None"], ["Uploads", "None"], ["Watermark", "None"], ["Time limit", "None"], ["Captions", "Made on device"], ["Source code", "Open on GitHub"]].map(([k, v]) => (
                  <li key={k} className="flex items-center justify-between py-4 text-[15.5px] tracking-[-0.01em]"><span className="font-medium">{k}</span><span className="text-muted">{v}</span></li>
                ))}
              </ul>
            </Reveal>
          </div>
        </section>

        {/* Download */}
        <section id="download" className={`${SECTION} pt-0 md:pt-0`}>
          <div className={W}>
            <Reveal>
              <div className="grid gap-10 rounded-[32px] border border-black/[0.06] bg-white p-6 sm:p-10 md:grid-cols-[1.05fr_1fr] md:p-14">
                <div className="flex flex-col items-start gap-6">
                  <Badge>Download</Badge>
                  <h2 className="text-[clamp(2.1rem,4.6vw,3.4rem)] font-semibold leading-[1.02] tracking-[-0.045em]">Get Framecast for Mac.</h2>
                  <p className="text-[17px] text-muted">Free and open source. No sign-up, no trial, nothing to unlock.</p>
                  <DownloadButton size="lg">Download Framecast.dmg</DownloadButton>
                  <dl className="mt-2 grid w-full grid-cols-[auto_1fr] gap-x-8 gap-y-3 border-t border-line pt-6 text-[15px]">
                    {[["Requires", "macOS 14 Sonoma or later"], ["Mac", "Apple silicon (M1 or newer)"], ["Size", "About 6 MB"], ["AI editing", "Optional, needs the Claude app"]].map(([k, v]) => (
                      <div key={k} className="contents"><dt className="text-zinc-500">{k}</dt><dd className="font-medium">{v}</dd></div>
                    ))}
                  </dl>
                </div>
                <ol className="grid content-start gap-2">
                  {[
                    ["Download Framecast.dmg", "From this page or the latest GitHub release."],
                    ["Drag it to Applications", "Open the disk image and drag Framecast into Applications."],
                    ["Open it", "macOS will warn you the first time. The install guide shows exactly what to click."],
                    ["Allow access", "Screen & System Audio Recording, Camera and Microphone. Input Monitoring only for showing shortcuts."],
                    ["Record", <>Press <Kbd>⌥⌘R</Kbd> from any app to start, and again to stop.</>],
                  ].map(([t, d], i) => (
                    <li key={i} className="flex gap-4 rounded-2xl p-3 transition-colors hover:bg-zinc-50">
                      <span className="tnum flex size-8 shrink-0 items-center justify-center rounded-full bg-zinc-100 text-[14px] font-semibold">{i + 1}</span>
                      <div><p className="text-[15.5px] font-semibold tracking-[-0.02em]">{t}</p><p className="mt-0.5 text-[14.5px] leading-relaxed text-muted">{d}</p></div>
                    </li>
                  ))}
                </ol>
              </div>
            </Reveal>
          </div>
        </section>

        {/* FAQ */}
        <section id="faq" className={`${SECTION} pt-0 md:pt-0`}>
          <div className={W}>
            <Reveal><SectionHead center badge="Questions" title="Good to know." /></Reveal>
            <Reveal><Faq /></Reveal>
          </div>
        </section>

        {/* Closing */}
        <section className="pb-24 md:pb-32">
          <div className={W}>
            <Reveal>
              <div className="relative overflow-hidden rounded-[36px] bg-ink px-6 py-16 text-center text-white sm:px-12 md:py-24">
                <div aria-hidden className="pointer-events-none absolute left-1/2 top-0 h-[420px] w-[820px] -translate-x-1/2 -translate-y-1/2 rounded-full bg-[radial-gradient(closest-side,rgba(229,55,43,0.45),transparent)] blur-2xl" />
                <div aria-hidden className="pointer-events-none absolute inset-0 bg-[linear-gradient(to_right,rgba(255,255,255,0.04)_1px,transparent_1px),linear-gradient(to_bottom,rgba(255,255,255,0.04)_1px,transparent_1px)] bg-[size:56px_56px] [mask-image:radial-gradient(ellipse_at_center,black,transparent_75%)]" />
                <div className="relative flex flex-col items-center">
                  <Logo className="size-14" />
                  <h2 className="mt-8 max-w-[16ch] text-balance text-[clamp(2.2rem,5vw,4rem)] font-semibold leading-[1] tracking-[-0.05em]">Your next demo is one shortcut away.</h2>
                  <p className="mt-5 max-w-md text-[17px] text-zinc-400">Free for every Mac, forever. Takes a minute to install.</p>
                  <div className="mt-9 flex flex-wrap justify-center gap-3">
                    <DownloadButton>Download for macOS</DownloadButton>
                    <GithubButton dark>Star on GitHub</GithubButton>
                  </div>
                </div>
              </div>
            </Reveal>
          </div>
        </section>
      </main>
      <Footer />
    </>
  );
}
