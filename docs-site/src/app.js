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

// Homepage hero backdrop: the painting drawn once per resize as coarse cells with ordered
// dithering, a little grain and a dithered dissolve at the bottom, so it reads as texture
// behind the hero instead of a picture. Without WebGL the pixelated <img> stays.
const backdrop = $('.hero-backdrop');
if (backdrop) {
  const main = $('main'), hero = $('.hero'), heroText = $('.hero-note') || hero, image = backdrop.querySelector('img'), canvas = backdrop.querySelector('canvas');
  const gl = canvas.getContext('webgl', { premultipliedAlpha: true, antialias: false });
  const CELL = 4, BLUR = 10; // CSS px: the size of a pixel block and the soft-focus radius.
  let fadeStart = 0.8;
  // The painting's box is sized by CSS alone (full window width, the image's aspect ratio), so
  // it never changes size after the first paint. This only decides where the dissolve starts
  // (just below the hero) and, when the painting is shorter than the hero text, switches that
  // text back to the theme's colors (hero-short).
  function measure() {
    const top = main.getBoundingClientRect().top - 56;
    const height = backdrop.clientHeight;
    const short = heroText.getBoundingClientRect().bottom - top > height * 0.92;
    fadeStart = short ? 0.45 : Math.min(0.9, Math.max(0.6, (hero.getBoundingClientRect().bottom - top - 16) / height));
    document.body.classList.toggle('hero-short', short);
  }
  const vertex = 'attribute vec2 p;void main(){gl_Position=vec4(p,0.,1.);}';
  const fragment = `precision mediump float;
uniform sampler2D img;uniform vec2 res,blur;uniform float cell,fade;
float b2(vec2 a){a=floor(a);return fract(a.x/2.+a.y*a.y*.75);}
float bayer(vec2 a){return b2(.5*a)*.25+b2(a);}
float hash(vec2 p){return fract(sin(dot(p,vec2(12.9898,78.233)))*43758.5453);}
float noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.-2.*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+1.),f.x),f.y);}
// A soft-focus read of the painting: 13 taps spread over a disc of radius blur (in uv).
vec3 soft(vec2 t){vec3 s=texture2D(img,t).rgb;for(int i=0;i<12;i++){float a=float(i)*2.39996,r=sqrt((float(i)+.5)/12.);s+=texture2D(img,t+vec2(cos(a),sin(a))*r*blur).rgb;}return s/13.;}
void main(){
  vec2 c=floor(gl_FragCoord.xy/cell);
  vec2 uv=(c+.5)*cell/res;uv.y=1.-uv.y;
  vec3 col=soft(uv);
  float l=dot(col,vec3(.299,.587,.114));
  col=mix(vec3(l),col,1.2)*.9;
  vec2 e=(uv-vec2(.5,.38))/vec2(.32,.36);col*=1.-.2*exp(-dot(e,e)*1.5);
  float d=bayer(c),n=hash(c);
  col+=(n-.5)*.05;
  col=floor(col*12.+d)/12.;
  float edge=uv.y+(noise(c/7.)-.5)*.18;
  float a=1.-smoothstep(fade,1.,edge);
  float keep=step(d*.45+n*.55+.001,a);
  gl_FragColor=vec4(col*keep,keep);
}`;
  function compile(type, source) { const shader = gl.createShader(type); gl.shaderSource(shader, source); gl.compileShader(shader); return shader; }
  function start() {
    const program = gl.createProgram();
    gl.attachShader(program, compile(gl.VERTEX_SHADER, vertex));
    gl.attachShader(program, compile(gl.FRAGMENT_SHADER, fragment));
    gl.linkProgram(program);
    if (!gl.getProgramParameter(program, gl.LINK_STATUS)) return;
    gl.useProgram(program);
    gl.bindBuffer(gl.ARRAY_BUFFER, gl.createBuffer());
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW);
    const position = gl.getAttribLocation(program, 'p');
    gl.enableVertexAttribArray(position);
    gl.vertexAttribPointer(position, 2, gl.FLOAT, false, 0, 0);
    gl.bindTexture(gl.TEXTURE_2D, gl.createTexture());
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, image);
    for (const [key, value] of [[gl.TEXTURE_MIN_FILTER, gl.LINEAR], [gl.TEXTURE_MAG_FILTER, gl.LINEAR], [gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE], [gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE]]) gl.texParameteri(gl.TEXTURE_2D, key, value);
    const uniform = name => gl.getUniformLocation(program, name);
    let frame;
    function draw() {
      frame = null;
      measure();
      // Cells are 4 CSS px. Each is drawn as a whole number of buffer pixels, as many as the
      // screen has (8 on Retina), but never so many that the buffer passes 4096 px: browsers
      // silently shrink larger WebGL buffers. Sizes are read back from the buffer actually given.
      const columns = Math.ceil(canvas.clientWidth / CELL), rows = Math.ceil(canvas.clientHeight / CELL);
      if (!columns || !rows) return;
      const cell = Math.max(1, Math.floor(Math.min(CELL * (devicePixelRatio || 1), 4096 / columns, 4096 / rows)));
      canvas.width = columns * cell; canvas.height = rows * cell;
      gl.viewport(0, 0, gl.drawingBufferWidth, gl.drawingBufferHeight);
      gl.uniform2f(uniform('res'), gl.drawingBufferWidth, gl.drawingBufferHeight);
      gl.uniform1f(uniform('cell'), cell * gl.drawingBufferWidth / canvas.width);
      gl.uniform2f(uniform('blur'), BLUR / canvas.clientWidth, BLUR / canvas.clientHeight);
      gl.uniform1f(uniform('fade'), fadeStart);
      gl.drawArrays(gl.TRIANGLES, 0, 3);
      backdrop.classList.add('ready');
    }
    new ResizeObserver(() => { if (!frame) frame = requestAnimationFrame(draw); }).observe(main);
    draw();
  }
  measure();
  if (gl) image.complete && image.naturalWidth ? start() : image.addEventListener('load', start, { once: true });
}
