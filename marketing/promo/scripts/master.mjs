// Masters the film's audio to about -14 LUFS integrated with peaks held under
// -1 dBTP after AAC encoding, then remuxes it with the untouched video stream.
// A measured gain stage plus a -2 dBFS limiter keeps the mix's dynamics intact
// (loudnorm's dynamic mode would pump the music under the cues).
// Usage: node scripts/master.mjs <rendered.mp4> <output.mp4> [audio-source]
import {execFileSync, spawnSync} from 'node:child_process';

const TARGET_LUFS = -14;
const LIMIT_DB = -2;
const [input, output, audioSource = input] = process.argv.slice(2);

const measure = (file) => {
  const {stderr} = spawnSync('ffmpeg', ['-hide_banner', '-i', file, '-af', 'ebur128=peak=true', '-f', 'null', '-'], {encoding: 'utf8'});
  const summary = stderr.slice(stderr.lastIndexOf('Summary:'));
  return {
    lufs: Number(summary.match(/I:\s+(-?[\d.]+) LUFS/)[1]),
    peak: Number(summary.match(/Peak:\s+(-?[\d.]+) dBFS/)[1]),
  };
};

const before = measure(audioSource);
// The limiter shaves a little loudness off the hits; aim slightly high to land on target.
const gain = TARGET_LUFS - before.lufs + 0.4;
execFileSync('ffmpeg', [
  '-v', 'error', '-y', '-i', input, '-i', audioSource,
  '-map', '0:v', '-map', '1:a',
  '-af', `volume=${gain.toFixed(2)}dB,alimiter=limit=${Math.pow(10, LIMIT_DB / 20).toFixed(4)}:attack=2:release=60:level=false,aresample=48000`,
  '-c:v', 'copy', '-c:a', 'aac', '-b:a', '320k', '-movflags', '+faststart', output,
]);
const after = measure(output);
console.log(`mastered ${output}: ${before.lufs} → ${after.lufs} LUFS, true peak ${after.peak} dBFS`);
