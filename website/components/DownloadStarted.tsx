"use client";
import { useEffect, useState } from "react";
import { Check } from "lucide-react";

/** Tells people their download has begun when they arrive from a download button. */
export default function DownloadStarted() {
  const [started, setStarted] = useState(false);
  useEffect(() => {
    try {
      if (sessionStorage.getItem("framecast-download-started")) { setStarted(true); sessionStorage.removeItem("framecast-download-started"); }
    } catch {}
  }, []);
  if (!started) return null;
  return (
    <p className="mt-5 inline-flex items-center gap-2 rounded-full bg-emerald-50 px-4 py-2 text-[14.5px] font-medium text-emerald-800 ring-1 ring-emerald-200">
      <Check className="size-4" strokeWidth={2.6} aria-hidden />Your download has started. Didn&apos;t see it? Use the button below.
    </p>
  );
}
