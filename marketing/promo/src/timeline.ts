// The film's single source of truth for timing. Scenes read their event times
// from here, Film.tsx places the Mixkit cues, and scripts/render-cuelume.mjs
// renders the Cuelume cues from the same list. Times are in seconds of film.
//
// The music is "Sweet September" (Mixkit #282), about 95 BPM, a bar every
// 2.52 s, with ten bars of its middle taken out (src/audio/mixkit.ts). Scenes
// change on downbeats and dissolve into each other; recordings run at about
// real speed, and every title stays up just long enough to read comfortably.
// This file is plain, erasable TypeScript so Node can import it directly.

export const FPS = 60;
export const WIDTH = 1920;
export const HEIGHT = 1080;

export const BEAT = 0.63118;
export const BAR = 4 * BEAT;
const FIRST_DOWNBEAT = 0.576;
/** Downbeat `n` of the song. */
export const bar = (n: number) => FIRST_DOWNBEAT + n * BAR;
/** Beat `k` counted from downbeat `n`. */
export const beat = (n: number, k: number) => bar(n) + k * BEAT;

/** How long one scene takes to dissolve into the next. */
export const XF = 0.7;

/** The end card fades to black here, as the song's last chord rings out. */
export const BLACK = 62.55;
export const DURATION = 65.45;

export const toFrame = (seconds: number) => Math.round(seconds * FPS);

export type Span = {from: number; to: number};

// Song map, in bars of the edited bed: 0–1 the end of the quiet intro, 2–5 the
// band comes in, 6 the edit straight into the fullest part (to 12), 13–16 a
// quiet breakdown, 17–23 the last chorus, 24 the end.
//
// The film opens on the app itself: people scrolling past see Folio answering
// a question within the first seconds, and the name card comes after it.
export const SCENES = {
  ask: {from: 0, to: bar(4)},
  brand: {from: bar(4), to: bar(6)},
  library: {from: bar(6), to: bar(8)},
  stays: {from: bar(8), to: bar(9.5)},
  bubble: {from: bar(9.5), to: bar(12)},
  page: {from: bar(12), to: bar(15)},
  reader: {from: bar(15), to: bar(17.5)},
  details: {from: bar(17.5), to: bar(20)},
  finale: {from: bar(20), to: DURATION},
} satisfies Record<string, Span>;

// Real recordings of Folio, made with Crono and exported as takes into
// public/crono/<name>/ (see README). Each scene plays its take as a few
// segments; a segment plays one stretch of the take at a constant speed, mostly
// real time. A last, near-still segment holds the final frame so the answer can
// be read. Times inside a take are seconds of its video.mp4.
export type Segment = {
  /** Take time at the segment's start. */
  src: number;
  /** Film time the segment starts and ends. */
  from: number;
  to: number;
  /** Take seconds per film second. */
  rate: number;
  /** Where the camera looks during the segment, in fractions of the window. */
  focus?: Focus;
};

/** Zoom by `scale` and centre the window point (`x`, `y`), in fractions of the window. */
export type Focus = {scale: number; x: number; y: number};

const FULL: Focus = {scale: 1, x: 0.5, y: 0.5};
// The chat panel sits at the right of the window: its composer at the bottom,
// a conversation's latest messages above it.
const COMPOSER: Focus = {scale: 1.4, x: 0.82, y: 0.8};
const ANSWER: Focus = {scale: 1.4, x: 0.82, y: 0.42};

/** Take time at a film moment, or undefined when no segment shows it. */
export const takeTime = (segments: Segment[], t: number) => {
  const g = segments.find((s) => t >= s.from && t < s.to);
  return g ? g.src + (t - g.from) * g.rate : undefined;
};

/** Film time of a take moment, or undefined when no segment shows it. */
export const clipToFilm = (segments: Segment[], src: number) => {
  for (const g of segments) {
    const film = g.from + (src - g.src) / g.rate;
    if (film >= g.from && film < g.to) return film;
  }
  return undefined;
};

