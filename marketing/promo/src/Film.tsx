import React from 'react';
import {AbsoluteFill, Html5Audio, Sequence, interpolate, staticFile} from 'remotion';
import {MIXKIT_SFX, MixkitId} from './audio/mixkit';
import {loadFonts} from './lib/fonts';
import {easeInOut, ramp, useTime} from './lib/motion';
import {Badge, Brand, Details, Finale, Stays} from './scenes/Cards';
import {RecordingScene} from './scenes/Recordings';
import {DURATION, FPS, SCENES, SFX_CUES, Span, XF, toFrame} from './timeline';

loadFonts();

const MUSIC_VOLUME = 0.85;
// The music steps back a little under the recordings, where the interface talks.
const UNDER = 0.62;
const CUELUME_VOLUME = 0.8;

const dbToGain = (db: number) => Math.pow(10, db / 20);

/** Mixkit cues, each placed so its peak (or start) lands on the timeline's time. */
const SoundEffects: React.FC = () => (
  <>
    {SFX_CUES.map((cue, i) => {
      const sfx = MIXKIT_SFX[cue.id as MixkitId];
      const start = cue.align === 'start' ? cue.at : cue.at - sfx.peak;
      const from = toFrame(Math.max(0, start));
      const trimBefore = start < 0 ? toFrame(-start) : 0;
      const volume = Math.min(1, cue.volume * dbToGain(sfx.gainDb));
      const length = cue.fadeOut ?? sfx.duration;
      const frames = Math.max(1, toFrame(length) - trimBefore);
      return (
        <Sequence key={`${cue.id}-${i}`} from={from} durationInFrames={frames} name={`Mixkit ${cue.id} · ${sfx.title}`} layout="none">
          <Html5Audio
            src={staticFile(`audio/mixkit/${cue.id}.wav`)}
            trimBefore={trimBefore || undefined}
            volume={(f) =>
              cue.fadeOut ? volume * interpolate(f, [0, frames - 3, frames], [1, 1, 0], {extrapolateRight: 'clamp'}) : volume
            }
          />
        </Sequence>
      );
    })}
  </>
);

/**
 * One scene, dissolving in over the scene before it. A scene stays on screen
 * XF past its slot, under the next one's dissolve.
 */
const Layer: React.FC<{t: number; span: Span; children: React.ReactNode}> = ({t, span, children}) => {
  if (t < span.from || t >= span.to + XF) return null;
  const opacity = span.from === 0 ? 1 : ramp(t, span.from, XF, easeInOut);
  return <AbsoluteFill style={{opacity}}>{children}</AbsoluteFill>;
};

const RECORDINGS = [SCENES.library, SCENES.ask, SCENES.bubble, SCENES.page, SCENES.reader];

/** Music level: full on the title cards, a little under on the recordings, out at the end. */
const musicVolume = (t: number) => {
  const under = RECORDINGS.some((s) => t >= s.from && t < s.to + XF);
  const level = under ? UNDER : MUSIC_VOLUME;
  return level * interpolate(t, [DURATION - 1.2, DURATION], [1, 0], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
};

export const Film: React.FC = () => {
  const t = useTime();
  return (
    <AbsoluteFill style={{background: '#000'}}>
      <Layer t={t} span={SCENES.ask}>
        <RecordingScene t={t} take="ask" />
        <Badge t={t} />
      </Layer>
      <Layer t={t} span={SCENES.brand}><Brand t={t} /></Layer>
      <Layer t={t} span={SCENES.library}><RecordingScene t={t} take="library" /></Layer>
      <Layer t={t} span={SCENES.stays}><Stays t={t} /></Layer>
      <Layer t={t} span={SCENES.bubble}><RecordingScene t={t} take="bubble" /></Layer>
      <Layer t={t} span={SCENES.page}><RecordingScene t={t} take="page" /></Layer>
      <Layer t={t} span={SCENES.reader}><RecordingScene t={t} take="reader" /></Layer>
      <Layer t={t} span={SCENES.details}><Details t={t} /></Layer>
      <Layer t={t} span={SCENES.finale}><Finale t={t} /></Layer>

      {/* The level changes are smoothed over a few frames so they never click. */}
      <Html5Audio
        src={staticFile('audio/music-bed.wav')}
        volume={(f) => {
          const at = f / FPS;
          let sum = 0;
          for (let k = -12; k <= 12; k++) sum += musicVolume(at + k / FPS * 2);
          return sum / 25;
        }}
      />
      <Html5Audio src={staticFile('audio/cuelume.wav')} volume={CUELUME_VOLUME} />
      <SoundEffects />
    </AbsoluteFill>
  );
};
