"use client";
import Link from "next/link";
import DownloadButton from "./DownloadButton";
import { useEffect, useState } from "react";
import { GithubIcon, Logo } from "./icons";
import { GITHUB } from "@/lib/site";

export default function Nav({ home = "/" }: { home?: string }) {
  const [scrolled, setScrolled] = useState(false);
  useEffect(() => {
    const on = () => setScrolled(window.scrollY > 8);
    on(); window.addEventListener("scroll", on, { passive: true });
    return () => window.removeEventListener("scroll", on);
  }, []);
  const links = [["Features", "#features"], ["AI editing", "#ai"], ["Compare", "/compare/screen-studio/"], ["FAQ", "#faq"]];
  return (
    <header className={`sticky top-0 z-50 border-b backdrop-blur-xl backdrop-saturate-150 transition-colors ${scrolled ? "border-line bg-canvas/80" : "border-transparent bg-canvas/40"}`}>
      <div className="mx-auto flex h-16 max-w-[1200px] items-center gap-8 px-4 sm:px-8">
        <Link href="/" className="flex items-center gap-2.5 text-[17px] font-semibold tracking-[-0.03em]" aria-label="Framecast home">
          <Logo />Framecast
        </Link>
        <nav className="hidden md:block" aria-label="Main">
          <ul className="flex gap-7 text-[14.5px] font-medium tracking-[-0.01em] text-muted">
            {links.map(([label, href]) => (
              <li key={label}><Link className="transition-colors hover:text-ink" href={href.startsWith("#") ? `${home}${href}` : href}>{label}</Link></li>
            ))}
          </ul>
        </nav>
        <div className="ml-auto flex items-center gap-3 sm:gap-5">
          <a href={GITHUB} rel="noopener" className="flex items-center gap-2 text-[14.5px] font-medium text-muted transition-colors hover:text-ink">
            <GithubIcon /><span className="hidden sm:inline">GitHub</span>
          </a>
          <DownloadButton size="sm">Download</DownloadButton>
        </div>
      </div>
    </header>
  );
}
