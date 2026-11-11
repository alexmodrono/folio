// Renders the promotional screenshots in src/Screens.tsx, every shot in both
// formats, as PNGs into out/screenshots/ (16:9 at 2560 × 1440, 4:5 at 1620 × 2025).
import {bundle} from '@remotion/bundler';
import {renderStill, selectComposition} from '@remotion/renderer';
import {mkdirSync} from 'node:fs';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {FORMATS, SHOTS} from '../src/shots.ts';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const out = join(root, 'out/screenshots');
mkdirSync(out, {recursive: true});
const serveUrl = await bundle({entryPoint: join(root, 'src/index.ts')});
for (const format of Object.keys(FORMATS)) {
  for (const shot of SHOTS) {
    const inputProps = {shot: shot.id, format};
    const composition = await selectComposition({serveUrl, id: `Screen-${format}`, inputProps});
    const output = join(out, `folio-${shot.id}-${format}.png`);
    await renderStill({serveUrl, composition, inputProps, frame: 0, output, imageFormat: 'png', scale: FORMATS[format].scale});
    console.log(output);
  }
}
