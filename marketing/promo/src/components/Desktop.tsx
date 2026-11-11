import React from 'react';
import {AbsoluteFill, OffthreadVideo, Sequence, staticFile} from 'remotion';
import {FPS, toFrame} from '../timeline';

/**
 * A Mac desktop for the recordings: one of Apple's aerial wallpapers, moving
 * slowly behind the window. `offset` picks where in the clip the scene starts.
 */
export const Desktop: React.FC<{
  wallpaper: string;
  from: number;
  to: number;
  offset?: number;
  children?: React.ReactNode;
}> = ({wallpaper, from, to, offset = 0, children}) => (
  <AbsoluteFill style={{background: '#111'}}>
    <Sequence from={toFrame(from)} durationInFrames={toFrame(to) - toFrame(from)} layout="none">
      <OffthreadVideo
        src={staticFile(`backgrounds/${wallpaper}.mp4`)}
        muted
        trimBefore={Math.round(offset * FPS)}
        style={{position: 'absolute', inset: 0, width: '100%', height: '100%', objectFit: 'cover'}}
      />
    </Sequence>
    {/* Shade under the caption so white type reads on any wallpaper. */}
    <AbsoluteFill style={{background: 'linear-gradient(0deg, rgba(0,0,0,0.5) 0%, rgba(0,0,0,0.18) 14%, rgba(0,0,0,0) 30%)'}} />
    {children}
  </AbsoluteFill>
);
