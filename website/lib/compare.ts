export type Cell = string | boolean;
export type Comparison = {
  name: string; title: string; description: string; lede: string;
  theirs: string[]; ours: string[]; rows: [string, Cell, Cell][];
};

export const COMPARISONS: Record<string, Comparison> = {
  "screen-studio": {
    name: "Screen Studio",
    title: "Framecast vs Screen Studio: a free, open-source alternative for Mac",
    description: "Compare Framecast and Screen Studio: price, auto zoom, camera layouts, captions, blur, timeline editing and AI editing with Claude.",
    lede: "Both make screen recordings look polished on a Mac, with backgrounds, a camera bubble and zooms that follow your clicks. Screen Studio is a paid, mature app; Framecast is free, open source and lets Claude do the edit to your own rules.",
    theirs: ["Years of polish and a large community", "Cursor smoothing and motion effects", "A wide set of presets and export options"],
    ours: ["Free and open source, no subscription", "AI editing with Claude that follows your written style", "Blur, marker and spotlight boxes for private details", "Per-section camera layouts: nine spots, full screen or hidden", "Music lanes, voiceover and voice clean-up in the same app"],
    rows: [["Price", "Free", "$9 a month billed yearly, or $29 monthly"], ["Open source", true, false], ["Platform", "macOS", "macOS"],
      ["Auto zoom on clicks", true, true], ["Cursor smoothing", false, true], ["Camera bubble and shapes", true, true],
      ["Claude edits from your own style file", true, false]],
  },
  loom: {
    name: "Loom",
    title: "Framecast vs Loom: private, polished recordings without the cloud",
    description: "Compare Framecast and Loom: where your videos live, editing, auto zoom, captions, blur, price per person and AI editing.",
    lede: "Loom is built for sending a quick link that a teammate watches in the browser. Framecast is built for making a finished video on your Mac and keeping the files yourself.",
    theirs: ["Instant share links with comments and reactions", "Viewer insights", "Apps for Mac, Windows, browser and phone", "Team workspaces and admin controls"],
    ours: ["Free, with no per-person price", "Recordings stay on your Mac", "Auto zoom, backgrounds and a camera bubble", "A full timeline with cuts, speed, music and captions", "AI editing with Claude that follows your written style"],
    rows: [["Price", "Free", "Free Starter plan; Business from $15 a month per person, billed yearly"], ["Open source", true, false],
      ["Where videos live", "Your Mac", "Loom's cloud"], ["Share link and comments", false, true], ["Platform", "macOS", "Mac, Windows, browser, phone"],
      ["Auto zoom on clicks", true, false], ["Backgrounds and padding", true, false], ["Timeline editing", "Full timeline", "Trim and stitch"],
      ["AI features", "Claude edits from your own style file", "Loom AI on higher plans"]],
  },
  camtasia: {
    name: "Camtasia",
    title: "Framecast vs Camtasia: a lighter, free screen video editor for Mac",
    description: "Compare Framecast and Camtasia: price, ease of use, auto zoom, captions, blur, timeline editing and AI editing with Claude.",
    lede: "Camtasia is a long-standing, full video editor for Windows and Mac. Framecast does fewer things, aims them squarely at screen demos, weighs about 6 MB and costs nothing.",
    theirs: ["Deep multi-track editing", "Large library of assets and templates", "Windows and Mac", "Training and support resources"],
    ours: ["Free, with no yearly licence", "The framed, zoomed look out of the box", "Automatic zoom from your clicks", "AI editing with Claude that follows your written style", "A small, fast app"],
    rows: [["Price", "Free", "Essentials from $179.88 a year"], ["Open source", true, false], ["Platform", "macOS", "Windows and Mac"],
      ["Zoom on clicks", "Automatic", "Placed by hand"], ["Camera bubble", true, true], ["Blur and highlight", true, true],
      ["Multi-track editing", "Focused tracks", "Full multi-track"], ["AI features", "Claude edits from your own style file", "From the Create tier up"], ["App size", "About 6 MB", "Much larger"]],
  },
  obs: {
    name: "OBS Studio",
    title: "Framecast vs OBS Studio: recording plus editing in one free Mac app",
    description: "Compare Framecast and OBS Studio: both free and open source. See how recording, streaming, editing, zoom, captions and AI editing differ.",
    lede: "OBS Studio and Framecast are both free and open source. OBS is a powerful recording and live-streaming studio with scenes and plugins; Framecast records and then edits, so you finish with a polished video without another app.",
    theirs: ["Live streaming to any platform", "Scenes, sources and plugins", "Windows, Mac and Linux", "Very large community"],
    ours: ["A built-in editor: cuts, zooms, captions, music", "Auto zoom from your clicks", "Backgrounds, padding and a camera bubble with no setup", "Blur, marker and spotlight boxes", "AI editing with Claude that follows your written style"],
    rows: [["Price", "Free", "Free"], ["Open source", true, true], ["Platform", "macOS", "Windows, Mac, Linux"], ["Live streaming", false, true],
      ["Built-in editor", true, false], ["Auto zoom on clicks", true, false], ["Captions", "On device", "Through plugins"],
      ["Blur, highlight and spotlight", true, "Through filters and plugins"], ["Set-up time", "Minutes", "Scenes to build"], ["Claude edits from your own style file", true, false]],
  },
};
