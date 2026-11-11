import React from 'react';

// Line icons drawn in the spirit of the SF Symbols the app uses.
// All share a 24-unit grid, round caps, and inherit `currentColor`.

type IconProps = {size?: number; color?: string; weight?: number; style?: React.CSSProperties};

const Svg: React.FC<IconProps & {children: React.ReactNode; fill?: boolean}> = ({
  size = 16,
  color = 'currentColor',
  weight = 1.7,
  style,
  children,
  fill = false,
}) => (
  <svg
    width={size}
    height={size}
    viewBox="0 0 24 24"
    fill={fill ? color : 'none'}
    stroke={fill ? 'none' : color}
    strokeWidth={weight}
    strokeLinecap="round"
    strokeLinejoin="round"
    style={{display: 'block', flexShrink: 0, ...style}}
  >
    {children}
  </svg>
);

export const FolderIcon = (p: IconProps) => (
  <Svg {...p}>
    <path d="M3 7.2A2.2 2.2 0 0 1 5.2 5h3.9c.5 0 1 .2 1.4.6l1.4 1.4c.4.4.9.6 1.4.6h5.5A2.2 2.2 0 0 1 21 9.8v8a2.2 2.2 0 0 1-2.2 2.2H5.2A2.2 2.2 0 0 1 3 17.8z" />
    <path d="M3 10h18" />
  </Svg>
);

export const DocRichTextIcon = (p: IconProps) => (
  <Svg {...p}>
    <path d="M6.5 3h7.8L19 7.7v11.1A2.2 2.2 0 0 1 16.8 21H6.5a2.2 2.2 0 0 1-2.2-2.2V5.2A2.2 2.2 0 0 1 6.5 3z" />
    <path d="M14 3.2v3.6c0 .6.4 1 1 1h3.8" />
    <rect x="7.3" y="10.6" width="3.6" height="3.4" rx=".6" />
    <path d="M13 11h3M13 13.6h3M7.4 17h8.6" />
  </Svg>
);

export const DocIcon = (p: IconProps) => (
  <Svg {...p}>
    <path d="M6.5 3h7.8L19 7.7v11.1A2.2 2.2 0 0 1 16.8 21H6.5a2.2 2.2 0 0 1-2.2-2.2V5.2A2.2 2.2 0 0 1 6.5 3z" />
    <path d="M14 3.2v3.6c0 .6.4 1 1 1h3.8" />
  </Svg>
);

export const GlobeIcon = (p: IconProps) => (
  <Svg {...p}>
    <circle cx="12" cy="12" r="8.6" />
    <ellipse cx="12" cy="12" rx="3.7" ry="8.6" />
    <path d="M3.6 9.2h16.8M3.6 14.8h16.8" />
  </Svg>
);

const gearPath = (() => {
  const teeth = 8;
  const outer = 9.3;
  const inner = 7.2;
  const points: string[] = [];
  for (let i = 0; i < teeth * 4; i++) {
    const angle = (i / (teeth * 4)) * Math.PI * 2 - Math.PI / 2;
    const radius = i % 4 < 2 ? outer : inner;
    points.push(`${(12 + Math.cos(angle) * radius).toFixed(2)} ${(12 + Math.sin(angle) * radius).toFixed(2)}`);
  }
  return `M${points.join('L')}Z`;
})();

export const GearIcon = (p: IconProps) => (
  <Svg {...p}>
    <path d={gearPath} />
    <circle cx="12" cy="12" r="3" />
  </Svg>
);

export const SidebarRightIcon = (p: IconProps) => (
  <Svg {...p}>
    <rect x="3" y="4.5" width="18" height="15" rx="3" />
    <path d="M14.5 4.8v14.4M16.8 8.4h1.6M16.8 11h1.6M16.8 13.6h1.6" />
  </Svg>
);

export const SidebarLeftIcon = (p: IconProps) => (
  <Svg {...p}>
    <rect x="3" y="4.5" width="18" height="15" rx="3" />
    <path d="M9.5 4.8v14.4M5.6 8.4h1.6M5.6 11h1.6M5.6 13.6h1.6" />
  </Svg>
);

export const SyncIcon = (p: IconProps) => (
  <Svg {...p}>
    <path d="M19.2 9.5A7.6 7.6 0 0 0 5.4 8.1" />
    <path d="M4.8 14.5a7.6 7.6 0 0 0 13.8 1.4" />
    <path d="M19.6 4.8v4.9h-4.9M4.4 19.2v-4.9h4.9" />
  </Svg>
);

