import {
  MousePointerClick, Video, Shapes, ImageIcon, Sparkles, EyeOff, Captions, Type, Keyboard, Smartphone,
  Circle, Scissors, Music, Palette, Download, Lock, Timer, ZoomIn, ShieldAlert, Wand2, Check, type LucideProps,
} from "lucide-react";

const MAP = {
  click: MousePointerClick, camera: Video, shapes: Shapes, image: ImageIcon, sparkles: Sparkles, eyeoff: EyeOff,
  captions: Captions, type: Type, keyboard: Keyboard, phone: Smartphone, record: Circle, scissors: Scissors,
  music: Music, palette: Palette, download: Download, lock: Lock, timer: Timer, zoom: ZoomIn, shield: ShieldAlert,
  wand: Wand2, check: Check,
} as const;

export function Icon({ name, ...props }: { name: string } & LucideProps) {
  const C = MAP[name as keyof typeof MAP] ?? Sparkles;
  return <C aria-hidden strokeWidth={1.9} {...props} />;
}

export function GithubIcon({ className = "size-[18px]" }: { className?: string }) {
  return (
    <svg viewBox="0 0 16 16" aria-hidden fill="currentColor" className={className}>
      <path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z" />
    </svg>
  );
}

export function Logo({ className = "size-7" }: { className?: string }) {
  return (
    <svg viewBox="0 0 64 64" aria-hidden className={className}>
      <rect x="4" y="8" width="56" height="44" rx="12" fill="#111113" />
      <rect x="11" y="15" width="42" height="30" rx="5" fill="#F3F4F6" />
      <circle cx="46" cy="44" r="11" fill="#E5372B" stroke="#111113" strokeWidth="4" />
    </svg>
  );
}
