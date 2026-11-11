import { readdir, readFile, stat } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';
import { marked } from 'marked';
const root = fileURLToPath(new URL('../dist/', import.meta.url));
const content = fileURLToPath(new URL('../src/content/', import.meta.url));
const files = await readdir(root, { recursive: true });
let checked = 0;
const failures = [];
const decodeText = html => html.replace(/<[^>]*>/g, '').replace(/&(#x[\da-f]+|#\d+|amp|quot|apos|lt|gt);/gi, (_, entity) => {
  if (!entity.startsWith('#')) return { amp: '&', quot: '"', apos: "'", lt: '<', gt: '>' }[entity.toLowerCase()];
  return String.fromCodePoint(entity[1].toLowerCase() === 'x' ? parseInt(entity.slice(2), 16) : Number(entity.slice(1)));
});
let highlightedBlocks = 0;

async function checkLink(raw, source) {
  if (/^(?:[a-z][a-z\d+.-]*:|\/\/)/i.test(raw)) return;
  const url = new URL(raw, `http://localhost/${source.replace(/index\.html$/, '')}`);
  let target = resolve(root, `.${url.pathname}`);
  try {
    if ((await stat(target)).isDirectory()) target = resolve(target, 'index.html');
    await stat(target);
    if (url.hash) {
      const html = await readFile(target, 'utf8');
      if (!html.includes(`id="${decodeURIComponent(url.hash.slice(1))}"`)) {
        failures.push(`${source}: missing anchor ${raw}`);
      }
    }
    checked++;
  } catch { failures.push(`${source}: missing file ${raw}`); }
}

for (const file of files.filter(file => file.endsWith('.html'))) {
  const html = await readFile(resolve(root, file), 'utf8');
  if (!html.includes('<html lang="en">') || !/<title>[^<]*Folio[^<]*<\/title>/.test(html)) {
    failures.push(`${file}: missing Folio document metadata`);
  }
  if ((html.match(/<h1[ >]/g) || []).length !== 1) failures.push(`${file}: expected one primary heading`);
  if (/crono|findle-icon|findle-(theme|sidebar|sound)|Moodle files in Finder/i.test(html)) failures.push(`${file}: contains source product content`);
  const ids = [...html.matchAll(/\bid="([^"]+)"/g)].map(match => match[1]);
  if (ids.length !== new Set(ids).size) failures.push(`${file}: duplicate ID`);
  for (const [, raw] of html.matchAll(/(?:href|src|poster)="([^"]+)"/g)) await checkLink(raw, file);
  for (const [image] of html.matchAll(/<img\b[^>]*>/g)) {
    if (!/\balt="[^"]*"/.test(image)) failures.push(`${file}: image without alternative text`);
  }
  if (file !== '404.html') {
    if (!/<meta name="description" content="[^"]+"/.test(html)) failures.push(`${file}: missing description`);
    if (!html.includes('href="#content"')) failures.push(`${file}: missing skip link`);
  }
}

const search = JSON.parse(await readFile(resolve(root, 'search.json'), 'utf8'));
const indexedURLs = new Set();
for (const entry of search) {
  if (!entry.title || !entry.section || !entry.text || !entry.url) {
    failures.push('Search entry is missing content');
    continue;
  }
  if (indexedURLs.has(entry.url)) failures.push(`Duplicate search destination: ${entry.url}`);
  indexedURLs.add(entry.url);
  await checkLink(entry.url, 'search.json');
}

const guides = (await readdir(content)).filter(file => file.endsWith('.md'));
for (const guide of guides) {
  const slug = guide.slice(0, -3);
  const route = slug === 'overview' ? '/' : `/${slug}/`;
  if (!indexedURLs.has(route)) failures.push(`${guide}: page missing from search`);
  const source = resolve(content, guide);
  const markdown = await readFile(source, 'utf8');
  const codeBlocks = [];
  marked.walkTokens(marked.lexer(markdown), token => { if (token.type === 'code') codeBlocks.push(token.text + '\n'); });
  const html = await readFile(resolve(root, slug === 'overview' ? 'index.html' : `${slug}/index.html`), 'utf8');
  const renderedCode = [...html.matchAll(/<pre><code\b[^>]*>([\s\S]*?)<\/code><\/pre>/g)].map(([, code]) => {
    if (code.includes('class="hljs-')) highlightedBlocks++;
    return decodeText(code);
  });
  if (JSON.stringify(codeBlocks) !== JSON.stringify(renderedCode)) failures.push(`${guide}: rendered code differs from source and would copy incorrectly`);
  const endpoints = slug === 'overview' ? ['overview.md', 'index.md', '.md'] : [guide, `${slug}/.md`];
  for (const endpoint of endpoints) {
    try {
      if (await readFile(resolve(root, endpoint), 'utf8') !== markdown) {
        failures.push(`${endpoint}: Markdown differs from source`);
      }
    } catch { failures.push(`${endpoint}: missing Markdown endpoint`); }
  }
}
const llms = await readFile(resolve(root, 'llms.txt'), 'utf8');
for (const guide of guides) {
  if (!llms.includes(`(/${guide})`)) failures.push(`${guide}: missing from llms.txt`);
}
const app = await readFile(resolve(root, 'app.js'), 'utf8');
if (/crono|findle/i.test(app)) failures.push('Browser script retains another product\'s branding or preferences');
if (!highlightedBlocks) failures.push('No syntax highlighting found in generated code examples');

if (failures.length) { console.error(failures.join('\n')); process.exit(1); }
console.log(`Verified ${guides.length} guides, ${checked} internal links and assets, document metadata, unique IDs, Markdown endpoints, ${search.length} search entries, and code-copy fidelity (${highlightedBlocks} highlighted blocks).`);
