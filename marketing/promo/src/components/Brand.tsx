import React from 'react';
import {AppIcon} from './Chrome';
import {easeOut, ramp} from '../lib/motion';

/** The app icon settling in: a slow fade and a slight grow, with a soft teal shadow. */
export const BrandIcon: React.FC<{t: number; at: number; size: number}> = ({t, at, size}) => {
  const p = t < at ? 0 : ramp(t, at, 1.2, easeOut);
  return (
    <div
      style={{
        width: size,
        height: size,
        opacity: p,
        transform: `translateY(${(1 - p) * 18}px) scale(${0.94 + 0.06 * p})`,
        filter: `drop-shadow(0 ${size * 0.07}px ${size * 0.16}px rgba(20,168,160,0.22))`,
      }}
    >
      <AppIcon size={size} />
    </div>
  );
};
