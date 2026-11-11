import {Easing, interpolate, spring, useCurrentFrame} from 'remotion';
import {FPS} from '../timeline';

export const clamp = {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'} as const;

// Strong ease-out for entrances, symmetric ease for on-screen movement.
export const easeOut = Easing.bezier(0.16, 1, 0.3, 1);
export const easeInOut = Easing.bezier(0.65, 0, 0.35, 1);
export const easeIn = Easing.bezier(0.7, 0, 0.84, 0);

/** Film time in seconds. Every scene works in absolute film time. */
export const useTime = () => useCurrentFrame() / FPS;

/** 0 → 1 over `duration` seconds starting at `start`. */
export const ramp = (t: number, start: number, duration: number, easing: (x: number) => number = easeOut) =>
  interpolate(t, [start, start + duration], [0, 1], {...clamp, easing});

/** Fade in at `start`, fade out ending at `end`. */
export const window01 = (t: number, start: number, end: number, fadeIn = 0.3, fadeOut = 0.3) =>
  Math.min(ramp(t, start, fadeIn), 1 - ramp(t, end - fadeOut, fadeOut, easeIn));

export const springAt = (
  t: number,
  start: number,
  config: {stiffness?: number; damping?: number; mass?: number} = {},
) => spring({frame: (t - start) * FPS, fps: FPS, config: {stiffness: 170, damping: 26, mass: 1, ...config}});

export const mix = (from: number, to: number, progress: number) => from + (to - from) * progress;

/** Picks the value of the last keyframe whose time has passed. */
export const step = <V,>(t: number, keyframes: [number, V][]) => {
  let value = keyframes[0][1];
  for (const [time, v] of keyframes) if (t >= time) value = v;
  return value;
};

/** Eased motion through [time, value] keyframes. */
export const keyframes = (t: number, frames: [number, number][], easing = easeInOut) => {
  if (t <= frames[0][0]) return frames[0][1];
  for (let i = 1; i < frames.length; i++) {
    const [t1, v1] = frames[i];
    const [t0, v0] = frames[i - 1];
    if (t <= t1) return mix(v0, v1, easing((t - t0) / Math.max(1e-6, t1 - t0)));
  }
  return frames[frames.length - 1][1];
};
