// Promotional screenshots: one real frame of a take on an aerial wallpaper,
// with a headline, in the film's look. src/Screens.tsx draws them and
// scripts/screenshots.mjs renders every shot in both formats into
// out/screenshots/. Plain, erasable TypeScript so Node can import it.
import type {Focus, TakeName} from './timeline.ts';

export type Format = 'wide' | 'tall';

export type Shot = {
  id: string;
  take: TakeName;
  /** Take time of the frame, in seconds of its video.mp4. */
  time: number;
  headline: string;
  sub: string;
  wallpaper: string;
  wallpaperTime: number;
  cursor?: boolean;
  /** Camera in the 16:9 format. */
  focus: Focus;
  /**
   * In the 4:5 format the window is wider than the frame and runs off one
   * edge: `left` keeps the sidebar and pages in view, `right` the chat, or a
   * number gives the window's left edge in frame pixels.
   */
  tall: 'left' | 'center' | 'right' | number;
};

export const SHOTS: Shot[] = [
  {
    id: '1-ask-about-it',
    take: 'page',
    time: 13.4,
    headline: 'Read a PDF. Ask about it.',
    sub: 'Answers appear right beside the page you’re reading.',
    wallpaper: 'tahoe',
    wallpaperTime: 3,
    cursor: false,
    focus: {scale: 1, x: 0.5, y: 0.5},
    tall: 'right',
  },
  {
    id: '2-select-a-passage',
    take: 'ask',
    time: 6.3,
    headline: 'Select a passage and press ⌘L.',
    sub: 'It goes into your question as a quote, with its page.',
    wallpaper: 'gg-sunset',
    wallpaperTime: 2,
    cursor: false,
    focus: {scale: 1, x: 0.5, y: 0.5},
    // The selected passage at the left, its chip in the chat at the right.
    tall: -170,
  },
  {
    id: '3-question-bubbles',
    take: 'bubble',
    time: 3.6,
    headline: 'Every question stays on its page.',
    sub: 'A bubble in the margin takes you back to the conversation.',
    wallpaper: 'sequoia-morning',
    wallpaperTime: 4,
    focus: {scale: 1, x: 0.5, y: 0.5},
    tall: 'right',
  },
  {
    id: '4-whole-page',
    take: 'page',
    time: 3.7,
    headline: 'Ask about a whole page.',
    sub: 'Folio sends a picture of it, figures included.',
    wallpaper: 'gg-bay',
    wallpaperTime: 6,
    focus: {scale: 1, x: 0.5, y: 0.5},
    tall: 'center',
  },
  {
    id: '5-reader',
    take: 'reader',
    time: 9.4,
    headline: 'A real Mac PDF reader.',
    sub: 'Two pages, book mode, thumbnails, find and zoom.',
    wallpaper: 'sonoma-evening',
    wallpaperTime: 5,
    cursor: false,
    focus: {scale: 1, x: 0.5, y: 0.5},
    tall: 'left',
  },
  {
    id: '6-library',
    take: 'library',
    time: 1.8,
    headline: 'All your PDFs, in one quiet library.',
    sub: 'A plain folder on your Mac, with folders and favorites.',
    wallpaper: 'sonoma-evening',
    wallpaperTime: 10,
    cursor: false,
    focus: {scale: 1, x: 0.5, y: 0.5},
    tall: 'left',
  },
];

export const FORMATS: Record<Format, {width: number; height: number; scale: number}> = {
  // 16:9, rendered at 2560 × 1440: website, X, Reddit.
  wide: {width: 1920, height: 1080, scale: 4 / 3},
  // 4:5, rendered at 1620 × 2025: tall posts in phone feeds.
  tall: {width: 1080, height: 1350, scale: 1.5},
};

