import React from 'react';
import {Composition} from 'remotion';
import {Banner} from './Banner';
import {BANNERS, BannerFormat} from './banners';
import {Film} from './Film';
import {Screen} from './Screens';
import {FORMATS, SHOTS} from './shots';
import {DURATION, FPS, HEIGHT, WIDTH} from './timeline';

export const Root: React.FC = () => (
  <>
  <Composition
    id="Folio10"
    component={Film}
    durationInFrames={Math.round(DURATION * FPS)}
    fps={FPS}
    width={WIDTH}
    height={HEIGHT}
  />

  {(['wide', 'tall'] as const).map((format) => (
    <Composition
      key={format}
      id={`Screen-${format}`}
      component={Screen}
      durationInFrames={1}
      fps={FPS}
      width={FORMATS[format].width}
      height={FORMATS[format].height}
      defaultProps={{shot: SHOTS[0].id, format}}
    />
  ))}

  {(Object.keys(BANNERS) as BannerFormat[]).map((format) => (
    <Composition
      key={format}
      id={`Banner-${format}`}
      component={Banner}
      durationInFrames={1}
      fps={FPS}
      width={BANNERS[format].width}
      height={BANNERS[format].height}
      defaultProps={{format}}
    />
  ))}
  </>
);