export const ChevronRightIcon = (p: IconProps) => (
  <Svg {...p}>
    <path d="M9 5.5l6.5 6.5L9 18.5" />
  </Svg>
);

export const ChevronLeftIcon = (p: IconProps) => (
  <Svg {...p}>
    <path d="M15 5.5L8.5 12l6.5 6.5" />
  </Svg>
);

export const CheckIcon = (p: IconProps) => (
  <Svg {...p}>
    <path d="M5 12.5l4.5 4.5L19 7.5" />
  </Svg>
);

export const CheckCircleFill = ({color = '#34c759', size = 16, style}: IconProps) => (
  <svg width={size} height={size} viewBox="0 0 24 24" style={{display: 'block', flexShrink: 0, ...style}}>
    <circle cx="12" cy="12" r="10" fill={color} />
    <path d="M7.4 12.4l3.1 3.1 6.2-6.6" fill="none" stroke="#fff" strokeWidth={2.2} strokeLinecap="round" strokeLinejoin="round" />
  </svg>
);

export const LockShieldIcon = (p: IconProps) => (
  <Svg {...p}>
    <path d="M12 3l7.2 2.7v5.6c0 4.6-3 8.1-7.2 9.7-4.2-1.6-7.2-5.1-7.2-9.7V5.7z" />
    <rect x="9" y="11" width="6" height="4.8" rx="1" />
    <path d="M10.2 11V9.6a1.8 1.8 0 0 1 3.6 0V11" />
  </Svg>
);

export const ArrowDownDocIcon = (p: IconProps) => (
  <Svg {...p}>
    <path d="M6.5 3h7.8L19 7.7v11.1A2.2 2.2 0 0 1 16.8 21H6.5a2.2 2.2 0 0 1-2.2-2.2V5.2A2.2 2.2 0 0 1 6.5 3z" />
    <path d="M14 3.2v3.6c0 .6.4 1 1 1h3.8" />
    <path d="M11.7 10.5v6M9 14l2.7 2.7 2.7-2.7" />
  </Svg>
);

export const ChecklistIcon = (p: IconProps) => (
  <Svg {...p}>
    <path d="M4 6.5l1.5 1.5 2.8-3M4 13l1.5 1.5 2.8-3M11 7h9M11 13.5h9M11 19h9M4.6 19h2.4" />
  </Svg>
);

export const MagnifierIcon = (p: IconProps) => (
  <Svg {...p}>
    <circle cx="10.5" cy="10.5" r="6.3" />
    <path d="M15.2 15.2L20 20" />
  </Svg>
);

export const CloudDownIcon = (p: IconProps) => (
  <Svg {...p}>
    <path d="M6.8 19h10.6a4.4 4.4 0 0 0 .5-8.8A6.2 6.2 0 0 0 6 11.6 3.7 3.7 0 0 0 6.8 19z" />
    <path d="M12 10.2v5.6M9.6 13.6l2.4 2.4 2.4-2.4" />
  </Svg>
);

export const ClockIcon = (p: IconProps) => (
  <Svg {...p}>
    <circle cx="12" cy="12" r="8.6" />
    <path d="M12 7.2V12l3.2 2" />
  </Svg>
);

export const AppsIcon = (p: IconProps) => (
  <Svg {...p}>
    <path d="M5.2 4.4h5.4L12 7l1.4-2.6h5.4M12 7v12.6M6.8 9.6h3.4M13.8 9.6h3.4" />
    <rect x="3.6" y="3.6" width="16.8" height="16.8" rx="4" />
  </Svg>
);

export const DesktopIcon = (p: IconProps) => (
  <Svg {...p}>
    <rect x="3" y="4.5" width="18" height="12" rx="2" />
    <path d="M9 20h6M12 16.5V20" />
  </Svg>
);

export const DownloadIcon = (p: IconProps) => (
  <Svg {...p}>
    <circle cx="12" cy="12" r="8.6" />
    <path d="M12 7.5v8M8.6 12.6L12 16l3.4-3.4" />
  </Svg>
);

export const AirdropIcon = (p: IconProps) => (
  <Svg {...p}>
    <circle cx="12" cy="12" r="1.6" />
    <path d="M8.4 15.6a5 5 0 1 1 7.2 0M5.6 18.4a9 9 0 1 1 12.8 0" />
  </Svg>
);

