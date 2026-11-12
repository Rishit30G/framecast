"use client";
import { useRouter } from "next/navigation";
import type { ReactNode } from "react";
import { Download } from "lucide-react";
import { recordClasses } from "./ui";
import { DMG } from "@/lib/site";

/** Starts the download and moves straight to the install guide.
 *  Without JavaScript the link still lands on the guide, which has its own download link. */
export default function DownloadButton({ children, size = "md" }: { children: ReactNode; size?: "sm" | "md" | "lg" }) {
  const router = useRouter();
  return (
    <a href="/install/" className={recordClasses(size)}
      onClick={(e) => {
        if (e.metaKey || e.ctrlKey || e.shiftKey || e.button !== 0) return;
        e.preventDefault();
        // A hidden frame fetches the .dmg; GitHub serves it as an attachment, so the browser saves it.
        const frame = document.createElement("iframe");
        frame.style.display = "none";
        frame.src = DMG;
        document.body.appendChild(frame);
        try { sessionStorage.setItem("framecast-download-started", "1"); } catch {}
        router.push("/install/");
      }}>
      <Download className="size-4" strokeWidth={2.2} aria-hidden />{children}
    </a>
  );
}
