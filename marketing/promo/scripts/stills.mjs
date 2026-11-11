// Renders review stills at the given film times (seconds) into out/stills/.
// Usage: node scripts/stills.mjs 2.5 9.8 14.2 ...
import {bundle} from '@remotion/bundler';
import {renderStill, selectComposition} from '@remotion/renderer';
import {mkdirSync} from 'node:fs';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const times = process.argv.slice(2).map(Number);
mkdirSync(join(root, 'out/stills'), {recursive: true});
const serveUrl = await bundle({entryPoint: join(root, 'src/index.ts')});
const composition = await selectComposition({serveUrl, id: 'Folio10'});
for (const time of times) {
  const frame = Math.round(time * composition.fps);
  const output = join(root, `out/stills/${time.toFixed(2)}.jpg`);
  await renderStill({serveUrl, composition, frame, output, imageFormat: 'jpeg', jpegQuality: 85});
  console.log(output);
}
