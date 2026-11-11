import React from 'react';
import {Desktop} from '../components/Desktop';
import {Captions} from '../components/Type';
import {TakeWindow, windowSize} from '../components/TakeWindow';
import {mix, ramp} from '../lib/motion';
import {CAPTIONS, SCENES, TAKES, TakeName, XF} from '../timeline';

const WINDOW_WIDTH = 1460;
const WINDOW_TOP = 36;

/** A real Folio window on a Mac desktop, with a caption underneath. */
export const RecordingScene: React.FC<{t: number; take: TakeName}> = ({t, take}) => {
  const scene = SCENES[take];
  const end = scene.to + XF;
  const {name, segments, wallpaper, wallpaperOffset} = TAKES[take];
  const size = windowSize(name, WINDOW_WIDTH);
  // A very slow push-in over the whole scene, so the shot is never quite still.
  const push = mix(1, 1.025, ramp(t, scene.from, end - scene.from, (x) => x));
  return (
    <Desktop wallpaper={wallpaper} from={scene.from} to={end} offset={wallpaperOffset}>
      <div
        style={{
          position: 'absolute',
          inset: 0,
          transform: `scale(${push})`,
          transformOrigin: `50% ${WINDOW_TOP + size.height / 2}px`,
        }}
      >
        <TakeWindow t={t} name={name} segments={segments} width={WINDOW_WIDTH} style={{left: (1920 - WINDOW_WIDTH) / 2, top: WINDOW_TOP}} />
      </div>
      <Captions t={t} captions={CAPTIONS[take]} end={end} />
    </Desktop>
  );
};
