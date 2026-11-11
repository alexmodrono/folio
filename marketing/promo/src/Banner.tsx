import React from 'react';
import {AbsoluteFill, OffthreadVideo, staticFile} from 'remotion';
import {AppIcon, CHARIS, INK, MUTED, PAPER} from './components/Chrome';
import {TakeWindow} from './components/TakeWindow';
import {loadFonts} from './lib/fonts';
import {BANNER, BANNERS, BannerFormat} from './banners';
import {FPS} from './timeline';

loadFonts();

export const Banner: React.FC<{format: BannerFormat}> = ({format}) => {
  const L = BANNERS[format];
  const u = L.icon / 100;
  const m = L.panelMargin;
  return (
    <AbsoluteFill style={{background: PAPER}}>
      {/* The desktop: a framed aerial wallpaper with the window running off its edges. */}
      <div
        style={{
          position: 'absolute',
          left: L.panelLeft,
          top: m,
          right: m,
          bottom: L.panelBottom ?? m,
          borderRadius: 26 * u,
          overflow: 'hidden',
          background: '#111',
          boxShadow: '0 0 0 1px rgba(38,34,29,0.08), 0 18px 50px rgba(38,34,29,0.16)',
        }}
      >
        <OffthreadVideo
          src={staticFile(`backgrounds/${BANNER.wallpaper}.mp4`)}
          muted
          trimBefore={Math.round(BANNER.wallpaperTime * FPS)}
          style={{position: 'absolute', inset: 0, width: '100%', height: '100%', objectFit: 'cover'}}
        />
        <TakeWindow
          t={0}
          name={BANNER.take}
          segments={[{src: BANNER.time, from: 0, to: 10, rate: 0.0001, focus: {scale: 1, x: 0.5, y: 0.5}}]}
          width={L.windowWidth}
          cursor={false}
          style={{right: L.windowRight, top: L.windowY}}
        />
      </div>

      <div style={{position: 'absolute', left: L.textLeft, top: L.textTop, color: INK, fontFamily: CHARIS}}>
        <div style={{display: 'flex', alignItems: 'center', gap: 26 * u}}>
          <AppIcon size={L.icon} style={{filter: `drop-shadow(0 ${6 * u}px ${14 * u}px rgba(20,168,160,0.25))`}} />
          <div style={{fontSize: 96 * u, fontWeight: 700, letterSpacing: '-0.01em', lineHeight: 1}}>Folio</div>
        </div>
        <div style={{fontSize: 46 * u, fontStyle: 'italic', marginTop: 26 * u, lineHeight: 1.15}}>Read a PDF. Ask about it.</div>
        <div style={{fontSize: 26 * u, color: MUTED, marginTop: 18 * u, display: 'flex', gap: 14 * u}}>
          <span style={{color: INK, fontWeight: 700}}>For Mac</span>
          <span>·</span>
          <span>pdf.amodrono.com</span>
        </div>
        {L.footnote === 'column' ? <Footnote size={18 * u} style={{marginTop: 26 * u}} /> : null}
      </div>
      {L.footnote === 'under' ? (
        <Footnote size={13} inline style={{position: 'absolute', right: m + 8, bottom: 22}} />
      ) : null}
    </AbsoluteFill>
  );
};

const Footnote: React.FC<{size: number; inline?: boolean; style?: React.CSSProperties}> = ({size, inline, style}) => (
  <div style={{fontFamily: CHARIS, fontSize: size, color: MUTED, lineHeight: 1.4, ...style}}>
    Works with your own ChatGPT account.{inline ? ' ' : <br />}Folio isn’t affiliated with OpenAI.
  </div>
);
