// Renders the promotional banners in src/Banner.tsx as PNGs into out/banners/.
import {bundle} from '@remotion/bundler';
import {renderStill, selectComposition} from '@remotion/renderer';
import {mkdirSync} from 'node:fs';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {BANNERS} from '../src/banners.ts';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const out = join(root, 'out/banners');
mkdirSync(out, {recursive: true});
const serveUrl = await bundle({entryPoint: join(root, 'src/index.ts')});
const only = process.argv.slice(2);
for (const [format, layout] of Object.entries(BANNERS)) {
  if (only.length && !only.includes(format)) continue;
  const inputProps = {format};
  const composition = await selectComposition({serveUrl, id: `Banner-${format}`, inputProps});
  const output = join(out, `folio-banner-${format}.png`);
  await renderStill({serveUrl, composition, inputProps, frame: 0, output, imageFormat: 'png', scale: layout.scale});
  console.log(output);
}
