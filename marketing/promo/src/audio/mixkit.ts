// Mixkit sound effects and music (Mixkit Sound Effects / Stock Music Free Licenses:
// commercial use, no attribution required, no redistribution of the raw files).
// scripts/fetch-mixkit.mjs downloads these into public/audio/mixkit/.
//
// `peak` is when the loudest 20 ms window occurs, so cues can land a sound's
// hit on a frame. `gainDb` levels each file to a common peak loudness (-12 dB
// RMS); per-cue volume in timeline.ts is relative to that.
// This file is plain, erasable TypeScript so Node can import it directly.

export type MixkitSfx = {title: string; peak: number; duration: number; gainDb: number};

export const MIXKIT_SFX = {
  '2350': {title: 'Magic sparkle whoosh', peak: 0.44, duration: 3.5, gainDb: 0.4},
  '2997': {title: 'Clear mouse clicks', peak: 0.0, duration: 1.05, gainDb: 6.6},
} satisfies Record<string, MixkitSfx>;

export type MixkitId = keyof typeof MIXKIT_SFX;

// "Sweet September" (Mixkit stock music #282), about 95 BPM; bar k starts at
// 0.576 + k × 2.5247 s in the source. The bed starts half a bar before bar 2,
// so the film's grid matches the source's, keeps the end of the quiet intro
// and the band coming in (bars 2–7), then jumps from bar 8 to bar 18, where the same
// groove is already at full strength, and plays on through the breakdown, the
// last chorus and the song's own ending. Bars 8 and 18 line up to within 16 ms;
// a short equal-power crossfade sits just before the edit's downbeat.
export const MUSIC = {
  id: '282',
  title: 'Sweet September',
  segments: [
    [5.049, 20.76],
    [46.023, 96],
  ],
  crossfade: 0.03,
} as const;
