# Contributing to Framecast

Thanks for helping. Framecast is a small, focused Mac app, and contributions of every size are welcome: a typo, a bug report, a new export option or a whole feature.

## Ways to help

- **Report a bug.** Open an issue with what you did, what you expected and what happened. Include your macOS version, your Mac (Apple silicon model) and, if you can, a short screen recording.
- **Suggest a feature.** Open an issue describing the problem first, then the idea. Screenshots or a sketch help.
- **Improve the docs or the website.** The README, this guide and the site in `website/` all count.
- **Write code.** Pick an issue labelled `good first issue` or `help wanted`, or open one to discuss a larger change before you start.

## Getting set up

You need macOS 14 or later on Apple silicon and Xcode 26 or later.

```bash
git clone https://github.com/Rishit30G/framecast.git
cd framecast
./build.sh
open build/Framecast.app
```

To stop macOS asking for Screen Recording permission after every rebuild, create a code-signing certificate named **Framecast Local Signing** in Keychain Access (Certificate Assistant › Create a Certificate, type *Code Signing*). `build.sh` picks it up automatically.

### The website

```bash
cd website
npm install
npm run dev      # http://localhost:4173
npm run build    # static files in website/out
```

## Checking your change

There's no XCTest suite yet. Instead, the app can render a synthetic project through every export path:

```bash
build/Framecast.app/Contents/MacOS/Framecast --selftest /tmp/framecast-selftest
```

It prints one line per variant (size, length, audio tracks) and writes a PNG of each, so you can look at the result. Please run it before opening a pull request that touches capture, rendering or export, and try the real flow too: record, edit, export.

If you change how the README or website clips look, regenerate them with `Framecast --demos <folder>`.

## Code map

| Folder | What lives there |
|---|---|
| `Sources/Framecast/Capture` | ScreenCaptureKit, camera and mic capture, the pause clock, click and key tracking |
| `Sources/Framecast/Recorder` | The recorder bar, camera bubble, countdown and library |
| `Sources/Framecast/Editor` | The editor window, timeline and inspector |
| `Sources/Framecast/Render` | Composition, the Core Image renderer shared by preview and export, zoom planning, export |
| `Sources/Framecast/ClaudeTools.swift` | The command-line tools the Claude skill uses |
| `Resources/skill` | The Claude skill and the starter editing style |
| `website` | The Next.js site |

## Guidelines

- **Keep the app small and native.** AppKit and SwiftUI, Apple frameworks, no third-party dependencies in the app.
- **Preview and export must match.** Anything drawn goes through `FrameRenderer`.
- **Projects must stay readable.** New fields in `Project` are optional so older recordings still open.
- **Plain words in the interface.** Name things by what people control ("Blur", "Show keyboard shortcuts"), use sentence case, and say what a button does.
- **One change per pull request,** with a short description of what changed and how you checked it. Screenshots or a clip for anything visual.

## Pull requests

1. Fork the repo and create a branch from `main`.
2. Make your change and run the self-test.
3. Open a pull request using the template, and link the issue it fixes.

By contributing, you agree that your contributions are licensed under the [MIT licence](LICENSE).
