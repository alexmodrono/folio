import React from 'react';
import {FONT, INK, SERIF} from './Chrome';
import {easeIn, easeOut, ramp} from '../lib/motion';

/** How far along a gentle entrance is: a fade, a small rise and a blur that clears. */
export const enter = (t: number, at: number, duration = 0.9) => (t < at ? 0 : ramp(t, at, duration, easeOut));

export const entering = (p: number, rise = 16): React.CSSProperties => ({
  opacity: p,
  transform: `translateY(${(1 - p) * rise}px)`,
  filter: p < 1 ? `blur(${(1 - p) * 6}px)` : undefined,
});

/** A line of serif type that settles into place at `at`, whole, never word by word. */
export const Line: React.FC<{
  t: number;
  at: number;
  children: React.ReactNode;
  size?: number;
  italic?: boolean;
  weight?: number;
  color?: string;
  style?: React.CSSProperties;
}> = ({t, at, children, size = 96, italic = false, weight = 500, color = INK, style}) => (
  <div
    style={{
      fontFamily: SERIF,
      fontSize: size,
      fontWeight: weight,
      fontStyle: italic ? 'italic' : 'normal',
      fontVariationSettings: `"opsz" 72`,
      letterSpacing: '-0.015em',
      lineHeight: 1.12,
      color,
      whiteSpace: 'nowrap',
      ...entering(enter(t, at)),
      ...style,
    }}
  >
    {children}
  </div>
);

/**
 * The caption under a recording. Each caption fades in at its time and out just
 * before the next, so only one is ever on screen.
 */
export const Captions: React.FC<{t: number; captions: {at: number; text: string}[]; end: number}> = ({t, captions, end}) => (
  <>
    {captions.map((c, i) => {
      const next = captions[i + 1]?.at ?? end;
      if (t < c.at || t >= next) return null;
      const p = enter(t, c.at, 0.7);
      const out = i < captions.length - 1 ? ramp(t, next - 0.3, 0.3, easeIn) : 0;
      return (
        <div
          key={i}
          style={{
            position: 'absolute',
            left: 0,
            right: 0,
            bottom: 34,
            textAlign: 'center',
            fontFamily: SERIF,
            fontSize: 50,
            fontWeight: 500,
            fontVariationSettings: `"opsz" 48`,
            letterSpacing: '-0.01em',
            color: '#fff',
            textShadow: '0 2px 16px rgba(0,0,0,0.45), 0 1px 3px rgba(0,0,0,0.3)',
            ...entering(p, 10),
            opacity: p * (1 - out),
          }}
        >
          {c.text}
        </div>
      );
    })}
  </>
);

/** Small sans-serif type, for facts like the website and system requirements. */
export const Small: React.FC<{children: React.ReactNode; style?: React.CSSProperties}> = ({children, style}) => (
  <div style={{fontFamily: FONT, fontSize: 28, color: 'rgba(38,34,29,0.6)', letterSpacing: '-0.005em', ...style}}>{children}</div>
);
