import React from 'react';
import {AbsoluteFill} from 'remotion';
import {BrandIcon} from '../components/Brand';
import {AppIcon, INK, MUTED, SERIF, Stage, TEAL} from '../components/Chrome';
import {ArrowDownDocIcon, CheckIcon, FolderIcon, GlobeIcon, MagnifierIcon, PersonCheckIcon} from '../components/Icons';
import {Line, Small, enter, entering} from '../components/Type';
import {easeInOut, ramp} from '../lib/motion';
import {BLACK, T} from '../timeline';

const Centre: React.FC<{children: React.ReactNode; gap?: number; style?: React.CSSProperties}> = ({children, gap = 0, style}) => (
  <AbsoluteFill style={{display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap, ...style}}>
    {children}
  </AbsoluteFill>
);

/**
 * The name in the corner of the opening shot, there from the first frame, so
 * anyone who scrolls on after a few seconds still knows what they saw.
 */
export const Badge: React.FC<{t: number}> = () => (
  <div style={{position: 'absolute', left: 40, top: 42, display: 'flex', alignItems: 'center', gap: 12}}>
    <AppIcon size={56} style={{filter: 'drop-shadow(0 3px 10px rgba(0,0,0,0.3))'}} />
    <div
      style={{
        fontFamily: SERIF,
        fontSize: 42,
        fontWeight: 600,
        color: '#fff',
        letterSpacing: '-0.02em',
        textShadow: '0 2px 12px rgba(0,0,0,0.45)',
      }}
    >
      Folio
    </div>
  </div>
);

/** Right after the first demo: the icon, the name and what it does. */
export const Brand: React.FC<{t: number}> = ({t}) => (
  <Stage>
    <Centre>
      <BrandIcon t={t} at={T.brand.icon} size={210} />
      <Line t={t} at={T.brand.name} size={150} weight={600} style={{marginTop: 26, letterSpacing: '-0.025em'}}>
        Folio
      </Line>
      <Line t={t} at={T.brand.tagline} size={60} italic weight={400} color={MUTED} style={{marginTop: 6}}>
        Read a PDF. Ask about it.
      </Line>
    </Centre>
  </Stage>
);

/** Between the library and the bubbles. */
export const Stays: React.FC<{t: number}> = ({t}) => (
  <Stage>
    <Centre>
      <Line t={t} at={T.stays.lines[0]}>Every question</Line>
      <Line t={t} at={T.stays.lines[1]} italic color={TEAL}>
        stays on its page.
      </Line>
    </Centre>
  </Stage>
);

const DETAILS: {icon: React.ReactElement<{size?: number; weight?: number}>; text: string}[] = [
  {icon: <PersonCheckIcon />, text: 'Uses your own ChatGPT account.'},
  {icon: <CheckIcon />, text: 'Nothing is sent until you press Send.'},
  {icon: <ArrowDownDocIcon />, text: 'Each PDF is uploaded once per chat.'},
  {icon: <FolderIcon />, text: 'Your library is a plain folder.'},
  {icon: <MagnifierIcon />, text: 'Find, zoom and print.'},
  {icon: <GlobeIcon />, text: 'In English and Spanish.'},
];

/** The last chorus: the things worth knowing, one at a time. */
export const Details: React.FC<{t: number}> = ({t}) => (
  <Stage>
    <Centre>
      <div style={{display: 'flex', flexDirection: 'column', gap: 30}}>
        {DETAILS.map((d, i) => (
          <div key={d.text} style={{display: 'flex', alignItems: 'center', gap: 30, ...entering(enter(t, T.details.items[i], 0.8), 12)}}>
            <div style={{color: TEAL, display: 'flex', width: 48, justifyContent: 'center'}}>
              {React.cloneElement(d.icon, {size: 42, weight: 1.8})}
            </div>
            <div style={{fontFamily: SERIF, fontSize: 56, fontWeight: 500, color: INK, letterSpacing: '-0.012em', fontVariationSettings: `"opsz" 48`}}>
              {d.text}
            </div>
          </div>
        ))}
      </div>
    </Centre>
  </Stage>
);

/** The end: the icon and name, where to get it, then black. */
export const Finale: React.FC<{t: number}> = ({t}) => {
  const F = T.finale;
  const dark = ramp(t, BLACK, 1.8, easeInOut);
  return (
    <Stage>
      <Centre style={{paddingBottom: 40}}>
        <BrandIcon t={t} at={F.icon} size={180} />
        <Line t={t} at={F.name} size={130} weight={600} style={{marginTop: 22, letterSpacing: '-0.025em'}}>
          Folio
        </Line>
        <Line t={t} at={F.tagline} size={56} italic weight={400} color={MUTED} style={{marginTop: 4}}>
          Read a PDF. Ask about it.
        </Line>
        <div style={{marginTop: 46, ...entering(enter(t, F.available), 10)}}>
          <Small style={{fontSize: 32, color: INK, fontWeight: 600}}>Available now for Mac</Small>
        </div>
        <div style={{marginTop: 18, display: 'flex', alignItems: 'center', gap: 18, ...entering(enter(t, F.url), 10)}}>
          <div
            style={{
              fontFamily: 'system-ui, -apple-system, sans-serif',
              fontSize: 30,
              fontWeight: 600,
              color: '#fff',
              background: INK,
              padding: '14px 30px',
              borderRadius: 999,
              letterSpacing: '-0.005em',
            }}
          >
            pdf.amodrono.com
          </div>
          <Small>macOS 26 or later</Small>
        </div>
      </Centre>
      <div style={{position: 'absolute', left: 0, right: 0, bottom: 52, textAlign: 'center', ...entering(enter(t, F.url), 0)}}>
        <Small style={{fontSize: 22, color: 'rgba(38,34,29,0.45)'}}>Works with your own ChatGPT account. Folio isn’t affiliated with OpenAI.</Small>
      </div>
      <AbsoluteFill style={{background: '#000', opacity: dark}} />
    </Stage>
  );
};
