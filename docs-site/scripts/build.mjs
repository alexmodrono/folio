import { mkdir, readFile, writeFile, cp, rm, stat, open } from 'node:fs/promises';
import { setTimeout as delay } from 'node:timers/promises';
import { fileURLToPath } from 'node:url';
import { marked } from 'marked';
import hljs from 'highlight.js';

const root = fileURLToPath(new URL('../', import.meta.url));
const dist = `${root}dist`;
const groups = [
  ['Getting started', [['overview', 'Overview'], ['quickstart', 'Quickstart'], ['sign-in', 'Sign in to ChatGPT']]],
  ['Using Folio', [['library', 'Your library'], ['reading', 'Reading PDFs'], ['asking', 'Ask about a passage'], ['chats', 'Chats and attachments'], ['questions', 'Question bubbles']]],
  ['Reference', [['moodle', 'Moodle courses'], ['settings', 'Settings & shortcuts'], ['privacy', 'Privacy'], ['troubleshooting', 'Troubleshooting'], ['building', 'Build from source']]],
];
const pages = groups.flatMap(([group, items]) => items.map(([slug, label]) => ({ slug, label, group })));
const href = slug => slug === 'overview' ? '/' : `/${slug}/`;
const escape = value => value.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');
const entities = { amp: '&', quot: '"', apos: "'", lt: '<', gt: '>' };
const plain = value => value.replace(/<[^>]+>/g, '').replace(/\[([^\]]+)\]\([^)]+\)/g, '$1')
  .replace(/&(#x[\da-f]+|#\d+|amp|quot|apos|lt|gt);/gi, (_, entity) => {
    if (!entity.startsWith('#')) return entities[entity.toLowerCase()];
    return String.fromCodePoint(entity[1].toLowerCase() === 'x' ? parseInt(entity.slice(2), 16) : Number(entity.slice(1)));
  }).replace(/[*`#]/g, '');
const slugify = value => plain(value).toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
const icons = {
  github: '<path d="M12 2a10 10 0 0 0-3.16 19.49c.5.09.68-.22.68-.48v-1.86c-2.78.6-3.37-1.18-3.37-1.18-.46-1.16-1.11-1.47-1.11-1.47-.91-.62.07-.61.07-.61 1 .07 1.53 1.03 1.53 1.03.89 1.52 2.34 1.08 2.91.83.09-.65.35-1.08.64-1.33-2.22-.25-4.56-1.11-4.56-4.94 0-1.09.39-1.99 1.03-2.69-.1-.25-.45-1.27.1-2.65 0 0 .84-.27 2.75 1.03A9.6 9.6 0 0 1 12 6.82a9.6 9.6 0 0 1 2.5.34c1.91-1.3 2.75-1.03 2.75-1.03.55 1.38.2 2.4.1 2.65.64.7 1.03 1.6 1.03 2.69 0 3.84-2.34 4.69-4.57 4.94.36.31.68.92.68 1.85v2.75c0 .27.18.58.69.48A10 10 0 0 0 12 2Z" fill="currentColor" stroke="none"/>',
  search: '<circle cx="10.5" cy="10.5" r="6.5"/><path d="m16 16 4 4"/>',
  panel: '<rect x="3" y="4" width="18" height="16" rx="2"/><path d="M9 4v16m7-11-3 3 3 3"/>',
  sun: '<circle cx="12" cy="12" r="4"/><path d="M12 2v2m0 16v2M2 12h2m16 0h2M5 5l1.5 1.5m11 11L19 19M5 19l1.5-1.5m11-11L19 5"/>',
  menu: '<path d="M4 6h16M4 12h16M4 18h16"/>',
  close: '<path d="m6 6 12 12M6 18 18 6"/>',
  sound: '<path d="M4 9.5h3.5L12 5.5v13l-4.5-4H4z"/><path class="sound-on" d="M15.5 9a4 4 0 0 1 0 6m2.5-8.5a7.5 7.5 0 0 1 0 11"/><path class="sound-off" d="m16 9.5 5 5m0-5-5 5"/>',
  copy: '<rect x="8" y="8" width="12" height="13" rx="2"/><path d="M16 8V5a2 2 0 0 0-2-2H5a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h3"/>',
};
const icon = name => `<svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${icons[name]}</svg>`;
const repo = 'https://github.com/alexmodrono/folio';
const navigation = current => groups.map(([group, items]) => `<div class="nav-group"><h2>${group}</h2>${items.map(([slug, label]) => `<a data-cuelume-navigate href="${href(slug)}"${slug === current ? ' aria-current="page"' : ''}>${escape(label)}</a>`).join('')}</div>`).join('');
const themeControl = `<label class="theme-control"><span class="sr-only">Color theme</span><select aria-label="Color theme" data-cuelume-select><option value="system">System</option><option value="light">Light</option><option value="dark">Dark</option></select></label>`;
const soundControl = `<button class="sound-toggle icon-button" aria-label="Interface sounds" aria-pressed="true">${icon('sound')}</button>`;
const appleLogo = '<svg viewBox="0 0 24 24" width="22" height="22" aria-hidden="true"><path fill="currentColor" d="M12.15 6.9c-.95 0-2.42-1.08-3.96-1.04-2.04.03-3.91 1.18-4.96 3.01-2.12 3.68-.55 9.1 1.52 12.09 1.01 1.45 2.2 3.09 3.79 3.04 1.52-.07 2.09-.99 3.94-.99 1.83 0 2.35.99 3.96.95 1.64-.03 2.68-1.48 3.68-2.95 1.15-1.69 1.63-3.33 1.66-3.42-.04-.01-3.18-1.22-3.22-4.85-.03-3.04 2.48-4.5 2.6-4.56-1.43-2.09-3.63-2.33-4.4-2.38-2-.16-3.67 1.09-4.6 1.09zm3.38-3.07c.84-1.01 1.4-2.43 1.25-3.83-1.21.05-2.67.8-3.54 1.82-.78.9-1.45 2.34-1.27 3.71 1.34.1 2.71-.69 3.56-1.7"/></svg>';
const guideIcon = '<svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4 5.5A2.5 2.5 0 0 1 6.5 3H20v15H6.5A2.5 2.5 0 0 0 4 20.5z"/><path d="M4 20.5A2.5 2.5 0 0 0 6.5 23H20v-5M8 7.5h8M8 11h5"/></svg>';
const heroActions = `<div class="hero-actions"><a class="store-button dark" href="${repo}/releases/latest" data-cuelume-tap>${appleLogo}<span><small>Download · Free</small><strong>macOS</strong></span></a><a class="store-button light" href="/quickstart/" data-cuelume-navigate>${guideIcon}<span><small>Read the guide</small><strong>Get started</strong></span></a></div>`;
// Behind the homepage hero (full width, under the glass header and sidebars): a painted mountain valley,
// faded out at the bottom by a CSS mask.
const heroBackdrop = `<div class="hero-backdrop" aria-hidden="true"><img src="/images/hero/valley.webp" width="1308" height="736" alt="" fetchpriority="high"></div>`;
const hero = `<section class="hero"><img class="hero-icon" src="/images/folio-icon.png" width="220" height="220" alt="" fetchpriority="high"><div class="hero-copy"><h1>Read a PDF. Ask about it.</h1><p class="hero-lead">Folio is a small PDF reader for Mac with ChatGPT beside the page. Select a passage, ask about it with the page number attached, and keep reading.</p>${heroActions}<p class="hero-note">For macOS 26 and later. Uses your own ChatGPT account. Not affiliated with OpenAI.</p></div></section>`;
// The homepage turns each guide section into a landing-page block: sections with a
// screenshot become alternating feature rows, the last one a closing call to action.
function landing(html) {
  const [intro, ...sections] = html.split(/(?=<h2 id=)/);
  let features = 0;
  return intro + sections.map((section, index) => {
    const image = section.match(/<p>(<img\b[^>]*>)<\/p>/);
    if (image) {
      const shot = image[1].replace('<img ', '<img loading="lazy" decoding="async" width="2000" height="1250" ');
      return `<section class="feature${features++ % 2 ? ' flip' : ''}"><div class="feature-copy">${section.replace(image[0], '')}</div><figure class="feature-shot">${shot}</figure></section>`;
    }
    if (index === sections.length - 1) return `<section class="closing"><img class="closing-icon" src="/images/folio-icon.png" width="112" height="112" alt="" loading="lazy">${section}${heroActions}</section>`;
    return `<section class="details">${section}</section>`;
  }).join('');
}
const siteFooter = `<footer class="site-footer"><div class="site-footer-brand"><img src="/images/folio-icon-small.png" width="32" height="32" alt=""><p>Folio, a PDF reader for Mac.<br>Not affiliated with OpenAI.</p></div>${groups.map(([group, items]) => `<nav aria-label="${group}"><p class="footer-heading">${group}</p>${items.map(([slug, label]) => `<a href="${href(slug)}">${escape(label)}</a>`).join('')}</nav>`).join('')}</footer>`;

const renderer = new marked.Renderer();
renderer.code = ({ text, lang }) => {
  const language = (lang || 'text').trim().split(/\s+/)[0].toLowerCase();
  const supported = Boolean(hljs.getLanguage(language));
  const code = supported ? hljs.highlight(text, { language, ignoreIllegals: true }).value : escape(text);
  const languageClass = supported ? ` language-${escape(language)}` : '';
  return `<div class="code-block"><div class="code-header"><span>${escape(language)}</span><button class="copy-code" aria-label="Copy code"><span>Copy</span></button></div><pre><code class="hljs${languageClass}">${code}\n</code></pre></div>\n`;
};

async function hasFile(path) {
  try { return (await stat(`${root}public${path}`)).isFile(); }
  catch (error) { if (error.code === 'ENOENT') return false; throw error; }
}
const videoSources = [];
for (const [extension, type] of [['mp4', 'video/mp4'], ['webm', 'video/webm']]) {
  const path = `/videos/folio-demo.${extension}`;
  if (await hasFile(path)) videoSources.push({ path, type });
}
let videoPoster = null;
for (const extension of ['jpg', 'png', 'webp']) {
  const path = `/videos/folio-demo-poster.${extension}`;
  if (await hasFile(path)) { videoPoster = path; break; }
}
const captions = '/videos/folio-demo.en.vtt';
const captionTrack = await hasFile(captions) ? `<track kind="captions" src="${captions}" srclang="en" label="English" default>` : '';
const demoVideo = videoSources.length ? `<figure class="showcase"><video controls playsinline preload="metadata"${videoPoster ? ` poster="${videoPoster}"` : ''} aria-label="Folio demo">${videoSources.map(({ path, type }) => `<source src="${path}" type="${type}">`).join('')}${captionTrack}<a href="${videoSources[0].path}">Download the Folio demo</a></video></figure>` : null;

// A manual build and the development watcher can run at the same time.
// Serialize their writes so one cannot remove the other's output directory.
const lockPath = `${root}.build.lock`;
const deadline = Date.now() + 15000;
let lock;
while (!lock) {
  try {
    lock = await open(lockPath, 'wx');
    await lock.writeFile(String(process.pid));
  } catch (error) {
    if (error.code !== 'EEXIST') throw error;
    try {
      const pid = Number(await readFile(lockPath, 'utf8'));
      if (Number.isInteger(pid) && pid > 0) process.kill(pid, 0);
    } catch (ownerError) {
      if (ownerError.code === 'ESRCH') { await rm(lockPath, { force: true }); continue; }
      if (ownerError.code === 'ENOENT') continue;
    }
    if (Date.now() >= deadline) throw new Error('Another website build is still running. Retry after it finishes.');
    await delay(100);
  }
}
try {
await rm(dist, { recursive: true, force: true });
await mkdir(dist, { recursive: true });
await cp(`${root}public`, dist, { recursive: true });
await cp(`${root}src/styles.css`, `${dist}/styles.css`);
await cp(`${root}src/syntax.css`, `${dist}/syntax.css`);
await cp(`${root}src/app.js`, `${dist}/app.js`);
await mkdir(`${dist}/vendor`, { recursive: true });
await cp(`${root}node_modules/highlight.js/LICENSE`, `${dist}/vendor/LICENSE.highlightjs`);
await cp(`${root}node_modules/cuelume/dist`, `${dist}/vendor/cuelume`, { recursive: true, filter: source => !source.endsWith('.d.ts') });
await cp(`${root}node_modules/cuelume/LICENSE`, `${dist}/vendor/LICENSE.cuelume`);
const search = [];
for (const [index, page] of pages.entries()) {
  const markdown = await readFile(`${root}src/content/${page.slug}.md`, 'utf8');
  const outline = [];
  let html = marked.parse(markdown, { gfm: true, renderer });
  const title = plain(html.match(/<h1\b[^>]*>([\s\S]*?)<\/h1>/i)?.[1] || page.label).trim();
  const description = page.slug === 'overview' ? 'A small native PDF reader for Mac with ChatGPT in a side panel. Select a passage, ask about it with its page number, and keep reading.' : [...html.matchAll(/<p\b[^>]*>([\s\S]*?)<\/p>/gi)].map(([, paragraph]) => plain(paragraph).trim()).find(Boolean) || title;
  if (page.slug === 'overview') {
    html = html.replace(/<h1\b[^>]*>[\s\S]*?<\/h1>/, hero);
    if (demoVideo) html = html.replace('<!-- folio-demo -->', demoVideo);
  }
  const isLanding = page.slug === 'overview';
  html = html.replace(/<h2>(.*?)<\/h2>/g, (_, heading) => {
    const id = slugify(heading);
    outline.push({ id, title: plain(heading) });
    return `<h2 id="${id}">${heading}<a class="heading-anchor" href="#${id}" aria-label="Link to ${escape(plain(heading))}">#</a></h2>`;
  });
  if (isLanding) html = landing(html);
  html = html.replace(/<table>/g, '<div class="table-scroll" role="region" aria-label="Reference table" tabindex="0"><table>').replace(/<\/table>/g, '</table></div>');
  const chunks = markdown.split(/^## /m);
  search.push({ title: page.label, section: 'Overview', url: href(page.slug), text: plain(chunks[0]) });
  for (const chunk of chunks.slice(1)) {
    const heading = chunk.split('\n')[0];
    search.push({ title: page.label, section: heading, url: `${href(page.slug)}#${slugify(heading)}`, text: plain(chunk) });
  }
  const prev = pages[index - 1], next = pages[index + 1];
  const document = `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><meta name="color-scheme" content="light dark"><title>${escape(page.slug === 'overview' ? 'Folio | A PDF reader with ChatGPT beside the page' : `${title} | Folio`)}</title><meta name="description" content="${escape(description)}"><meta property="og:title" content="${escape(title)}"><meta property="og:description" content="${escape(description)}"><meta property="og:type" content="website"><meta property="og:image" content="/images/folio-icon.png"><link rel="icon" href="/images/folio-icon-small.png"><link rel="preload" href="/fonts/Geist-VariableFont_wght.ttf" as="font" type="font/ttf" crossorigin><script>try{var t=localStorage.getItem('folio-theme')||'system';document.documentElement.dataset.theme=t==='system'?(matchMedia('(prefers-color-scheme: dark)').matches?'dark':'light'):t;if(localStorage.getItem('folio-sidebar')==='collapsed')document.documentElement.dataset.sidebar='collapsed'}catch(e){}</script><link rel="stylesheet" href="/styles.css"><link rel="stylesheet" href="/syntax.css"><script type="module" src="/app.js"></script></head>
<body data-page="${page.slug}"${isLanding ? ' class="landing"' : ''}><a class="skip-link" href="#content">Skip to content</a>${isLanding ? heroBackdrop : ''}
<header class="header"><a class="brand" href="/" aria-label="Folio home"><img src="/images/folio-icon-small.png" width="26" height="26" alt=""><span><span class="brand-owner">alexmodrono</span><span class="brand-sep">/</span>Folio</span></a><div class="header-actions">${isLanding ? `<nav class="header-nav" aria-label="Site"><a href="/quickstart/">Guide</a><a href="${repo}/releases">Releases</a></nav>` : ''}<button class="search-trigger" data-cuelume-open data-cuelume-emphasis="subtle" aria-label="Search documentation">${icon('search')}<span>Search documentation…</span><kbd>⌘ K</kbd></button><a class="github-link" href="${repo}" target="_blank" rel="noreferrer" aria-label="Folio on GitHub">${icon('github')}</a><button class="menu-trigger icon-button" data-cuelume-open aria-label="Open navigation" aria-haspopup="dialog">${icon('menu')}</button></div></header>
<aside class="sidebar" aria-label="Documentation"><nav aria-label="Documentation pages">${navigation(page.slug)}</nav><div class="sidebar-footer">${themeControl}${soundControl}<button class="collapse-sidebar icon-button" data-cuelume-toggle aria-label="Collapse sidebar" aria-expanded="true">${icon('panel')}</button></div></aside>
<main id="content" tabindex="-1"><article>${page.slug !== 'overview' ? `<div class="article-toolbar"><div class="breadcrumb">${page.group}<span>›</span>${escape(page.label)}</div><button class="copy-page"><span>Copy page</span></button></div>` : ''}${html}${isLanding ? siteFooter : `<nav class="pagination" aria-label="Previous and next pages">${prev ? `<a href="${href(prev.slug)}"><span>Previous</span>← ${escape(prev.label)}</a>` : '<div></div>'}${next ? `<a href="${href(next.slug)}" class="next" data-cuelume-navigate><span>Next</span>${escape(next.label)} →</a>` : '<div></div>'}</nav><footer class="article-footer"><span>Folio. Not affiliated with OpenAI.</span><a href="${repo}/releases">Releases ↗</a></footer>`}</article></main>
<aside class="toc"><nav aria-label="On this page"><h2>On this page</h2>${outline.map(({ id, title }) => `<a href="#${id}" data-cuelume-navigate data-cuelume-emphasis="subtle">${escape(title)}</a>`).join('')}</nav><div class="toc-footer"><a href="${repo}/issues" target="_blank" rel="noreferrer">Report an issue ↗</a><a href="/${page.slug}.md">View as Markdown ↗</a></div></aside>
<dialog class="mobile-nav" aria-label="Documentation navigation"><div class="mobile-nav-top"><span>Documentation</span><button class="close-mobile icon-button" data-cuelume-close aria-label="Close navigation">${icon('close')}</button></div><nav>${navigation(page.slug)}</nav><div class="mobile-theme">${themeControl}${soundControl}</div></dialog>
<dialog class="search-dialog" aria-label="Search documentation"><form method="dialog" class="search-form">${icon('search')}<label class="sr-only" for="search-input">Search documentation</label><input id="search-input" type="search" data-cuelume-type data-cuelume-emphasis="subtle" autocomplete="off" placeholder="Search documentation…"><button class="icon-button" data-cuelume-close data-cuelume-emphasis="subtle" aria-label="Close search">${icon('close')}</button></form><div class="search-results" aria-label="Search results"></div><div class="search-footer"><span id="search-status" role="status">Type to search Folio’s documentation</span><span><kbd>↑</kbd><kbd>↓</kbd> navigate <kbd>esc</kbd> close</span></div></dialog><div class="toast" role="status" aria-live="polite"></div>
</body></html>`;
  const target = page.slug === 'overview' ? dist : `${dist}/${page.slug}`;
  await mkdir(target, { recursive: true });
  await writeFile(`${target}/index.html`, document);
  await writeFile(`${dist}/${page.slug}.md`, markdown);
  // Both /page.md and /page/.md work, so the displayed URL can be appended literally.
  await writeFile(`${target}/.md`, markdown);
}
await writeFile(`${dist}/index.md`, await readFile(`${root}src/content/overview.md`));
await writeFile(`${dist}/search.json`, JSON.stringify(search));
await writeFile(`${dist}/llms.txt`, `# Folio\n\nFolio is a small native PDF reader for macOS with chatgpt.com in a side panel, signed in with the person's own ChatGPT account. It quotes selected passages with their page numbers into the chat and marks the pages that were asked about. Not affiliated with OpenAI.\n\n${pages.map(p => `- [${p.label}](/${p.slug}.md)`).join('\n')}\n\nSource: ${repo}\n`);
await writeFile(`${dist}/404.html`, '<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Page not found | Folio</title><link rel="stylesheet" href="/styles.css"><body class="not-found"><h1>Page not found</h1><p>This page is not in the Folio documentation.</p><a class="button primary" href="/">Back to Folio</a></body></html>');
console.log(`Built ${pages.length} pages, Markdown endpoints, and ${search.length} searchable sections.`);
} finally {
  await lock.close();
  await rm(lockPath, { force: true });
}
