import type { Metadata } from "next";
import { Heart, Star, GitPullRequest, Keyboard, MessageCircle } from "lucide-react";
import Nav from "@/components/Nav";
import Footer from "@/components/Footer";
import InstallShot from "@/components/InstallShot";
import DownloadStarted from "@/components/DownloadStarted";
import { Fade, Reveal } from "@/components/motion";
import { Badge, GithubButton, Kbd, RecordButton } from "@/components/ui";
import { DMG, GITHUB } from "@/lib/site";

export const metadata: Metadata = {
  title: "Install Framecast",
  description: "Install Framecast on your Mac in about a minute: drag it to Applications, allow it in Privacy & Security, and turn on screen recording.",
  alternates: { canonical: "/install/" },
};

const B = ({ children }: { children: React.ReactNode }) => <b className="font-semibold text-ink">{children}</b>;

const STEPS: { title: string; body: React.ReactNode; shot: React.ComponentProps<typeof InstallShot> }[] = [
  {
    title: "Drag Framecast into Applications",
    body: <>Open <B>Framecast.dmg</B> from your Downloads folder. In the window that appears, drag the <B>Framecast</B> icon onto the <B>Applications</B> folder.</>,
    shot: { src: "/install/1-drag.png", w: 820, h: 262, alt: "The Framecast disk image window, showing the Framecast app and the Applications folder",
      marks: [{ x: 47, y: 30, w: 15, h: 62, label: "Drag this", round: false }, { x: 12, y: 30, w: 16, h: 62, label: "Drop here" }],
      arrow: { from: [47, 55], to: [29, 55] }, max: 640 },
  },
  {
    title: "Open Framecast",
    body: <>Press <Kbd>⌘ Space</Kbd>, type <B>Framecast</B> and press Return. You can also double-click it in your Applications folder.</>,
    shot: { src: "/install/2-spotlight.png", w: 1282, h: 230, alt: "Spotlight search showing Framecast as the top result",
      marks: [{ x: 1.5, y: 51, w: 97, h: 46, label: "Open this" }] },
  },
  {
    title: "macOS shows a warning. Click Done.",
    body: <>You&apos;ll see <B>“Framecast” Not Opened</B>. This is expected; the note above explains why. Click <B>Done</B>. Don&apos;t click Move to Bin.</>,
    shot: { src: "/install/3-done.png", w: 808, h: 736, alt: "The macOS warning: Framecast Not Opened, with Done and Move to Bin buttons",
      marks: [{ x: 21.6, y: 72.3, w: 27, h: 7.6, label: "Click Done", round: true, below: true }, { x: 50.7, y: 72.3, w: 27.3, h: 7.6, avoid: true }], max: 420 },
  },
  {
    title: "Open Privacy & Security and click Open Anyway",
    body: <>Open <B>System Settings</B>, choose <B>Privacy &amp; Security</B> in the sidebar and scroll down to <B>Security</B>. Next to “Framecast was blocked to protect your Mac”, click <B>Open Anyway</B>.</>,
    shot: { src: "/install/4-security.png", w: 1000, h: 370, alt: "The Security section of Privacy & Security, with an Open Anyway button next to Framecast",
      marks: [{ x: 72.7, y: 52.7, w: 21.4, h: 12.7, label: "Open Anyway", round: true }] },
  },
  {
    title: "Confirm with Open Anyway",
    body: <>macOS asks one last time. Click <B>Open Anyway</B> and enter your Mac password or use Touch ID if asked. You only do this once.</>,
    shot: { src: "/install/5-confirm.png", w: 720, h: 794, alt: "The Open Framecast? dialog with Move to Bin, Open Anyway and Done buttons",
      marks: [{ x: 18.1, y: 74.3, w: 63.2, h: 6.8, label: "Click Open Anyway", round: true, below: true }, { x: 18.1, y: 65.6, w: 63.2, h: 6.8, avoid: true }], max: 400 },
  },
  {
    title: "Let Framecast record your screen",
    body: <>Framecast asks for screen recording the first time. In <B>System Settings › Privacy &amp; Security › Screen &amp; System Audio Recording</B>, turn on <B>Framecast</B>. Allow the camera and microphone too when it asks.</>,
    shot: { src: "/install/6-screen.png", w: 960, h: 268, alt: "Screen & System Audio Recording settings with Framecast switched on",
      marks: [{ x: 89.5, y: 74, w: 9.5, h: 19, label: "Turn on", round: true }] },
  },
  {
    title: "Click Reopen Framecast",
    body: <>macOS only applies screen recording once the app restarts. If the recorder bar says “Turn on Framecast under Screen &amp; System Audio Recording, then reopen it”, click <B>Reopen Framecast</B>. That&apos;s the last step.</>,
    shot: { src: "/install/7-reopen.png", w: 650, h: 135, alt: "The right end of the Framecast recorder bar, with Open Settings and Reopen Framecast buttons",
      marks: [{ x: 64.6, y: 64, w: 32.3, h: 24, label: "Click Reopen Framecast", round: true, below: true }], max: 620 },
  },
];

