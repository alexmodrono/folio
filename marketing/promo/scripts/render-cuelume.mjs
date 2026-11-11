// Renders the Cuelume cues in src/timeline.ts into a sample-accurate stereo
// stem using Cuelume's own engine. By default it renders every regular cue into
// public/audio/cuelume.wav; with --accents it renders the cues marked `accent`
// into public/audio/cuelume-accents.wav, 6 dB hotter, because Cuelume clamps
// its own per-cue volume to 1.
//
// Cuelume plays through a shared, real-time AudioContext. Here that context is
// an OfflineAudioContext (node-web-audio-api) seen through a proxy whose clock
// reads each cue's film time, so `play()` schedules the cue exactly where the
// film needs it. Everything is scheduled first, then rendered in one pass.
import {writeFileSync} from 'node:fs';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {OfflineAudioContext} from 'node-web-audio-api';
import {CUELUME_CUES, DURATION} from '../src/timeline.ts';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const sampleRate = 48000;
const accents = process.argv.includes('--accents');
// Cuelume is voiced for quiet interfaces; lift the stem so cues read over music.
const STEM_GAIN = Math.pow(10, (accents ? 18 : 12) / 20);
const context = new OfflineAudioContext({numberOfChannels: 2, length: sampleRate * DURATION, sampleRate});

let filmTime = 0;
const clock = new Proxy(context, {
  get(target, property) {
    if (property === 'currentTime') return filmTime;
    if (property === 'state') return 'running';
    const value = Reflect.get(target, property, target);
    return typeof value === 'function' ? value.bind(target) : value;
  },
});

globalThis.window = globalThis;
globalThis.AudioContext = function AudioContext() {
  return clock;
};
// Cuelume's cadence logic reads performance.now(); give it film time too.
Object.defineProperty(globalThis.performance, 'now', {value: () => filmTime * 1000, configurable: true});
// Cuelume disconnects finished voices on a wall-clock timer. Offline, that
// timer would fire before rendering, so cleanup is skipped while scheduling.
const realSetTimeout = globalThis.setTimeout;
globalThis.setTimeout = () => 0;

const {play} = await import('cuelume');
const cues = CUELUME_CUES.filter((cue) => Boolean(cue.accent) === accents).sort((a, b) => a.t - b.t);
for (const {t, sound, accent, ...options} of cues) {
  filmTime = t;
  play(sound, options);
}
globalThis.setTimeout = realSetTimeout;

const buffer = await context.startRendering();
const channels = [buffer.getChannelData(0), buffer.getChannelData(1)];
const frames = buffer.length;
const wav = Buffer.alloc(44 + frames * 4);
wav.write('RIFF', 0);
wav.writeUInt32LE(36 + frames * 4, 4);
wav.write('WAVEfmt ', 8);
wav.writeUInt32LE(16, 16);
wav.writeUInt16LE(1, 20);
wav.writeUInt16LE(2, 22);
wav.writeUInt32LE(sampleRate, 24);
wav.writeUInt32LE(sampleRate * 4, 28);
wav.writeUInt16LE(4, 32);
wav.writeUInt16LE(16, 34);
wav.write('data', 36);
wav.writeUInt32LE(frames * 4, 40);
for (let i = 0; i < frames; i++) {
  for (let c = 0; c < 2; c++) {
    const sample = Math.max(-1, Math.min(1, channels[c][i] * STEM_GAIN));
    wav.writeInt16LE(Math.round(sample * 32767), 44 + i * 4 + c * 2);
  }
}
const file = join(root, accents ? 'public/audio/cuelume-accents.wav' : 'public/audio/cuelume.wav');
writeFileSync(file, wav);
console.log(`rendered ${cues.length} Cuelume cues into ${file}`);
