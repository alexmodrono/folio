# Folio 1.0 launch film

A 65-second, 1920 × 1080, 60 fps Remotion film for Folio 1.0. It's built on
the same Remotion engine as our other launch films but paced for reading. It opens on a
moment every reader knows, then shows the real app at real speed on Mac
desktops with Apple's aerial wallpapers. Serif captions sit under each shot and
stay up just long enough to read, and scenes dissolve into each other on the
song's downbeats.

## Render

Requires macOS (the film uses the system San Francisco fonts), Node.js 22.18 or
later, npm, FFmpeg, the takes in `public/crono/` and the wallpaper clips in
`public/backgrounds/`.

```sh
cd marketing/promo
npm ci
npm run audio      # fetch Mixkit audio, build the music bed, render the Cuelume stems
npm run render     # → out/folio-1.0.mp4 (H.264 CRF 16, AAC 320 kbps)
```

`npm run studio` opens Remotion Studio. `node scripts/stills.mjs 14 21.5` renders
review stills for the given times into `out/stills/`.

## Screenshots

`npm run screenshots` renders the promotional screenshots into `out/screenshots/`
as PNGs. Each is a real frame of a take on an aerial wallpaper, with the Folio
badge, a serif headline and the not-affiliated line, in two formats:

- `-wide`: 16:9 at 2560 × 1440, for the website, X and Reddit.
- `-tall`: 4:5 at 1620 × 2025, for phone feeds. The window is wider than the
  frame and runs off one edge so the app stays large.

The shots, their frames and headlines are in `src/shots.ts`; `src/Screens.tsx`
draws them.

## Takes

The interface shots are the real app, recorded with
[Crono](https://github.com/alexmodrono/crono) through its MCP server (real
pointer) and exported with `export_take` into `public/crono/<name>/`: the window
alone as `video.mp4`, Crono's drawn pointer in `cursor.json`, and the clicks,
keystrokes and named steps in `take.json`. `TakeWindow` draws the window with its
real corners and shadow, plays it in segments and puts the pointer back on top.

All takes are a Debug build of Folio in a 1600 × 1000 pt window, with a demo
library of Wikipedia articles (CC BY-SA 4.0, exported as PDFs from
en.wikipedia.org) in a temporary folder (`defaults write app.folio.Folio
libraryPath …`, `FOLIO_FINDLE=missing`), and ChatGPT on Instant.

| Take | What was recorded |
| --- | --- |
| `library` | Home → the Biology folder → Photosynthesis. |
| `ask` | A sentence dragged, ⌘L, "Explain this in one sentence." typed and sent, the answer. |
| `page` | Right-click the diagram → Ask ChatGPT About Page 1 → "What does this diagram show?" → the answer. Recorded as a screen area so the context menu shows. |
| `bubble` | The question bubble in the margin → its popover → Show in Chat. |
| `reader` | The page display menu → Two Pages, then Thumbnails, then a zoom step. Recorded as a screen area so the menu shows. |

Menus are separate windows, so a window recording leaves them out: record any
take that opens a menu with `target: {area: …}` set to the window's frame.
`TakeWindow` gives those takes the window's corner radius, which hides the
backdrop at the corners.

ChatGPT's personalized suggestion chip under the greeting is blurred in
`library` and `ask` (Crono's `blur` regions). Before a take that selects text,
click an empty part of the page: a drag that starts on an existing selection
drags it instead of selecting.

`TAKES` in `src/timeline.ts` lists each take's click times (from its
`take.json`) and its segments. Segments play a stretch of the take at a constant
speed, mostly real time; typing is sped up, and a last near-still segment holds
the final frame so the answer can be read. `CAPTIONS` places the caption under
each shot.

## Wallpapers

`public/backgrounds/` holds 16-second 1080p clips of five of Apple's aerial
wallpapers (Sonoma Evening, Golden Gate Sunset, Sequoia Morning, Tahoe Day, the
Golden Gate over the bay), cut with FFmpeg from the URLs in macOS's aerials
manifest (`~/Library/Application Support/com.apple.wallpaper/aerials/manifest/entries.json`).

## Structure

The song is about 95 BPM (one bar ≈ 2.52 s); each row starts on a downbeat. The
film opens straight on the app, for people who only watch the first seconds of
a post, with a small Folio badge in the corner; the name card comes after the
first demo.

| Bars | Time (s) | Scene | What it shows |
| --- | --- | --- | --- |
| 0–3 | 0–10.7 | Ask | A passage selected, ⌘L, the question, the answer, in three captions. |
| 4–5 | 10.7–15.7 | Brand | The icon, "Folio", "Read a PDF. Ask about it." |
| 6–7 | 15.7–20.8 | Library | "All your PDFs, in one quiet library." |
| 8–9 | 20.8–24.6 | Card | "Every question / stays on its page." |
| 9½–11 | 24.6–30.9 | Bubble | A bubble in the margin, Show in Chat. |
| 12–14 | 30.9–38.5 | Page | The context menu's Ask About Page, and the answer. |
| 15–17 | 38.5–44.8 | Reader | The breakdown: the display menu, two pages, thumbnails, zoom. |
| 17½–19 | 44.8–51.1 | Details | Six facts, one a beat, as the last chorus starts. |
| 20– | 51.1–65.5 | Finale | Icon, name, tagline, "Available now for Mac", pdf.amodrono.com, the not-affiliated line, then black as the song ends. |

`src/timeline.ts` is the single source of truth. Re-run `npm run audio:cuelume`
after editing Cuelume cues.

## Sound

"Sweet September" (Mixkit #282), from just before its third bar, with ten bars of
its middle taken out (`src/audio/mixkit.ts`);
quiet Mixkit clicks on the recordings' clicks and a soft sparkle under the icon;
and Cuelume interface sounds rendered offline from the timeline. The music dips
a little under the recordings.

## Type

Titles and captions are set in Newsreader (SIL Open Font License, `public/fonts/`,
license in `OFL.txt`); small print uses the system San Francisco font.

## Naming

"ChatGPT" only names the service in the recordings and the footnote; it's kept out
of the title, taglines and the end card, which says Folio isn't affiliated with
OpenAI (see `docs/openai-terms.md`).

## Licensing

- Mixkit sound effects and music: Mixkit Sound Effects / Stock Music Free
  Licenses (commercial use, no attribution, no redistribution of the raw files).
- Cuelume is MIT-licensed; the rendered stems are generated, not shipped.
- The demo PDFs are Wikipedia articles (CC BY-SA 4.0).
- The aerial wallpapers are Apple's. Check that use before publishing the film.
