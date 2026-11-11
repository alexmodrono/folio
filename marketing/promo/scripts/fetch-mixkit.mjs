// Downloads the Mixkit sound effects and music listed in src/audio/mixkit.ts,
// then builds the edited music bed with FFmpeg.
// Mixkit's free licenses allow use in this film but not redistribution of the
// raw files, so they live in a gitignored folder and are fetched on demand.
import {execFileSync} from 'node:child_process';
import {existsSync, mkdirSync, writeFileSync} from 'node:fs';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {MIXKIT_SFX, MUSIC} from '../src/audio/mixkit.ts';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const folder = join(root, 'public/audio/mixkit');
mkdirSync(folder, {recursive: true});

async function download(url, file) {
  if (existsSync(file)) return;
  const response = await fetch(url, {headers: {'User-Agent': 'Mozilla/5.0'}});
  if (!response.ok) throw new Error(`${url}: HTTP ${response.status}`);
  writeFileSync(file, Buffer.from(await response.arrayBuffer()));
  console.log(`fetched ${url}`);
}

const source = join(folder, `music-${MUSIC.id}.mp3`);
await Promise.all([
  ...Object.keys(MIXKIT_SFX).map((id) =>
    download(`https://assets.mixkit.co/active_storage/sfx/${id}/${id}.wav`, join(folder, `${id}.wav`)),
  ),
  download(`https://assets.mixkit.co/music/${MUSIC.id}/${MUSIC.id}.mp3`, source),
]);

// Each segment is padded by half a crossfade on every joined side, so after the
// equal-power crossfades the bed is exactly the sum of the segment lengths and
// every edit is centred on its downbeat.
const half = MUSIC.crossfade / 2;
const last = MUSIC.segments.length - 1;
const trims = MUSIC.segments.map(([from, to], i) => {
  const start = i === 0 ? from : from - half;
  const end = i === last ? to : to + half;
  return `[0]atrim=${start}:${end},asetpts=PTS-STARTPTS[s${i}]`;
});
let chain = '[s0]';
const fades = [];
for (let i = 1; i <= last; i++) {
  const output = i === last ? '[joined]' : `[j${i}]`;
  fades.push(`${chain}[s${i}]acrossfade=d=${MUSIC.crossfade}:c1=qsin:c2=qsin${output}`);
  chain = output;
}
if (last === 0) fades.push('[s0]anull[joined]');
const bed = join(root, 'public/audio/music-bed.wav');
execFileSync('ffmpeg', [
  '-v', 'error', '-y', '-i', source,
  '-filter_complex', [...trims, ...fades, '[joined]afade=t=in:d=0.01,aresample=48000'].join(';'),
  '-ac', '2', '-c:a', 'pcm_s16le', bed,
]);
console.log(`wrote ${bed}`);
