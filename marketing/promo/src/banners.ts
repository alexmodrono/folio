// Promotional banners: the app icon and name set in Charis SIL on paper, beside
// a real frame of Folio on an aerial wallpaper. src/Banner.tsx draws them and
// scripts/banners.mjs renders each format into out/banners/. Plain, erasable
// TypeScript so Node can import it.
import type {TakeName} from './timeline.ts';

export type BannerFormat = 'x-header' | 'social' | 'web';

export type BannerLayout = {
  width: number;
  height: number;
  /** Render scale for the PNG. */
  scale: number;
  /** Left edge of the text column, and its top. */
  textLeft: number;
  textTop: number;
  /** Size of the icon; type sizes follow from it. */
  icon: number;
  /** The wallpaper panel: its left edge and its margin from the other edges. */
  panelLeft: number;
  panelMargin: number;
  /** Extra margin under the panel, where `footnote: 'under'` puts the footnote. */
  panelBottom?: number;
  /**
   * The window inside the panel: its width, its gap from the panel's right edge
   * (it runs off the left, so the chat beside the page stays in view) and top.
   */
  windowWidth: number;
  windowRight: number;
  windowY: number;
  /** The not-affiliated note: under the text, or under the panel at the right. */
  footnote: 'column' | 'under';
};

export const BANNER = {
  take: 'page' as TakeName,
  /** Take time of the frame: the answer beside the page. */
  time: 13.4,
  wallpaper: 'tahoe',
  wallpaperTime: 3,
};

export const BANNERS: Record<BannerFormat, BannerLayout> = {
  // X profile header, 3:1. The profile picture covers the bottom left, so the
  // text sits high and the footnote goes under the panel at the right.
  'x-header': {width: 1500, height: 500, scale: 2, textLeft: 90, textTop: 92, icon: 92, panelLeft: 700, panelMargin: 30, panelBottom: 64, windowWidth: 980, windowRight: 34, windowY: 46, footnote: 'under'},
  // Link previews (Open Graph, GitHub social preview, Reddit), 2:1.
  social: {width: 1280, height: 640, scale: 2, textLeft: 72, textTop: 156, icon: 86, panelLeft: 560, panelMargin: 34, windowWidth: 900, windowRight: 36, windowY: 56, footnote: 'column'},
  // A wide banner for the website or a Reddit post, 16:9.
  web: {width: 1920, height: 1080, scale: 4 / 3, textLeft: 112, textTop: 340, icon: 128, panelLeft: 820, panelMargin: 48, windowWidth: 1200, windowRight: 56, windowY: 110, footnote: 'column'},
};
