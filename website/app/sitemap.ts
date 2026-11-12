import type { MetadataRoute } from "next";
import { COMPARE, SITE } from "@/lib/site";
export const dynamic = "force-static";
export default function sitemap(): MetadataRoute.Sitemap {
  const now = new Date("2026-11-11");
  return [{ url: `${SITE}/`, lastModified: now, priority: 1 },
    { url: `${SITE}/install/`, lastModified: now, priority: 0.8 },
    ...COMPARE.map((c) => ({ url: `${SITE}/compare/${c.slug}/`, lastModified: now, priority: 0.7 }))];
}
