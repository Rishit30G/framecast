export const SITE = "https://framecast-mac.vercel.app";
export const GITHUB = "https://github.com/Rishit30G/framecast";
/** Bump when the clips are re-rendered, so browsers fetch the new files. */
export const MEDIA_V = "4";
export const DMG = `${GITHUB}/releases/latest/download/Framecast.dmg`;

export type Feature = {
  slug: string; icon: string; color: string; title: string; text: string; chips: string[]; label: string; portrait?: boolean;
};

export const FEATURES: Feature[] = [
  { slug: "autozoom", icon: "click", color: "var(--color-zoom)", title: "Auto zoom that follows your clicks",
    text: "Every click is remembered while you record. Framecast glides in where the action is and back out, and you can place your own zooms too.",
    chips: ["Click tracking", "Hand-placed zooms", "Adjustable depth"], label: "The video zooms in towards each click on a dashboard" },
  { slug: "camera", icon: "camera", color: "var(--color-cam)", title: "A camera that moves with the story",
    text: "Pin your camera to any of nine spots, fill the screen while you talk, or hide it for a stretch. It glides between layouts.",
    chips: ["9 positions", "Full screen", "Hidden", "Drag anywhere"], label: "The camera moves corner to corner, then fills the screen" },
  { slug: "shapes", icon: "shapes", color: "var(--color-cam)", title: "Any camera shape and size",
    text: "Circle, rounded square, square or wide. Set the size and corner radius, mirror it and add as much shadow as you like.",
    chips: ["Circle", "Rounded", "Square", "Wide", "Corner radius"], label: "The camera changes from a circle to a rounded square, a square and a wide frame" },
  { slug: "backgrounds", icon: "image", color: "var(--color-caps)", title: "A frame worth looking at",
    text: "Sit the recording on a macOS wallpaper, a solid colour, your own image or nothing at all. Blur it, then tune padding, corners, shadow and outline.",
    chips: ["macOS wallpapers", "Solid colours", "Background blur", "Outline"], label: "The same recording on five different backgrounds" },
  { slug: "animations", icon: "sparkles", color: "var(--color-zoom)", title: "Ten ways in and out",
    text: "Give any cut an entry and an exit: fade, fade up, four slides, zoom in, zoom out, blur or pop.",
    chips: ["Entry", "Exit", "Per clip"], label: "Clips arrive with rise, slide and pop animations" },
  { slug: "privacy", icon: "eyeoff", color: "var(--color-marks)", title: "Blur secrets. Point at what matters.",
    text: "Blur an API key, mark a table row or spotlight one card. Boxes stay pinned to the recording through every zoom.",
    chips: ["Blur", "Marker", "Spotlight"], label: "An API key is blurred, a row highlighted and a card spotlighted" },
  { slug: "captions", icon: "captions", color: "var(--color-caps)", title: "Captions made on your Mac",
    text: "Speech becomes timed captions without uploading a thing. Pick your font and colours, or save them as an .srt file.",
    chips: ["On device", "Your font", "Colours", ".srt"], label: "Yellow captions in a custom style under a recording" },
  { slug: "overlays", icon: "type", color: "var(--color-text)", title: "Titles, labels and logos",
    text: "Add text in your own font, colour and box, or drop in an image with rounded corners. Each sits on its own track.",
    chips: ["Text", "Images", "Fonts", "Fades"], label: "A title and a logo appear over the recording" },
  { slug: "keystrokes", icon: "keyboard", color: "var(--color-text)", title: "Show the shortcut you pressed",
    text: "Shortcuts you press while recording appear on screen for a moment, so viewers can follow along.",
    chips: ["Shortcuts", "On or off per video"], label: "Keyboard shortcuts appear as badges in the corner" },
  { slug: "vertical", icon: "phone", color: "var(--color-zoom)", title: "One recording, every shape",
    text: "Widescreen for YouTube, square for a feed, 9:16 for Reels, Shorts and TikTok. The camera and captions rearrange to fit.",
    chips: ["16:9", "4:3", "1:1", "9:16", "Crop"], label: "A vertical 9:16 version with a round camera and captions", portrait: true },
];