export default function InstallPage() {
  const W = "mx-auto w-full max-w-[880px] px-4 sm:px-8";
  const share = `https://x.com/intent/post?text=${encodeURIComponent("Framecast: a free, open-source screen recorder for Mac that Claude edits for you")}&url=${encodeURIComponent(GITHUB)}`;
  return (
    <>
      <Nav />
      <main>
        <section className="pb-12 pt-16 md:pt-24">
          <div className={`${W} text-center`}>
            <Fade initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} className="flex justify-center"><Badge>Thanks for downloading Framecast</Badge></Fade>
            <h1 className="mx-auto mt-7 max-w-[16ch] text-balance text-[clamp(2.5rem,6.4vw,4.6rem)] font-semibold leading-[1] tracking-[-0.055em]">Let&apos;s get it running on your Mac.</h1>
            <p className="mx-auto mt-6 max-w-[34rem] text-[17px] leading-relaxed text-muted md:text-[18px]">It takes about a minute. Follow the steps below once, and Framecast opens normally from then on.</p>
            <DownloadStarted />
            <div className="mt-8 flex flex-wrap justify-center gap-3">
              <RecordButton href={DMG} download>Download Framecast.dmg</RecordButton>
            </div>
            <p className="mt-4 text-[13.5px] text-zinc-500">macOS 14 or later · Apple silicon · About 6 MB · Free</p>
          </div>
        </section>

        <section className="pb-10">
          <div className={W}>
            <Reveal>
              <div className="rounded-[28px] border border-black/[0.06] bg-white p-6 sm:p-9">
                <p className="flex items-center gap-2.5 text-[15px] font-semibold tracking-[-0.02em]"><Heart className="size-[18px] text-record" fill="currentColor" aria-hidden />Before you start, a quick note from me</p>
                <div className="mt-5 grid gap-4 text-[16px] leading-relaxed text-zinc-700">
                  <p>When you open Framecast, your Mac will warn you that <B>Apple couldn&apos;t verify it</B>. Here&apos;s the honest reason.</p>
                  <p>To make that warning go away, Apple asks developers to pay <span className="rounded-md bg-record/10 px-1.5 py-0.5 font-semibold text-record">$99 every year</span> for a developer account. I&apos;m building Framecast on my own and <B>don&apos;t have one yet</B>, so the app isn&apos;t signed by Apple. That&apos;s the only reason for the warning.</p>
                  <p><B>Framecast is free and open source.</B> Every line of code is on GitHub, so you can read exactly what it does, build it yourself, or open an issue or pull request whenever something looks off.</p>
                  <p>If Framecast saves you time, a star on GitHub or a share helps more than you&apos;d think, and brings the day this warning disappears for everyone a little closer.</p>
                  <p className="font-semibold text-ink">Rishit</p>
                </div>
                <div className="mt-6 flex flex-wrap gap-2.5 border-t border-line pt-6">
                  <a href={GITHUB} rel="noopener" className="inline-flex items-center gap-2 rounded-full bg-ink px-4 py-2 text-[14px] font-medium text-white hover:bg-zinc-800"><Star className="size-4" aria-hidden />Star on GitHub</a>
                  <a href={GITHUB} rel="noopener" className="inline-flex items-center gap-2 rounded-full border border-black/10 px-4 py-2 text-[14px] font-medium hover:border-black/30"><GitPullRequest className="size-4" aria-hidden />Read the code</a>
                  <a href={share} rel="noopener" className="inline-flex items-center gap-2 rounded-full border border-black/10 px-4 py-2 text-[14px] font-medium hover:border-black/30"><MessageCircle className="size-4" aria-hidden />Share on X</a>
                </div>
              </div>
            </Reveal>
          </div>
        </section>

        <section className="pb-16">
          <ol className={`${W} grid gap-5`}>
            {STEPS.map((s, i) => (
              <li key={s.title}>
                <Reveal>
                  <div className="rounded-[28px] border border-black/[0.06] bg-white p-5 sm:p-8">
                    <div className="flex gap-4">
                      <span className="tnum flex size-9 shrink-0 items-center justify-center rounded-full bg-record text-[15px] font-semibold text-white">{i + 1}</span>
                      <div>
                        <h2 className="text-[clamp(1.25rem,2.4vw,1.55rem)] font-semibold leading-tight tracking-[-0.035em]">{s.title}</h2>
                        <p className="mt-2 text-[15.5px] leading-relaxed text-muted">{s.body}</p>
                      </div>
                    </div>
                    <div className="mt-7 rounded-[22px] bg-zinc-100 px-3 pb-12 pt-11 sm:px-8 sm:pb-14 sm:pt-12"><InstallShot {...s.shot} /></div>
                  </div>
                </Reveal>
              </li>
            ))}
          </ol>
        </section>

        <section className="pb-24">
          <div className={W}>
            <Reveal>
              <div className="relative overflow-hidden rounded-[32px] bg-ink px-6 py-14 text-center text-white sm:px-12">
                <div aria-hidden className="pointer-events-none absolute left-1/2 top-0 h-[360px] w-[700px] -translate-x-1/2 -translate-y-1/2 rounded-full bg-[radial-gradient(closest-side,rgba(229,55,43,0.45),transparent)] blur-2xl" />
                <div className="relative flex flex-col items-center">
                  <Keyboard className="size-8 text-zinc-400" aria-hidden />
                  <h2 className="mt-5 text-balance text-[clamp(2rem,4.6vw,3.2rem)] font-semibold leading-[1] tracking-[-0.05em]">That&apos;s it. Press <span className="text-record">⌥⌘R</span> to record.</h2>
                  <p className="mt-4 max-w-md text-[16px] text-zinc-400">Stuck on a step? Open an issue on GitHub and I&apos;ll help.</p>
                  <div className="mt-8 flex flex-wrap justify-center gap-3">
                    <GithubButton dark>Get help on GitHub</GithubButton>
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
