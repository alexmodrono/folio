import { bind, play, setEnabled, unlock } from '/vendor/cuelume/index.js';

const $ = selector => document.querySelector(selector);
const $$ = selector => [...document.querySelectorAll(selector)];
const readPreference = key => { try { return localStorage.getItem(key); } catch { return null; } };
const writePreference = (key, value) => { try { localStorage.setItem(key, value); } catch {} };
const systemTheme = matchMedia('(prefers-color-scheme: dark)');
function applyTheme(value) {
  document.documentElement.dataset.theme = value === 'system' ? (systemTheme.matches ? 'dark' : 'light') : value;
  $$('.theme-control select').forEach(select => select.value = value);
}
applyTheme(readPreference('folio-theme') || 'system');
$$('.theme-control select').forEach(select => select.addEventListener('change', () => {
  writePreference('folio-theme', select.value);
  applyTheme(select.value);
}));
systemTheme.addEventListener('change', () => { if ((readPreference('folio-theme') || 'system') === 'system') applyTheme('system'); });

bind();
function applySound(enabled) {
  setEnabled(enabled);
  $$('.sound-toggle').forEach(button => {
    button.setAttribute('aria-pressed', String(enabled));
    button.setAttribute('aria-label', enabled ? 'Turn interface sounds off' : 'Turn interface sounds on');
  });
}
applySound(readPreference('folio-sound') !== 'off');
$$('.sound-toggle').forEach(button => button.addEventListener('click', async () => {
  const enabled = button.getAttribute('aria-pressed') !== 'true';
  writePreference('folio-sound', enabled ? 'on' : 'off');
  applySound(enabled);
  if (enabled && await unlock()) play('toggle');
}));
$('.pagination a:not(.next)')?.addEventListener('click', () => play('navigate', { direction: 'back' }));

const collapse = $('.collapse-sidebar');
function updateCollapse() {
  const collapsed = document.documentElement.dataset.sidebar === 'collapsed';
  collapse.setAttribute('aria-label', collapsed ? 'Expand sidebar' : 'Collapse sidebar');
  collapse.setAttribute('aria-expanded', String(!collapsed));
  $('.sidebar nav').inert = collapsed;
}
updateCollapse();
collapse.addEventListener('click', () => {
  const next = document.documentElement.dataset.sidebar === 'collapsed' ? 'expanded' : 'collapsed';
  document.documentElement.dataset.sidebar = next;
  writePreference('folio-sidebar', next);
  updateCollapse();
});

const mobile = $('.mobile-nav');
$('.menu-trigger').addEventListener('click', () => mobile.showModal());
$('.close-mobile').addEventListener('click', () => mobile.close());
mobile.addEventListener('click', event => { if (event.target === mobile && event.clientX > mobile.getBoundingClientRect().right) { play('close'); mobile.close(); } });
mobile.addEventListener('cancel', () => play('close'));
matchMedia('(min-width: 768px)').addEventListener('change', event => { if (event.matches && mobile.open) mobile.close(); });

let toastTimer;
function notify(message) {
  clearTimeout(toastTimer);
  $('.toast').textContent = message;
  $('.toast').classList.add('visible');
  toastTimer = setTimeout(() => $('.toast').classList.remove('visible'), 2500);
}
async function copyText(text) {
  try { await navigator.clipboard.writeText(text); play('success', { emphasis: 'subtle' }); notify('Copied to clipboard'); return true; }
  catch { play('error', { emphasis: 'subtle' }); notify('Could not copy. Select the text and copy it manually.'); return false; }
}
$$('.copy-code').forEach(button => button.addEventListener('click', async () => {
  if (await copyText(button.closest('.code-block').querySelector('code').textContent)) {
    button.querySelector('span').textContent = 'Copied';
    setTimeout(() => button.querySelector('span').textContent = 'Copy', 2000);
  }
}));
$('.copy-page')?.addEventListener('click', async event => {
  const button = event.currentTarget;
  button.disabled = true;
  try {
    const response = await fetch(`/${document.body.dataset.page}.md`);
    if (!response.ok) throw new Error('Page unavailable');
    await copyText(await response.text());
  } catch { play('error', { emphasis: 'subtle' }); notify('Could not load this page. Please try again.'); }
  finally { button.disabled = false; }
});

