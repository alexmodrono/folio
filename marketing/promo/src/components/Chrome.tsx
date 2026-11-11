import React from 'react';
import {AbsoluteFill, Img, staticFile} from 'remotion';

export const FONT = 'system-ui, -apple-system, "SF Pro Text", "Helvetica Neue", sans-serif';
// Newsreader (SIL OFL, public/fonts/): a serif drawn for reading on screens.
export const SERIF = 'Newsreader, "New York", Georgia, serif';
/** The banners' type (SIL Open Font License, public/fonts/charis/). */
export const CHARIS = '"Charis SIL", Georgia, serif';

// The icon's colors: teal water, coral and amber sand.
export const TEAL = '#14a8a0';
export const CORAL = '#f0734f';
export const AMBER = '#f5c04a';
// Warm ink on warm paper, like a printed page.
export const INK = '#26221d';
export const MUTED = '#7a7268';
export const PAPER = '#f7f3ec';

/** The film's stage for words: a warm sheet of paper with a soft light falling on it. */
export const Stage: React.FC<{children?: React.ReactNode}> = ({children}) => (
  <AbsoluteFill style={{background: `radial-gradient(90% 80% at 50% 38%, #fbf8f3 0%, ${PAPER} 55%, #efe8dc 100%)`}}>
    {children}
  </AbsoluteFill>
);

export const AppIcon: React.FC<{size: number; style?: React.CSSProperties}> = ({size, style}) => (
  <Img src={staticFile('images/folio-icon.png')} style={{width: size, height: size, display: 'block', ...style}} />
);
