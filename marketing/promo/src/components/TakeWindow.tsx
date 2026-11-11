import React from 'react';
import {Img, OffthreadVideo, Sequence, staticFile} from 'remotion';
import {easeInOut, mix, ramp} from '../lib/motion';
import {FPS, Focus, Segment, takeTime, toFrame} from '../timeline';
import askCursor from '../../public/crono/ask/cursor.json';
import askMeta from '../../public/crono/ask/take.json';
import bubbleCursor from '../../public/crono/bubble/cursor.json';
import bubbleMeta from '../../public/crono/bubble/take.json';
import libraryCursor from '../../public/crono/library/cursor.json';
import libraryMeta from '../../public/crono/library/take.json';
import pageCursor from '../../public/crono/page/cursor.json';
import pageMeta from '../../public/crono/page/take.json';
import readerCursor from '../../public/crono/reader/cursor.json';
import readerMeta from '../../public/crono/reader/take.json';

// Takes exported by Crono (public/crono/<name>/): the window alone as video, plus
// the pointer Crono drew, one sample per video frame. See Crono's take format.
type CursorArt = {image: string; width: number; height: number; hotspotX: number; hotspotY: number};
type TakeCursor = {
  fps: number;
  art: Record<string, CursorArt | undefined>;
  shapes: string[];
  x: number[];
  y: number[];
  angle: number[];
  press: number[];
  shape: number[];
};
type TakeMeta = {width: number; height: number; duration: number; cornerRadius: number | null; video: string};
type TakeData = {meta: TakeMeta; cursor: TakeCursor};

const TAKE_DATA: Record<string, TakeData> = {
  ask: {meta: askMeta, cursor: askCursor as TakeCursor},
  bubble: {meta: bubbleMeta, cursor: bubbleCursor as TakeCursor},
  library: {meta: libraryMeta, cursor: libraryCursor as TakeCursor},
  page: {meta: pageMeta, cursor: pageCursor as TakeCursor},
  reader: {meta: readerMeta, cursor: readerCursor as TakeCursor},
};

/** Window size in film pixels for a take drawn `width` wide. */
export const windowSize = (name: string, width: number) => {
  const {meta} = TAKE_DATA[name];
  return {width, height: (width * meta.height) / meta.width};
};

/** A Folio window's corner radius in take pixels (2× points). */
const WINDOW_CORNER = 42.25;

const FULL: Focus = {scale: 1, x: 0.5, y: 0.5};

/** The camera at film time `t`: each segment's focus, eased in from the previous one. */
const focusAt = (segments: Segment[], t: number): Focus => {
  const i = segments.findIndex((s) => t >= s.from && t < s.to);
  if (i < 0) return segments[segments.length - 1]?.focus ?? FULL;
  const now = segments[i].focus ?? FULL;
  const before = i > 0 ? segments[i - 1].focus ?? FULL : now;
  // A slow, smooth camera move rather than a snap.
  const p = ramp(t, segments[i].from, 1.1, easeInOut);
  return {scale: mix(before.scale, now.scale, p), x: mix(before.x, now.x, p), y: mix(before.y, now.y, p)};
};

const Cursor: React.FC<{name: string; time: number; width: number; height: number}> = ({name, time, width, height}) => {
  const {meta, cursor} = TAKE_DATA[name];
  const i = Math.min(cursor.x.length - 1, Math.max(0, Math.round(time * cursor.fps)));
  const shape = cursor.shapes[cursor.shape[i]] ?? 'arrow';
  const art = cursor.art[shape] ?? cursor.art.arrow;
  if (!art) return null;
  // As Crono's own exports: the system pointer at 1.6×, pressed in on clicks.
  const k = (width / meta.width) * 1.6 * cursor.press[i];
  const w = art.width * k;
  const h = art.height * k;
  const hx = art.hotspotX * w;
  const hy = art.hotspotY * h;
  return (
    <Img
      src={staticFile(`crono/${name}/${art.image}`)}
      style={{
        position: 'absolute',
        left: cursor.x[i] * width - hx,
        top: cursor.y[i] * height - hy,
        width: w,
        height: h,
        transformOrigin: `${hx}px ${hy}px`,
        // The take's angle turns counterclockwise; CSS turns clockwise.
        transform: `rotate(${-cursor.angle[i]}rad)`,
      }}
    />
  );
};

/**
 * A recorded Folio window with its real corners and a front-window shadow. Each
 * segment plays the take at a constant rate so its anchor lands on the film time
 * the timeline chose; cuts between segments are hard cuts.
 */
export const TakeWindow: React.FC<{
  t: number;
  name: string;
  segments: Segment[];
  width: number;
  /** Draw the recorded pointer (on by default). */
  cursor?: boolean;
  style?: React.CSSProperties;
}> = ({t, name, segments, width, cursor = true, style}) => {
  const {meta} = TAKE_DATA[name];
  const height = (width * meta.height) / meta.width;
  // Takes recorded as a screen area (so menus show) carry no corner radius; their
  // window has the same macOS 26 corners as the window takes.
  const radius = ((meta.cornerRadius ?? WINDOW_CORNER) * width) / meta.width;
  const focus = focusAt(segments, t);
  // Move the focus point to the middle without showing past the window's edges.
  const zoom = focus.scale;
  const tx = Math.min(0, Math.max(width - width * zoom, width / 2 - focus.x * width * zoom));
  const ty = Math.min(0, Math.max(height - height * zoom, height / 2 - focus.y * height * zoom));
  const time = takeTime(segments, t);
  return (
    <div
      style={{
        position: 'absolute',
        width,
        height,
        borderRadius: radius,
        overflow: 'hidden',
        background: '#ececec',
        boxShadow: '0 0 0 0.5px rgba(0,0,0,0.3), 0 14px 36px rgba(0,0,0,0.28), 0 44px 110px rgba(0,0,0,0.38)',
        ...style,
      }}
    >
      <div style={{position: 'absolute', inset: 0, transformOrigin: '0 0', transform: `translate(${tx}px, ${ty}px) scale(${zoom})`}}>
        {segments.map((g, i) => {
          const from = toFrame(g.from);
          const frames = toFrame(g.to) - from;
          const start = g.src;
          return (
            <Sequence key={i} from={from} durationInFrames={frames} layout="none">
              <OffthreadVideo
                src={staticFile(`crono/${name}/${meta.video}`)}
                muted
                trimBefore={Math.max(0, Math.round(start * FPS))}
                playbackRate={g.rate}
                style={{position: 'absolute', inset: 0, width: '100%', height: '100%'}}
              />
            </Sequence>
          );
        })}
        {cursor && time !== undefined ? <Cursor name={name} time={time} width={width} height={height} /> : null}
      </div>
    </div>
  );
};