/**
 * Lays segments end to end from `start`: each plays the take from `src` to
 * `until` at `rate`. The last one stretches its bit of take over whatever film
 * time is left before `end`, which holds the final frame almost still.
 */
const chain = (start: number, end: number, parts: {src: number; until: number; rate?: number; focus?: Focus}[]): Segment[] => {
  let t = start;
  return parts.map((p, i) => {
    const last = i === parts.length - 1;
    const length = last ? end - t : (p.until - p.src) / (p.rate ?? 1);
    const rate = last ? (p.until - p.src) / length : p.rate ?? 1;
    const g = {src: p.src, from: t, to: t + length, rate, focus: p.focus ?? FULL};
    t += length;
    return g;
  });
};

/** A caption under a recording, from `at` until the next one or the scene's end. */
export type Caption = {at: number; text: string};

export type Take = {
  name: string;
  wallpaper: string;
  wallpaperOffset: number;
  clicks: Record<string, number>;
  segments: Segment[];
};

// Every scene runs XF past its slot, under the next scene's dissolve.
const until = (scene: Span) => scene.to + XF;

const library: Take = {
  // Home → the Biology folder → Photosynthesis.pdf.
  name: 'library',
  wallpaper: 'sonoma-evening',
  wallpaperOffset: 1,
  clicks: {biology: 3.606, openPdf: 5.934},
  segments: chain(SCENES.library.from, until(SCENES.library), [
    {src: 0.4, until: 6.9, rate: 1.3},
    {src: 6.9, until: 7.5},
  ]),
};

const ask: Take = {
  // A sentence dragged, ⌘L, a question typed and sent, and ChatGPT's answer.
  name: 'ask',
  wallpaper: 'gg-sunset',
  wallpaperOffset: 0,
  clicks: {dragStart: 2.958, composer: 7.022},
  segments: chain(SCENES.ask.from, until(SCENES.ask), [
    {src: 1.7, until: 6.6, rate: 1.15, focus: {scale: 1.12, x: 0.55, y: 0.62}},
    {src: 6.6, until: 11.5, rate: 2, focus: COMPOSER},
    // Framed a little low: until the answer arrives, ChatGPT titles the chat with
    // the raw quote markup, and the title row stays out of shot.
    {src: 11.5, until: 13.7, focus: {...ANSWER, y: 0.47}},
    {src: 13.7, until: 13.78, focus: {...ANSWER, y: 0.47, scale: 1.48}},
  ]),
};

const bubble: Take = {
  // A question bubble in the margin → its popover → Show in Chat.
  name: 'bubble',
  wallpaper: 'sequoia-morning',
  wallpaperOffset: 0,
  clicks: {bubble: 2.954, showInChat: 5.274},
  segments: chain(SCENES.bubble.from, until(SCENES.bubble), [
    {src: 1.3, until: 5.0, rate: 1.1, focus: {scale: 1.3, x: 0.72, y: 0.62}},
    {src: 5.0, until: 6.8, focus: {scale: 1.4, x: 0.8, y: 0.42}},
    {src: 6.8, until: 6.86, focus: {scale: 1.45, x: 0.8, y: 0.42}},
  ]),
};

const page: Take = {
  // Right-click the diagram → Ask ChatGPT About Page 1 → a question → the answer.
  name: 'page',
  wallpaper: 'tahoe',
  wallpaperOffset: 1,
  clicks: {menu: 2.5, askPage: 4.283, composer: 6.383},
  segments: chain(SCENES.page.from, until(SCENES.page), [
    {src: 1.6, until: 5.8, rate: 1.15, focus: {scale: 1.35, x: 0.56, y: 0.52}},
    {src: 5.8, until: 11.05, rate: 3, focus: COMPOSER},
    // Straight from the send to ChatGPT thinking: the moment the quote goes into
    // the composer as markup is cut.
    {src: 12.4, until: 13.4, focus: ANSWER},
    {src: 13.4, until: 13.45, focus: {...ANSWER, scale: 1.46}},
  ]),
};