export const HERO_TRACKS = [
  { name: "Camera", color: "var(--color-cam)", pills: [[0, 2.4, "Full screen"], [2.4, 10.8, "Rounded corner"], [10.8, 12, "Full screen"]] },
  { name: "Zoom", color: "var(--color-zoom)", pills: [[4.05, 7.2, "Auto zoom"], [8.0, 10.6, "Zoom"]] },
  { name: "Text", color: "var(--color-text)", pills: [[2.7, 4.6, "Q3 revenue review"]] },
  { name: "Marks", color: "var(--color-marks)", pills: [[6.1, 7.7, "Spotlight"]] },
  { name: "Captions", color: "var(--color-caps)", pills: [[0.2, 2.3, "Hi! Let me walk…"], [2.6, 4.8, "Here's where…"], [5.0, 7.8, "and active users…"], [8.0, 10.8, "Recurring revenue…"]] },
] as const;

export const BOX = [
  { title: "Recording", icon: "record", items: ["Full screen, one window or any area", "Camera and microphone found automatically", "System audio on or off", "Countdown before you start", "Pause, resume, restart or discard", "⌥⌘R to start or stop, ⌥⌘P to pause, from any app", "Floating, resizable camera preview", "True-to-screen colour"] },
  { title: "Timeline", icon: "scissors", items: ["Split, cut and trim", "Cut to the playhead with Q and W", "Speed from 0.25× to 8× per clip", "Waveform shows speech and silence", "Pinch to zoom the timeline", "Undo and redo everything"] },
  { title: "Audio", icon: "music", items: ["Music and sound effects on their own lanes", "Use the same song as often as you like", "Pick the exact part of a song", "Volume, fade in and fade out", "Record a voiceover over the video", "Voice clean-up removes noise and hum"] },
  { title: "Look", icon: "palette", items: ["Wallpapers that ship with macOS", "macOS solid colours, or any colour", "Background blur", "Padding, corners, shadow, outline", "Crop the recording", "Presets for every new recording"] },
  { title: "Export", icon: "download", items: ["MP4 at 4K, 1080p, 720p or original size", "30 or 60 frames per second", "Wide, square or 9:16 vertical", "Captions as .srt", "A library of every recording"] },
  { title: "Yours", icon: "lock", items: ["Everything runs on your Mac", "No account, no sign-in", "No watermark, no time limit", "Open source on GitHub", "About 6 MB"] },
];

export const FAQ = [
  ["Is Framecast really free?", "Yes. Framecast is open source and free to use: no account, no watermark, no recording time limit and nothing locked behind a plan."],
  ["Does it need an internet connection?", "No. Recording, editing, captions, voice clean-up and export all run on your Mac. You only need a connection if you choose to have Claude do the edit."],
  ["How does editing with Claude work?", "In the editor, choose Edit with Claude, then Open in Claude. The Claude app opens on your recording with the request filled in; press Return. Claude reads your style file, the transcript, the pauses, your clicks and the moments the screen sits still, then makes the edits. Changes appear in the open editor within a second, and ⌘Z undoes them."],
  ["Can I change how Claude edits my videos?", "Yes. Your editing style is a plain-English text file. Open it from Edit with Claude, then Open My Editing Style, change any rule, and the next edit follows it. Everyone keeps their own file."],
  ["Does Claude see my video?", "Claude reads the transcript and the facts Framecast reports about the recording, and looks at single frames when it needs to check where something sits on screen. Your recording files stay on your Mac."],
  ["Which Macs does it run on?", "Macs with Apple silicon running macOS 14 Sonoma or later. On macOS 14 and 15, captions need Dictation turned on in System Settings."],
  ["Is there a Windows or Linux version?", "No. Framecast is built only for macOS, using Apple's own capture and video frameworks."],
  ["What does it export?", "MP4 video (H.264 with AAC audio) at 4K, 1080p, 720p or the recording's own size, at 30 or 60 frames per second. Captions can also be saved as an .srt file."],
] as const;

export const COMPARE = [
  { slug: "screen-studio", name: "Screen Studio" },
  { slug: "loom", name: "Loom" },
  { slug: "camtasia", name: "Camtasia" },
  { slug: "obs", name: "OBS Studio" },
] as const;
