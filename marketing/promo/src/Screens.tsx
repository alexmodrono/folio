import React from 'react';
import {AbsoluteFill} from 'remotion';
import {AppIcon, FONT, SERIF} from './components/Chrome';
import {Desktop} from './components/Desktop';
import {TakeWindow, windowSize} from './components/TakeWindow';
import {loadFonts} from './lib/fonts';
import {FORMATS, Format, SHOTS} from './shots';

loadFonts();

const shadow = '0 2px 18px rgba(0,0,0,0.45), 0 1px 3px rgba(0,0,0,0.3)';

const Badge: React.FC<{size: number}> = ({size}) => (
  <div style={{display: 'flex', alignItems: 'center', gap: size * 0.22}}>
    <AppIcon size={size} style={{filter: 'drop-shadow(0 3px 10px rgba(0,0,0,0.3))'}} />
    <div style={{fontFamily: SERIF, fontSize: size * 0.75, fontWeight: 600, color: '#fff', letterSpacing: '-0.02em', textShadow: shadow}}>
      Folio
    </div>
  </div>
);

const Footnote: React.FC<{size: number}> = ({size}) => (
  <div style={{fontFamily: FONT, fontSize: size, color: 'rgba(255,255,255,0.72)', textShadow: '0 1px 6px rgba(0,0,0,0.5)'}}>
    Works with your own ChatGPT account. Folio isn’t affiliated with OpenAI.
  </div>
);

export const Screen: React.FC<{shot: string; format: Format}> = ({shot: id, format}) => {
  const shot = SHOTS.find((s) => s.id === id) ?? SHOTS[0];
  const wide = format === 'wide';
  const width = wide ? 1360 : 1300;
  const size = windowSize(shot.take, width);
  const segments = [{src: shot.time, from: 0, to: 10, rate: 0.0001, focus: wide ? shot.focus : {scale: 1, x: 0.5, y: 0.5}}];
  const top = wide ? 166 : 1350 - size.height - 92;
  const anchors = {left: 40, center: (1080 - width) / 2, right: 1080 - 40 - width};
  const left = wide ? (1920 - width) / 2 : typeof shot.tall === 'number' ? shot.tall : anchors[shot.tall];
  return (
    <Desktop wallpaper={shot.wallpaper} from={0} to={10} offset={shot.wallpaperTime}>
      {/* Shade at the top for the headline. */}
      <AbsoluteFill style={{background: `linear-gradient(180deg, rgba(0,0,0,0.42) 0%, rgba(0,0,0,0.12) ${wide ? 20 : 34}%, rgba(0,0,0,0) ${wide ? 34 : 50}%)`}} />
      {wide ? (
        <div style={{position: 'absolute', left: 40, top: 38}}>
          <Badge size={50} />
        </div>
      ) : (
        <div style={{position: 'absolute', top: 64, left: 0, right: 0, display: 'flex', justifyContent: 'center'}}>
          <Badge size={58} />
        </div>
      )}
      <div
        style={{
          position: 'absolute',
          left: 60,
          right: 60,
          top: wide ? 30 : 150,
          textAlign: 'center',
          color: '#fff',
          textShadow: shadow,
          textWrap: 'balance',
        }}
      >
        <div style={{fontFamily: SERIF, fontSize: wide ? 64 : 74, fontWeight: 600, letterSpacing: '-0.02em', lineHeight: 1.08, fontVariationSettings: '"opsz" 72'}}>
          {shot.headline}
        </div>
        <div style={{fontFamily: SERIF, fontStyle: 'italic', fontSize: wide ? 32 : 36, fontWeight: 400, marginTop: wide ? 8 : 16, opacity: 0.92, lineHeight: 1.25}}>
          {shot.sub}
        </div>
      </div>
      <TakeWindow
        t={0}
        name={shot.take}
        segments={segments}
        width={width}
        cursor={shot.cursor ?? true}
        style={{left, top}}
      />
      <div style={{position: 'absolute', left: 0, right: 0, bottom: wide ? 22 : 34, display: 'flex', justifyContent: 'center'}}>
        <Footnote size={wide ? 17 : 22} />
      </div>
    </Desktop>
  );
};
