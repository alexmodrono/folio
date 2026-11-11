import { createServer } from 'node:http';
import { open, readFile, stat } from 'node:fs/promises';
import { watch } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { networkInterfaces } from 'node:os';
import { pipeline } from 'node:stream/promises';
import { fileURLToPath } from 'node:url';
import { resolve, extname, sep } from 'node:path';
const root = fileURLToPath(new URL('../', import.meta.url));
const dist = resolve(root, 'dist');
const build = () => spawnSync(process.execPath, ['scripts/build.mjs'], { cwd: root, stdio: 'inherit' });
if (build().status !== 0) process.exit(1);
let timer;
const rebuild = () => { clearTimeout(timer); timer = setTimeout(build, 100); };
for (const folder of ['src', 'public', 'scripts']) watch(resolve(root, folder), { recursive: true }, rebuild);
const types = {
  '.html': 'text/html', '.css': 'text/css', '.js': 'text/javascript', '.json': 'application/json',
  '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.svg': 'image/svg+xml',
  '.webp': 'image/webp', '.avif': 'image/avif', '.ttf': 'font/ttf', '.woff2': 'font/woff2',
  '.md': 'text/plain', '.txt': 'text/plain', '.vtt': 'text/vtt',
  '.mp4': 'video/mp4', '.m4v': 'video/mp4', '.webm': 'video/webm', '.mov': 'video/quicktime',
};

function byteRange(value, size) {
  const match = typeof value === 'string' && /^bytes=(\d*)-(\d*)$/.exec(value.trim());
  // Unsupported units, malformed headers, and multipart ranges fall back to a full response.
  if (!match || (!match[1] && !match[2])) return null;
  if (!size) return false;
  const start = match[1] ? Number(match[1]) : Math.max(0, size - Number(match[2]));
  const end = match[1] && match[2] ? Math.min(Number(match[2]), size - 1) : size - 1;
  if (start >= size || end < start) return false;
  return { start, end };
}

const server = createServer(async (req, res) => {
  if (req.method !== 'GET' && req.method !== 'HEAD') {
    res.writeHead(405, { Allow: 'GET, HEAD', 'Content-Length': 0 });
    return res.end();
  }
  let handle;
  try {
    const pathname = decodeURIComponent(new URL(req.url, 'http://localhost').pathname);
    let file = resolve(dist, `.${pathname}`);
    if (file !== dist && !file.startsWith(dist + sep)) { res.writeHead(403); return res.end(); }
    if ((await stat(file)).isDirectory()) file = resolve(file, 'index.html');
    handle = await open(file);
    const info = await handle.stat();
    if (!info.isFile()) throw new Error('Not a regular file');
    const type = types[extname(file).toLowerCase()] || (file.endsWith('/.md') || file.endsWith('/LICENSE') ? 'text/plain' : 'application/octet-stream');
    const contentType = type.startsWith('text/') || type === 'application/json' || type === 'image/svg+xml' ? `${type}; charset=utf-8` : type;
    const headers = { 'Content-Type': contentType, 'Cache-Control': 'no-store', 'Accept-Ranges': 'bytes' };
    const range = req.method === 'GET' ? byteRange(req.headers.range, info.size) : null;
    if (range === false) {
      res.writeHead(416, { ...headers, 'Content-Range': `bytes */${info.size}`, 'Content-Length': 0 });
      return res.end();
    }
    headers['Content-Length'] = range ? range.end - range.start + 1 : info.size;
    if (range) headers['Content-Range'] = `bytes ${range.start}-${range.end}/${info.size}`;
    res.writeHead(range ? 206 : 200, headers);
    if (req.method === 'HEAD' || !info.size) return res.end();
    await pipeline(handle.createReadStream({ autoClose: false, ...(range || {}) }), res);
  } catch {
    if (res.headersSent || res.destroyed) return res.destroy();
    const page = await readFile(resolve(dist, '404.html')).catch(() => Buffer.from('Page not found'));
    res.writeHead(404, { 'Content-Type': 'text/html; charset=utf-8', 'Content-Length': page.length });
    res.end(req.method === 'HEAD' ? undefined : page);
  } finally {
    await handle?.close();
  }
});
const host = process.env.HOST || '127.0.0.1';
server.listen(Number(process.env.PORT || 4320), host, () => {
  const port = server.address().port;
  console.log(`Local: http://127.0.0.1:${port}`);
  if (host === '0.0.0.0') {
    for (const addr of Object.values(networkInterfaces()).flat()) {
      if (addr && addr.family === 'IPv4' && !addr.internal) console.log(`Network: http://${addr.address}:${port}`);
    }
  }
});