const reader: Take = {
  // The page display menu: Two Pages, then Thumbnails, then a zoom step.
  name: 'reader',
  wallpaper: 'gg-bay',
  wallpaperOffset: 4,
  clicks: {menu: 2.683, twoPages: 4.15, menu2: 6.433, thumbnails: 7.967, zoom: 10.217},
  segments: chain(SCENES.reader.from, until(SCENES.reader), [
    // Close enough that the display menu reads; the chat panel is out of shot.
    {src: 2.2, until: 10.9, rate: 1.3, focus: {scale: 1.3, x: 0.385, y: 0.385}},
    {src: 10.9, until: 11.3, focus: {scale: 1.3, x: 0.385, y: 0.385}},
  ]),
};

export const TAKES = {library, ask, bubble, page, reader};
export type TakeName = keyof typeof TAKES;

const at = (take: Take, src: number) => clipToFilm(take.segments, src)!;
const clicksOf = (take: Take) =>
  Object.values(take.clicks)
    .map((t) => clipToFilm(take.segments, t))
    .filter((t): t is number => t !== undefined);

// Captions arrive a little after the scene's dissolve begins.
const LEAD = 0.5;

export const CAPTIONS: Record<TakeName, Caption[]> = {
  library: [{at: SCENES.library.from + LEAD, text: 'All your PDFs, in one quiet library.'}],
  ask: [
    // The very first words of the film, so they come almost at once.
    {at: 0.25, text: 'Select a passage and press ⌘L.'},
    {at: at(ask, 7.0), text: 'Ask in your own words.'},
    {at: at(ask, 12.6), text: 'The answer appears right beside the page.'},
  ],
  bubble: [
    {at: SCENES.bubble.from + LEAD, text: 'Each question leaves a bubble in the margin.'},
    {at: at(bubble, 5.0), text: 'Click it to return to the conversation.'},
  ],
  page: [
    {at: SCENES.page.from + LEAD, text: 'Or ask about a whole page, figures included.'},
  ],
  reader: [
    {at: SCENES.reader.from + LEAD, text: 'A real Mac PDF reader underneath.'},
    {at: at(reader, 5.8), text: 'Two pages, book mode, thumbnails and zoom.'},
  ],
};

export const T = {
  brand: {icon: bar(4), name: beat(4, 1.5), tagline: bar(5)},
  stays: {lines: [bar(8) + 0.25, beat(8, 1)]},
  // One line a beat, starting just after the dissolve.
  details: {items: Array.from({length: 6}, (_, i) => bar(17.5) + 0.3 + i * BEAT)},
  finale: {
    icon: bar(20),
    name: beat(20, 1.5),
    tagline: bar(21),
    available: bar(22),
    url: beat(22, 2),
  },
  ask: {askKey: at(ask, 4.753), send: at(ask, 11.283)},
  page: {send: at(page, 11.015)},
};

/** Clicks in the recordings, in film time, for the click sounds. */
export const CLICKS = [library, ask, bubble, page, reader].flatMap(clicksOf);

// Cuelume (https://cuelume.dev) interface cues, synthesized offline into one stem.
export type CuelumeCue = {
  t: number;
  sound: 'tap' | 'type' | 'select' | 'toggle' | 'open' | 'close' | 'success' | 'error' | 'navigate' | 'warning' | 'loading' | 'ready' | 'attention' | 'count';
  emphasis?: 'subtle' | 'normal' | 'strong';
  direction?: 'forward' | 'back';
  key?: 'printable' | 'space' | 'delete' | 'enter';
  input?: 'mouse' | 'touch' | 'pen' | 'keyboard';
  theme?: 'default' | 'mech' | 'bubble' | 'press';
  volume?: number;
  /** Rendered into a separate, louder stem so the cue reads over the music. */
  accent?: boolean;
};

