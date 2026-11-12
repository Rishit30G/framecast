---
name: framecast-editor
description: Edit a Framecast screen recording the way its owner likes - remove pauses, cut mistakes, add zooms, captions, text, blur or highlight boxes, set the look, and export. Use when the user asks to edit, clean up, polish or export a Framecast recording, or gives a folder inside ~/Movies/Framecast.
---

# Editing a Framecast recording

Framecast is a Mac screen recorder and editor. Each recording is a folder (normally in
`~/Movies/Framecast/`) holding `screen.mov`, optionally `camera.mov` and `mic.m4a`, and a
`project.json` with every edit. You edit it with the app's command-line tools below; never write
`project.json` by hand. If the recording is open in Framecast, your edits appear there within a
second and the person can undo them with ⌘Z.

The tool is: `{{FRAMECAST}}` (written as `FRAMECAST` below; always quote the path).

## Steps

1. **Read the person's style.** Read `STYLE.md` in this skill's folder. It says, in their own
   words, how they like videos edited. Follow it unless this request says otherwise. If it is
   missing, use sensible defaults and say so.
2. **Find the recording.** Use the folder they gave. If they gave none, list `~/Movies/Framecast/`
   and take the newest folder, telling them which one you chose.
3. **Look at it.** Run `FRAMECAST --info "<folder>"`. It prints JSON: length, transcript with
   times, silences, clicks, shortcuts pressed, what is kept, and the current look. The first run
   may take a while because it transcribes the speech.
4. **Plan the edit** from the style and the request, then write the edits to a JSON file in your
   scratch folder (not inside the recording) and run `FRAMECAST --apply "<folder>" "<edits.json>"`.
   It prints what it did. On an error nothing is saved.
5. **Check your work.** `FRAMECAST --frame "<folder>" <seconds> "<out.png>"` renders one frame of the
   edited video; look at one or two (for example where you put text or a blur box) and fix anything
   that is off. Run `--info` again to confirm the new length.
6. **Export only if the style or the request says to**: `FRAMECAST --export "<folder>" "<out.mp4>"
   --res 1080p --fps 60` (`--res` is 4K, 1080p, 720p or Original; `--fps` is 30 or 60).
7. **Report** in plain language: what you removed and how much shorter the video is, what you
   added, where the export is, and anything you were unsure about.

## Times and positions

- Every time is in **seconds of the raw recording**, the same clock as the transcript and silences
  in `--info`. This stays true after cuts; the tool translates for you.
- Positions `x`, `y` run 0 to 1 from the top-left. For zoom, blur, highlight and spotlight they are
  within the recorded screen; for text they are within the whole frame. `w`, `h` are fractions of
  the recorded screen.

## Edits

The file is `{"edits": [ ... ]}`. Cuts and speed changes are applied first, whatever their order.

| do | fields | effect |
|---|---|---|
| `cut` | `from`, `to` | remove that stretch |
| `keep` | `ranges: [[from, to], ...]` | keep only these stretches (replaces all cuts) |
| `removeSilences` | `longerThan` (0.8), `leave` (0.3) | cut pauses longer than N seconds, leaving a short gap |
| `speed` | `from`, `to`, `rate` (0.25 to 8) | speed up or slow down a stretch |
| `zoom` | `from`, `to`, `x`, `y`, `scale` (2) | zoom in on a point |
| `autoZoom` | `on`, `scale` | automatic zoom on mouse clicks |
| `camera` | `from`, `to`, `mode` (`position`, `fullscreen`, `hidden`), `col` 0-2, `row` 0-2 | move, enlarge or hide the camera for a stretch |
| `text` | `from`, `to`, `text`, `x`, `y`, `size` (1), `box` (true/false) | a title or label |
| `blur` | `from`, `to`, `x`, `y`, `w`, `h`, `strength` | hide something private |
| `highlight` | `from`, `to`, `x`, `y`, `w`, `h` | marker-pen tint over an area |
| `spotlight` | `from`, `to`, `x`, `y`, `w`, `h` | darken everything except an area |
| `captions` | `on`, `size` | show captions (made from the speech) or hide them |
| `cleanAudio` | `on` | remove background noise from the voice and even out its volume |
| `animation` | `clip` (`first`, `last`, `all`, or `index` with `index: n`, counting kept clips from 0), `entry`, `exit` (a name, or `none` to remove) | `fade`, `rise`, `slideLeft`, `slideRight`, `slideUp`, `slideDown`, `zoomIn`, `zoomOut`, `blur`, `pop` |
| `look` | `aspect` (`Auto`, `16:9`, `4:3`, `1:1`, `9:16`), `background` (`none`, a macOS wallpaper name from `wallpapers` in `--info` such as `Sonoma Horizon`, or a colour as `#rrggbb`), `padding` (0-0.3), `corners`, `shadow` (0-1), `outline` (0-1, thin white line around the recording), `backgroundBlur` (0-1), `cameraVisible`, `cameraSize`, `showShortcuts` | the overall look |
| `reset` | `what` (`all`, `cuts`, `zooms`, `overlays`, `camera`, `captions`) | clear earlier edits |

Example:

```json
{"edits": [
  {"do": "removeSilences", "longerThan": 0.8, "leave": 0.3},
  {"do": "cut", "from": 12.4, "to": 15.1},
  {"do": "zoom", "from": 20.0, "to": 24.0, "x": 0.3, "y": 0.4, "scale": 2},
  {"do": "text", "from": 0, "to": 3, "text": "Setting up the project", "y": 0.15, "box": true},
  {"do": "captions", "on": true},
  {"do": "animation", "clip": "first", "entry": "fade"},
  {"do": "animation", "clip": "last", "exit": "fade"}
]}
```

## Judgement

- Cut filler and false starts using the transcript: when a sentence is said twice, keep the last
  complete take. Cut on silences so words are not clipped; leave about 0.15s either side of speech.
- `stillScreen` in `--info` lists stretches where nothing on the recorded screen changes. Speech
  during one of those is "talking with nothing happening on screen"; speech outside them is
  "talking while showing something".
- Clip animations sit on either side of a cut. After cutting, run `--info` to see `keptClips`; the
  cut between clip n and clip n+1 is animated with `exit` on n and `entry` on n+1. The length of a
  cut is the gap between one clip's `to` and the next clip's `from`.
- Zooms: clicks in `--info` show where the action is. A zoom should last at least 2 seconds, and
  zooms should not overlap.
- You cannot see the screen contents from `--info`. Before placing a blur, highlight or text over
  something specific, render a frame with `--frame` to find where it is, then render again to check.
- Running `--apply` twice adds things twice. To redo an edit, start with
  `{"do": "reset", "what": "..."}` for the parts you are replacing.
- The first `--apply` saves the original edit as `project.before-claude.json` in the folder. Do not
  delete recordings or their files.
- If the style and the request conflict, the request wins for this video. If the person says they
  always want something done differently, offer to update `STYLE.md` for them.