export const GridIcon = (p: IconProps) => (
  <Svg {...p}>
    <rect x="4" y="4" width="6.5" height="6.5" rx="1.5" />
    <rect x="13.5" y="4" width="6.5" height="6.5" rx="1.5" />
    <rect x="4" y="13.5" width="6.5" height="6.5" rx="1.5" />
    <rect x="13.5" y="13.5" width="6.5" height="6.5" rx="1.5" />
  </Svg>
);

export const ListIcon = (p: IconProps) => (
  <Svg {...p}>
    <path d="M9 6.5h11M9 12h11M9 17.5h11" />
    <circle cx="4.8" cy="6.5" r=".6" />
    <circle cx="4.8" cy="12" r=".6" />
    <circle cx="4.8" cy="17.5" r=".6" />
  </Svg>
);

export const DatabaseIcon = (p: IconProps) => (
  <Svg {...p}>
    <ellipse cx="12" cy="6" rx="7" ry="2.8" />
    <path d="M5 6v12c0 1.5 3.1 2.8 7 2.8s7-1.3 7-2.8V6M5 12c0 1.5 3.1 2.8 7 2.8s7-1.3 7-2.8" />
  </Svg>
);

export const SparklesIcon = (p: IconProps) => (
  <Svg {...p}>
    <path d="M10 3.5l1.6 4.4L16 9.5l-4.4 1.6L10 15.5l-1.6-4.4L4 9.5l4.4-1.6zM17.5 14l.8 2.2 2.2.8-2.2.8-.8 2.2-.8-2.2-2.2-.8 2.2-.8z" />
  </Svg>
);

export const WrenchIcon = (p: IconProps) => (
  <Svg {...p}>
    <path d="M14.8 4.2a4.6 4.6 0 0 0-5.6 6l-5.5 5.5a1.9 1.9 0 0 0 2.7 2.7l5.5-5.5a4.6 4.6 0 0 0 6-5.6l-2.8 2.8-2.4-.4-.4-2.4z" />
  </Svg>
);

export const BooksIcon = (p: IconProps) => (
  <Svg {...p}>
    <rect x="4" y="4" width="4.2" height="16" rx="1" />
    <rect x="9.6" y="4" width="4.2" height="16" rx="1" />
    <path d="M15.6 5.3l3.9-1 3 15.5-3.9.9z" transform="translate(-1.4 0)" />
  </Svg>
);

export const PersonCheckIcon = (p: IconProps) => (
  <Svg {...p}>
    <circle cx="10" cy="8" r="3.6" />
    <path d="M3.5 19.5c.6-3.4 3.3-5.4 6.5-5.4 1.3 0 2.5.3 3.5.9" />
    <path d="M14.8 17.6l1.8 1.8 3.6-3.8" />
  </Svg>
);

export const AccessibilityIcon = (p: IconProps) => (
  <Svg {...p}>
    <circle cx="12" cy="12" r="9" />
    <circle cx="12" cy="7.6" r="1.1" />
    <path d="M7.5 10.2l4.5.9 4.5-.9M12 11.1v3.4l-2.2 4M12 14.5l2.2 4" />
  </Svg>
);

export const BubbleIcon = (p: IconProps) => (
  <Svg {...p}>
    <path d="M5 5.5h14a1.5 1.5 0 0 1 1.5 1.5v8a1.5 1.5 0 0 1-1.5 1.5h-7.5L7 20v-3.5H5A1.5 1.5 0 0 1 3.5 15V7A1.5 1.5 0 0 1 5 5.5Z" />
    <path d="M8 10h8M8 13h5" />
  </Svg>
);

export const QuoteIcon = (p: IconProps) => (
  <Svg {...p}>
    <path d="M4 6h16M4 10h10M4 14h12M4 18h8" />
    <path d="M18 13.5v5" />
  </Svg>
);

export const TwoPagesIcon = (p: IconProps) => (
  <Svg {...p}>
    <rect x="2.5" y="4.5" width="8.5" height="15" rx="1.5" />
    <rect x="13" y="4.5" width="8.5" height="15" rx="1.5" />
  </Svg>
);

export const StarIcon = (p: IconProps) => (
  <Svg {...p}>
    <path d="m12 3.5 2.6 5.4 5.9.8-4.3 4.1 1 5.8L12 16.8l-5.2 2.8 1-5.8-4.3-4.1 5.9-.8Z" />
  </Svg>
);