// Keystrokes from each take's take.json; only the ones the film shows sound.
const ASK_KEYS = [
  7.131, 7.233, 7.416, 7.512, 7.645, 7.781, 7.909, 8.047, 8.221, 8.323, 8.481, 8.588, 8.727, 8.872, 8.989, 9.109, 9.302,
  9.409, 9.522, 9.672, 9.85, 9.945, 10.05, 10.141, 10.236, 10.351, 10.484, 10.612, 10.752,
];
const PAGE_KEYS = [
  6.459, 6.601, 6.707, 6.815, 7.031, 7.222, 7.342, 7.449, 7.566, 7.73, 8.0, 8.135, 8.251, 8.342, 8.522, 8.745, 8.823,
  8.983, 9.158, 9.285, 9.391, 9.531, 9.682, 9.875, 10.089, 10.301, 10.454, 10.585,
];
const typing = (take: Take, keys: number[]): CuelumeCue[] =>
  keys
    .map((k) => clipToFilm(take.segments, k))
    .filter((t): t is number => t !== undefined)
    .map((t): CuelumeCue => ({t, sound: 'type', key: 'printable', input: 'keyboard', emphasis: 'subtle'}));

const F = T.finale;

export const CUELUME_CUES: CuelumeCue[] = [
  {t: T.brand.icon, sound: 'ready'},
  // Library
  {t: at(library, library.clicks.biology) + 0.05, sound: 'navigate', direction: 'forward', emphasis: 'subtle'},
  {t: at(library, library.clicks.openPdf) + 0.08, sound: 'open', emphasis: 'subtle'},
  // Ask
  {t: T.ask.askKey, sound: 'type', key: 'enter', input: 'keyboard'},
  {t: T.ask.askKey + 0.12, sound: 'select'},
  ...typing(ask, ASK_KEYS),
  {t: T.ask.send, sound: 'type', key: 'enter', input: 'keyboard'},
  // Bubble
  {t: at(bubble, bubble.clicks.bubble) + 0.1, sound: 'open', emphasis: 'subtle'},
  {t: at(bubble, bubble.clicks.showInChat) + 0.08, sound: 'navigate', direction: 'back', emphasis: 'subtle'},
  // Page
  {t: at(page, page.clicks.menu) + 0.05, sound: 'open', emphasis: 'subtle'},
  {t: at(page, page.clicks.askPage) + 0.05, sound: 'select'},
  ...typing(page, PAGE_KEYS),
  {t: T.page.send, sound: 'type', key: 'enter', input: 'keyboard'},
  // Reader
  {t: at(reader, reader.clicks.menu) + 0.04, sound: 'open', emphasis: 'subtle'},
  {t: at(reader, reader.clicks.twoPages) + 0.04, sound: 'toggle', input: 'mouse', emphasis: 'subtle'},
  {t: at(reader, reader.clicks.menu2) + 0.04, sound: 'open', emphasis: 'subtle'},
  {t: at(reader, reader.clicks.thumbnails) + 0.04, sound: 'toggle', input: 'mouse', emphasis: 'subtle'},
  // Finale
  {t: F.icon, sound: 'ready'},
  {t: F.available, sound: 'success', emphasis: 'subtle'},
];

// Mixkit sound effects. `at` is when the sound's peak should land unless
// `align: 'start'`; `volume` is relative to the file's levelled loudness.
export type SfxCue = {at: number; id: string; volume: number; align?: 'peak' | 'start'; fadeOut?: number};

export const SFX_CUES: SfxCue[] = [
  {at: T.brand.icon + 0.1, id: '2350', volume: 0.16},
  {at: F.icon + 0.1, id: '2350', volume: 0.14},
  ...CLICKS.map((at): SfxCue => ({at, id: '2997', volume: 0.3, align: 'start', fadeOut: 0.12})),
];