const searchDialog = $('.search-dialog');
const searchInput = $('#search-input');
const resultContainer = $('.search-results');
let searchIndex;
let indexRequest;
async function loadIndex() {
  if (searchIndex) return searchIndex;
  if (!indexRequest) indexRequest = fetch('/search.json').then(response => { if (!response.ok) throw new Error('Search unavailable'); return response.json(); }).then(data => searchIndex = data).catch(error => { indexRequest = null; throw error; });
  return indexRequest;
}
function emptyState(text) {
  resultContainer.replaceChildren();
  const p = document.createElement('p'); p.className = 'search-empty'; p.textContent = text; resultContainer.append(p);
}
async function renderSearch() {
  const query = searchInput.value.trim().toLowerCase();
  if (!query) { emptyState('Search for selections, bubbles, or sign-in.'); $('#search-status').textContent = 'Type to search Folio’s documentation'; return; }
  let entries;
  try { entries = await loadIndex(); }
  catch { emptyState('Search could not load. Please try again, or use the page navigation.'); $('#search-status').textContent = 'Search unavailable'; return; }
  if (query !== searchInput.value.trim().toLowerCase()) return;
  const terms = query.split(/\s+/);
  const matches = entries.map(entry => ({ ...entry, score: terms.reduce((n, term) => n + (entry.title.toLowerCase().includes(term) ? 4 : 0) + (entry.section.toLowerCase().includes(term) ? 3 : 0), 0) })).filter(entry => terms.every(term => `${entry.title} ${entry.section} ${entry.text}`.toLowerCase().includes(term))).sort((a, b) => b.score - a.score).slice(0, 15);
  resultContainer.replaceChildren();
  if (!matches.length) emptyState(`No results for “${searchInput.value.trim()}”. Try a different word.`);
  matches.forEach(entry => {
    const link = document.createElement('a'); link.className = 'search-result'; link.href = entry.url; link.dataset.cuelumeNavigate = '';
    const title = document.createElement('strong'); title.textContent = entry.title;
    const section = document.createElement('span'); section.textContent = ` › ${entry.section}`;
    const excerpt = document.createElement('p'); excerpt.textContent = entry.text.replace(/\s+/g, ' ').slice(0, 155) + (entry.text.length > 155 ? '…' : '');
    link.append(title, section, excerpt);
    link.addEventListener('click', () => searchDialog.close());
    resultContainer.append(link);
  });
  $('#search-status').textContent = `${matches.length}${matches.length === 15 ? '+' : ''} result${matches.length === 1 ? '' : 's'}`;
}
function openSearch() {
  if (mobile.open) mobile.close();
  if (!searchDialog.open) searchDialog.showModal();
  searchInput.focus(); renderSearch();
}
$('.search-trigger').addEventListener('click', openSearch);
searchInput.addEventListener('input', renderSearch);
searchDialog.addEventListener('click', event => {
  if (event.target !== searchDialog) return;
  const box = searchDialog.getBoundingClientRect();
  if (event.clientX < box.left || event.clientX > box.right || event.clientY < box.top || event.clientY > box.bottom) { play('close', { emphasis: 'subtle' }); searchDialog.close(); }
});
searchDialog.addEventListener('cancel', () => play('close', { emphasis: 'subtle' }));
searchInput.addEventListener('keydown', event => { if (event.key === 'Enter') { event.preventDefault(); resultContainer.querySelector('a')?.click(); } });
document.addEventListener('keydown', event => {
  if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === 'k') {
    event.preventDefault();
    if (!searchDialog.open) play('open', { emphasis: 'subtle' });
    openSearch();
  }
  if (!searchDialog.open || !['ArrowDown', 'ArrowUp'].includes(event.key)) return;
  event.preventDefault();
  const links = [...resultContainer.querySelectorAll('a')];
  const index = links.indexOf(document.activeElement);
  if (!links.length) return;
  play('select', { emphasis: 'subtle', direction: event.key === 'ArrowDown' ? 'forward' : 'back' });
  if (event.key === 'ArrowDown') (links[index + 1] || links[0])?.focus();
  else if (index <= 0) searchInput.focus(); else links[index - 1]?.focus();
});
const headings = [...document.querySelectorAll('article h2[id]')];
function updateOutline() {
  let current = headings[0]?.id;
  for (const heading of headings) if (heading.getBoundingClientRect().top <= 120) current = heading.id;
  $$('.toc nav a').forEach(link => link.setAttribute('aria-current', String(link.hash === `#${current}`)));
}
let outlinePending = false;
addEventListener('scroll', () => { if (!outlinePending) { outlinePending = true; requestAnimationFrame(() => { updateOutline(); outlinePending = false; }); } }, { passive: true });
updateOutline();

// Homepage hero backdrop: when the painting is shorter than the hero text, switch that text
// back to the theme's colors (hero-short). The painting's box is sized by CSS alone.
const backdrop = $('.hero-backdrop');
if (backdrop) {
  const main = $('main'), heroText = $('.hero-note') || $('.hero');
  const measure = () => {
    const top = main.getBoundingClientRect().top - 56;
    document.body.classList.toggle('hero-short', heroText.getBoundingClientRect().bottom - top > backdrop.clientHeight * 0.92);
  };
  new ResizeObserver(measure).observe(main);
  measure();
}
