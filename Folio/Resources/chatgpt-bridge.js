// Folio bridge for chatgpt.com. Runs in an isolated content world, so the page can't see it.
// It only edits the composer the way a person would (attach a file, paste text). It never sends on its own:
// PDF selections wait as a chip and go into the message when the person sends it.
(() => {
  // Sign-in popups (Google, Apple, Microsoft, auth.openai.com) share the card's scripts; stay out of them.
  if (!/(^|\.)chatgpt\.com$/.test(location.hostname)) return;
  if (window.__folio) return;

  // Update these when chatgpt.com changes its markup.
  const SELECTORS = {
    composer: [
      '#prompt-textarea',
      'div[contenteditable="true"].ProseMirror',
      'form div[contenteditable="true"]',
      'form textarea',
    ],
    fileInput: 'input[type="file"]',
    newChat: ['a[data-testid="create-new-chat-button"]', 'nav a[href="/"]'],
    // Selection chips go first in this column, above the attachments and the text.
    composerBody: '[class*="ComposerLayoutBody"]',
    sendButton: [
      'button[data-testid="send-button"]',
      '#composer-submit-button',
      'form button[type="submit"][aria-label="Send"]',
      'button[aria-label="Send prompt"]',
    ],
    // Takes the send button's place while a reply streams. Only the health check uses it.
    stopButton: ['button[data-testid="stop-button"]', 'form button[aria-label^="Stop"]'],
    userMessage: '[data-user-message-bubble], [data-message-author-role="user"]',
  };

  const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

  async function waitFor(check, timeout = 10000, interval = 100) {
    const end = performance.now() + timeout;
    for (;;) {
      const value = check();
      if (value) return value;
      if (performance.now() > end) return null;
      await sleep(interval);
    }
  }

  const visible = (el) => {
    const rect = el.getBoundingClientRect();
    return rect.width > 0 && rect.height > 0;
  };

  function composer() {
    for (const selector of SELECTORS.composer) {
      const el = [...document.querySelectorAll(selector)].find(visible);
      if (el) return el;
    }
    return null;
  }

  // The composer's form holds both the text and the attachment chips.
  const scopeOf = (el) => (el && el.closest('form')) || document.body;

  // The composer form's size and text, to tell whether an edit took.
  function signature() {
    const scope = scopeOf(composer());
    return { nodes: scope.querySelectorAll('*').length, text: `${scope.innerText}`.replace(/\s+/g, '') };
  }

  // Signed-out chatgpt.com only accepts images, so file attachments are skipped there.
  function signedOut() {
    if (document.querySelector('[data-testid="login-button"]')) return true;
    return [...document.querySelectorAll('button, a')].some((b) => /^log in$/i.test((b.innerText || '').trim()));
  }

  function placeCaretAtEnd(el) {
    el.focus();
    if (el.tagName === 'TEXTAREA') {
      el.selectionStart = el.selectionEnd = el.value.length;
      return;
    }
    const range = document.createRange();
    range.selectNodeContents(el);
    range.collapse(false);
    const selection = window.getSelection();
    selection.removeAllRanges();
    selection.addRange(range);
  }

  function bytesFrom(base64) {
    if (Uint8Array.fromBase64) return Uint8Array.fromBase64(base64);
    const binary = atob(base64);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
    return bytes;
  }

  function fileInput() {
    const accepts = (input) => {
      const accept = (input.getAttribute('accept') || '').toLowerCase();
      return !accept || accept.includes('pdf') || accept.includes('*');
    };
    return [...document.querySelectorAll(SELECTORS.fileInput)].find((i) => !i.disabled && accepts(i)) || null;
  }

  // Matches an attachment's label: the file name, chatgpt.com's renamed repeats ("name(2).pdf"), and with
  // `verb`, labels like "Remove name.pdf" or "Uploading name.pdf" on the same tile.
  function fileLabel(name, verb = false) {
    const dot = name.lastIndexOf('.');
    const base = dot > 0 ? name.slice(0, dot) : name;
    const ext = dot > 0 ? name.slice(dot) : '';
    const escape = (text) => text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    const pattern = new RegExp(`^${verb ? '(?:\\S+\\s)?' : ''}${escape(base)}(\\s?\\(\\d+\\))?${escape(ext)}$`, 'i');
    return (el) => pattern.test((el.getAttribute('title') || el.getAttribute('aria-label') || el.getAttribute('alt') || '').trim());
  }
  const LABELED = '[title],[aria-label],img[alt]';

  // How many labels in the composer's form name this file: its attachment tiles, not text typed in the composer.
  function filesInComposer(name) {
    const el = composer();
    const form = el && el.closest('form');
    if (!form) return 0;
    const named = fileLabel(name, true);
    // Folio's own chips (the attach offer, selections) carry names too; only chatgpt.com's tiles count.
    const ours = (n) => n.closest('.folio-suggestion, .folio-selections');
    return [...form.querySelectorAll(LABELED)].filter((n) => !el.contains(n) && !ours(n) && named(n)).length;
  }

  // Tries the file input, then a paste, then a drop. Each step waits for a tile with the file name.
  async function attachFile(base64, name, mime) {
    const el = await waitFor(composer);
    if (!el) return 'no-composer';
    if (signedOut()) return 'signed-out';
    const file = new File([bytesFrom(base64)], name, { type: mime, lastModified: Date.now() });
    const before = filesInComposer(name);
    // Only a new tile named for the file counts; other DOM changes in the form (a paste of its path as
    // text, a menu opening) don't.
    const landed = () => filesInComposer(name) > before;
    const transfer = () => {
      const dt = new DataTransfer();
      dt.items.add(file);
      return dt;
    };

    const input = fileInput();
    if (input) {
      input.files = transfer().files;
      input.dispatchEvent(new Event('change', { bubbles: true }));
      if (await waitFor(landed, 4000)) return 'input';
    }

    placeCaretAtEnd(el);
    el.dispatchEvent(new ClipboardEvent('paste', { clipboardData: transfer(), bubbles: true, cancelable: true }));
    if (await waitFor(landed, 3000)) return 'paste';

    const drop = transfer();
    for (const type of ['dragenter', 'dragover', 'drop']) {
      el.dispatchEvent(new DragEvent(type, { dataTransfer: drop, bubbles: true, cancelable: true }));
    }
    if (await waitFor(landed, 3000)) return 'drop';
    return 'failed';
  }

  function placeCaretAtStart(el) {
    el.focus();
    if (el.tagName === 'TEXTAREA') {
      el.selectionStart = el.selectionEnd = 0;
      return;
    }
    const range = document.createRange();
    range.selectNodeContents(el);
    range.collapse(true);
    const selection = window.getSelection();
    selection.removeAllRanges();
    selection.addRange(range);
  }

  async function insertText(text, atStart = false) {
    const el = await waitFor(composer);
    if (!el) return 'no-composer';
    (atStart ? placeCaretAtStart : placeCaretAtEnd)(el);
    // ProseMirror reads the caret on `selectionchange`, which fires asynchronously.
    if (atStart) await sleep(50);

    if (el.tagName === 'TEXTAREA') {
      const setter = Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, 'value').set;
      setter.call(el, atStart ? text + el.value : el.value + text);
      el.dispatchEvent(new Event('input', { bubbles: true }));
      return 'textarea';
    }

    const before = signature();
    const changed = () => {
      const now = signature();
      return now.text !== before.text || now.nodes !== before.nodes;
    };

    const dt = new DataTransfer();
    dt.setData('text/plain', text);
    el.dispatchEvent(new ClipboardEvent('paste', { clipboardData: dt, bubbles: true, cancelable: true }));
    if (await waitFor(changed, 1500, 50)) return 'paste';

    document.execCommand('insertText', false, text);
    if (await waitFor(changed, 1500, 50)) return 'exec';
    return 'failed';
  }

  // Where a file with this name already is: 'composer' (waiting to be sent), 'conversation' (sent earlier
  // in this chat), or ''. chatgpt.com renames repeats to "name(2).pdf", so those count too.
  // Images are labeled by their tile's aria-label and <img alt>.
  async function hasFile(name) {
    const form = composer()?.closest('form');
    if (filesInComposer(name) > 0) return 'composer';
    if (!/\/c\/[^/]+/.test(location.pathname)) return '';
    // A conversation's messages render a moment after the page.
    await waitFor(() => document.querySelector(SELECTORS.userMessage), 3000, 100);
    const named = fileLabel(name);
    const sent = [...document.querySelectorAll(LABELED)].some((el) => named(el) && !(form && form.contains(el)));
    return sent ? 'conversation' : '';
  }

  function composerText() {
    const el = composer();
    if (!el) return '';
    return (el.tagName === 'TEXTAREA' ? el.value : el.innerText).trim();
  }

  // Removes `text` that a native paste typed into the composer (WebKit pastes a file's path as text
  // when the page doesn't take the file).
  function removeText(text) {
    const el = composer();
    if (!el) return false;
    const read = () => (el.tagName === 'TEXTAREA' ? el.value : el.innerText);
    if (!read().includes(text)) return false;
    document.execCommand('undo');
    if (!read().includes(text)) return true;
    const rest = read().replace(text, '').trim();
    el.focus();
    const range = document.createRange();
    range.selectNodeContents(el);
    const selection = window.getSelection();
    selection.removeAllRanges();
    selection.addRange(range);
    document.execCommand('insertText', false, rest);
    return true;
  }

  function focusComposer() {
    const el = composer();
    if (el) placeCaretAtEnd(el);
    return !!el;
  }

  function startNewChat() {
    for (const selector of SELECTORS.newChat) {
      const link = document.querySelector(selector);
      if (link) {
        link.click();
        return true;
      }
    }
    return false;
  }

  // A compact description of what the bridge can see, for debugging selectors.
  function probe() {
    const el = composer();
    return JSON.stringify({
      path: location.pathname,
      composer: el ? `${el.tagName.toLowerCase()}#${el.id}` : null,
      signedOut: signedOut(),
      inForm: !!(el && el.closest('form')),
      fileInputs: [...document.querySelectorAll(SELECTORS.fileInput)].map((i) => i.getAttribute('accept') || '*'),
      newChat: SELECTORS.newChat.some((s) => document.querySelector(s)),
    });
  }


  // MARK: Selections
  //
  // A PDF selection waits as a chip above the composer. When the person sends, it goes in front of their
  // message as CriticMarkup, {==quoted text==}{>>where it's from<<}, which the model reads as a highlight
  // with a note. User messages holding that markup show it as the same chip.

  const MARKUP = /\{==([\s\S]*?)==\}(?:\{>>([\s\S]*?)<<\})?\s*/g;
  // Waiting selections survive reloads in this tab's session storage.
  const STORE_KEY = 'folio.selections';
  const pending = (() => {
    try {
      const saved = JSON.parse(sessionStorage.getItem(STORE_KEY) || '[]');
      return Array.isArray(saved) ? saved.filter((item) => item && typeof item.text === 'string') : [];
    } catch {
      return [];
    }
  })();
  let flushing = false;

  function savePending() {
    try {
      if (pending.length) sessionStorage.setItem(STORE_KEY, JSON.stringify(pending));
      else sessionStorage.removeItem(STORE_KEY);
    } catch {}
  }

  // SF Symbols rendered by Folio (`window.__folioIcons`, set by a script that runs just before this one),
  // used as masks so they take the text color. The SVG is a fallback if they're missing.
  const ICON =
    '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.3" stroke-linejoin="round" aria-hidden="true">' +
    '<path d="M4 1.75h5.25L12 4.5v9.75H4z"/><path d="M9 1.75V4.5h3M6.25 8h3.5M6.25 10.5h3.5"/></svg>';

  function iconFor(items) {
    const fromChats = items.every((item) => /^From (the chat|another chat)/.test(item.source));
    const url = (window.__folioIcons || {})[fromChats ? 'chat' : 'file'];
    if (!url) {
      const wrapper = document.createElement('span');
      wrapper.innerHTML = ICON;
      return wrapper.firstChild;
    }
    const icon = document.createElement('span');
    icon.className = 'folio-icon';
    icon.setAttribute('aria-hidden', 'true');
    icon.style.setProperty('--folio-icon', `url("${url}")`);
    return icon;
  }

  const STYLE = `
    .folio-selections { display: flex; flex-direction: column; gap: 8px; align-items: flex-start; }
    .folio-tray { padding: 10px 12px 0; }
    .folio-chip-row { display: flex; align-items: center; gap: 4px; }
    .folio-chip {
      display: inline-flex; align-items: center; gap: 6px; height: 32px; padding: 0 12px;
      border-radius: 999px; border: 1px solid color-mix(in srgb, currentColor 16%, transparent);
      background: color-mix(in srgb, currentColor 5%, transparent); color: inherit;
      font: 500 14px/1 inherit; cursor: pointer; user-select: none;
    }
    .folio-chip:hover { background: color-mix(in srgb, currentColor 10%, transparent); }
    .folio-chip svg { width: 16px; height: 16px; opacity: 0.7; flex: none; }
    .folio-icon {
      width: 16px; height: 16px; flex: none; opacity: 0.75; background-color: currentColor;
      -webkit-mask: var(--folio-icon) center / contain no-repeat; mask: var(--folio-icon) center / contain no-repeat;
    }
    .folio-remove {
      width: 24px; height: 24px; border-radius: 999px; border: 0; background: none; color: inherit;
      opacity: 0.55; cursor: pointer; font-size: 16px; line-height: 24px;
    }
    .folio-remove:hover { opacity: 1; background: color-mix(in srgb, currentColor 10%, transparent); }
    .folio-suggestion { display: flex; align-items: center; gap: 4px; padding: 10px 12px 0; min-width: 0; }
    .folio-suggestion .folio-chip { cursor: default; flex: 0 1 auto; min-width: 0; }
    .folio-suggestion button { flex: none; }
    .folio-suggestion .folio-name { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
    .folio-attach {
      height: 32px; padding: 0 12px; border-radius: 999px; border: 0; cursor: pointer; color: inherit;
      font: 500 14px/1 inherit; background: color-mix(in srgb, currentColor 12%, transparent);
    }
    .folio-attach:hover { background: color-mix(in srgb, currentColor 18%, transparent); }
    .folio-quotes { display: none; flex-direction: column; gap: 8px; max-width: 100%; }
    .folio-selections[data-open] .folio-quotes { display: flex; }
    .folio-tray .folio-quotes { max-height: 160px; overflow: auto; }
    .folio-quote {
      border-left: 2px solid color-mix(in srgb, currentColor 25%, transparent); padding-left: 10px;
      white-space: pre-wrap; text-align: start; font-size: 14px; line-height: 1.45;
    }
    .folio-quote-text {
      display: -webkit-box; -webkit-box-orient: vertical; -webkit-line-clamp: 6; overflow: hidden;
    }
    .folio-source { display: block; margin-top: 2px; font-size: 12px; opacity: 0.6; }
    .folio-message-selections { margin-bottom: 8px; }
  `;

  function installStyle() {
    if (document.getElementById('folio-style')) return;
    const style = document.createElement('style');
    style.id = 'folio-style';
    style.textContent = STYLE;
    (document.head || document.documentElement).appendChild(style);
  }

  const clean = (text) => text.replace(/\s+/g, ' ').trim().replace(/==\}/g, '= =}').replace(/<<\}/g, '< <}');

  // A whole-page reference's source ends in "(whole page)", in the composer and in sent messages alike.
  const WHOLE_PAGE = /\(whole page\)$/;
  const pageNumber = (item) => (item.source.match(/pages? ([\d–-]+)/) || [])[1];

  // Visible labels in the app's language (`window.__folioStrings`, set by a script that runs just before this
  // one), with English fallbacks. Only what's shown is translated; sources in the markup stay English.
  function t(key, fallback, values = {}) {
    let text = (window.__folioStrings || {})[key] || fallback;
    for (const [name, value] of Object.entries(values)) text = text.split(`{${name}}`).join(String(value));
    return text;
  }

  function chipLabel(items) {
    const pages = items.filter((item) => WHOLE_PAGE.test(item.source));
    if (items.length === 1 && pages.length === 1) {
      const n = pageNumber(pages[0]);
      return n ? t('page', 'Page {n}', { n }) : t('onePage', '1 page');
    }
    if (pages.length === items.length) return t('pages', '{n} pages', { n: items.length });
    if (pages.length === 0) {
      return items.length === 1 ? t('oneSelection', '1 selection') : t('selections', '{n} selections', { n: items.length });
    }
    return t('references', '{n} references', { n: items.length });
  }

  // A quote's source as shown under it. The English source itself is what goes into the message.
  const SOURCE_FORMS = [
    [/^From (.+), page (\S+) \(whole page\)$/, 'fromWholePage', (m) => ({ doc: m[1], n: m[2] })],
    [/^From (.+), pages (\S+)$/, 'fromPages', (m) => ({ doc: m[1], n: m[2] })],
    [/^From (.+), page (\S+)$/, 'fromPage', (m) => ({ doc: m[1], n: m[2] })],
    [/^From the chat “(.*)”$/, 'fromChat', (m) => ({ title: m[1] })],
    [/^From another chat$/, 'fromAnotherChat', () => ({})],
  ];

  function sourceLabel(source) {
    for (const [pattern, key, values] of SOURCE_FORMS) {
      const match = source.match(pattern);
      if (match) return t(key, source, values(match));
    }
    return source;
  }

  // The chip with its expandable list of quotes. `onRemove` adds a remove button (composer only).
  function selectionsView(items, onRemove) {
    const root = document.createElement('div');
    root.className = 'folio-selections';
    const row = document.createElement('div');
    row.className = 'folio-chip-row';
    const chip = document.createElement('button');
    chip.type = 'button';
    chip.className = 'folio-chip';
    chip.append(iconFor(items), chipLabel(items));
    chip.setAttribute('aria-expanded', 'false');
    chip.addEventListener('click', (event) => {
      event.preventDefault();
      event.stopPropagation();
      const open = !root.hasAttribute('data-open');
      root.toggleAttribute('data-open', open);
      chip.setAttribute('aria-expanded', String(open));
    });
    row.append(chip);
    if (onRemove) {
      const remove = document.createElement('button');
      remove.type = 'button';
      remove.className = 'folio-remove';
      remove.textContent = '×';
      remove.title = items.length === 1 ? t('removeSelection', 'Remove selection') : t('removeSelections', 'Remove selections');
      remove.setAttribute('aria-label', remove.title);
      remove.addEventListener('click', (event) => {
        event.preventDefault();
        event.stopPropagation();
        onRemove();
      });
      row.append(remove);
    }
    const quotes = document.createElement('div');
    quotes.className = 'folio-quotes';
    for (const item of items) {
      const quote = document.createElement('div');
      quote.className = 'folio-quote';
      const text = document.createElement('span');
      text.className = 'folio-quote-text';
      text.textContent = item.text;
      quote.append(text);
      if (item.source) {
        const source = document.createElement('span');
        source.className = 'folio-source';
        source.textContent = sourceLabel(item.source);
        quote.append(source);
      }
      quotes.append(quote);
    }
    root.append(row, quotes);
    return root;
  }

  // Keeps the composer's chip in step with `pending`. React can replace the composer, so this runs
  // again whenever the page changes.
  function syncTray() {
    savePending();
    const body = document.querySelector(SELECTORS.composerBody);
    let tray = document.querySelector('.folio-tray');
    const key = JSON.stringify(pending);
    if (!pending.length || !body) {
      tray?.remove();
      return;
    }
    if (tray && tray.parentElement === body && tray.dataset.key === key) return;
    const wasOpen = tray?.hasAttribute('data-open');
    tray?.remove();
    installStyle();
    tray = selectionsView(pending, () => {
      pending.length = 0;
      syncTray();
      focusComposer();
    });
    tray.classList.add('folio-tray');
    tray.dataset.key = key;
    if (wasOpen) tray.setAttribute('data-open', '');
    body.prepend(tray);
  }

  // `anchor` says where in which PDF the text came from. It stays in Folio: the message only gets the
  // quote and its source, and the anchor comes back in the "sent" report so Folio can pin a bubble there.
  // When the chip can't show or there's no send button to hold, the selection goes straight into the
  // composer as markup text instead, so asking still works. Returns how many selections are waiting
  // (as chips or text), 0 if none could be added.
  async function addSelection(text, source, anchor) {
    const quote = clean(text);
    if (!quote) return pending.length;
    const item = { text: quote, source: clean(source || '') };
    if (anchor && typeof anchor === 'object') item.anchor = anchor;
    pending.push(item);
    if (!fallback()) {
      syncTray();
      return pending.length;
    }
    return (await pasteSelections()) ? 1 : 0;
  }

  // The chip tray needs the composer's body, and holding a send needs a send button.
  const fallback = () => !document.querySelector(SELECTORS.composerBody) || sendState === false;

  // Moves waiting selections into the composer as text, after anything already typed.
  async function pasteSelections() {
    if (!pending.length) return true;
    const el = composer();
    if (!el) return false;
    // This markup is meant to stay as text, not turn back into a chip.
    adopted.add(el);
    const items = pending.splice(0);
    savePending();
    const typed = el.tagName === 'TEXTAREA' ? el.value : el.innerText;
    const gap = !typed.trim() || /\n\s*\n\s*$/.test(typed) ? '' : '\n\n';
    const result = await insertText(gap + markup(items));
    if (result === 'failed' || result === 'no-composer') {
      pending.unshift(...items);
      savePending();
      return false;
    }
    return true;
  }

  function clearSelections() {
    pending.length = 0;
    syncTray();
  }

  const markup = (items) =>
    items.map((item) => `{==${item.text}==}` + (item.source ? `{>>${item.source}<<}` : '')).join('\n') + '\n\n';

  // Puts the waiting selections in front of the message. Returns false if the composer didn't take them.
  async function flushSelections() {
    if (!pending.length) return true;
    const result = await insertText(markup(pending), true);
    if (result === 'failed' || result === 'no-composer') return false;
    pending.length = 0;
    syncTray();
    return true;
  }

  function sendButton() {
    for (const selector of SELECTORS.sendButton) {
      const button = document.querySelector(selector);
      if (button) return button;
    }
    return null;
  }

  // Holds a send until the selections are in the message, then sends it the way the person asked to.
  async function sendWithSelections() {
    flushing = true;
    // The markup this puts in the composer is being sent, not a draft to turn back into a chip.
    const el = composer();
    if (el) adopted.add(el);
    const items = pending.slice();
    const question = composerText();
    let sent = false;
    try {
      if (!(await flushSelections())) return;
      const button = await waitFor(() => {
        const b = sendButton();
        return b && !b.disabled ? b : null;
      }, 2000, 50);
      if (button) {
        button.click();
        sent = true;
      }
    } finally {
      flushing = false;
    }
    if (sent) reportSent(items, question);
  }

  // Tells Folio which PDF passages went out in which conversation, once a new chat has its /c/ address.
  async function reportSent(items, question) {
    const anchored = items.filter((item) => item.anchor);
    if (!anchored.length) return;
    const path = (await waitFor(() => (/\/c\/[^/]+/.test(location.pathname) ? location.pathname : null), 15000, 200))
      || location.pathname;
    window.webkit?.messageHandlers?.folio?.postMessage({ type: 'sent', path, question, items: anchored });
  }

  // Scrolls to the sent message that quotes `quote` and opens its chip. Returns false until it's on the page.
  function revealQuote(quote) {
    const needle = clean(quote).slice(0, 80);
    for (const view of document.querySelectorAll('.folio-message-selections')) {
      const match = [...view.querySelectorAll('.folio-quote')].some((q) => clean(q.querySelector('.folio-quote-text')?.textContent || '').startsWith(needle));
      if (!match) continue;
      view.setAttribute('data-open', '');
      view.closest(SELECTORS.userMessage)?.scrollIntoView({ block: 'center', behavior: 'smooth' });
      return true;
    }
    return false;
  }

  function interceptsSend(event) {
    if (!pending.length || flushing) return false;
    if (event.type === 'keydown') {
      if (event.key !== 'Enter' || event.shiftKey || event.altKey || event.isComposing) return false;
      const el = composer();
      return !!el && (event.target === el || el.contains(event.target));
    }
    if (event.type === 'submit') {
      const el = composer();
      return !!el && event.target instanceof Element && event.target.contains(el);
    }
    const button = event.target instanceof Element && event.target.closest(SELECTORS.sendButton.join(','));
    return !!button;
  }

  // Capture on window runs before ProseMirror's and React's handlers.
  for (const type of ['keydown', 'click', 'submit']) {
    window.addEventListener(
      type,
      (event) => {
        if (!interceptsSend(event)) return;
        event.preventDefault();
        event.stopImmediatePropagation();
        sendWithSelections();
      },
      true
    );
  }

  // Shows selection markup in the person's own messages as a chip. Only the text node's value changes and
  // the chip is added beside it, so React still finds the nodes it owns.
  function renderMessages(root) {
    const messages = root.querySelectorAll ? root.querySelectorAll(SELECTORS.userMessage) : [];
    for (const message of messages) {
      const walker = document.createTreeWalker(message, NodeFilter.SHOW_TEXT);
      const nodes = [];
      for (let node = walker.nextNode(); node; node = walker.nextNode()) {
        if (node.nodeValue.includes('{==')) nodes.push(node);
      }
      for (const node of nodes) {
        const items = [];
        const rest = node.nodeValue.replace(MARKUP, (_, text, source) => {
          items.push({ text: text.trim(), source: (source || '').trim() });
          return '';
        });
        if (!items.length) continue;
        installStyle();
        const previous = node.previousSibling;
        if (previous && previous.classList?.contains('folio-message-selections')) previous.remove();
        const view = selectionsView(items);
        view.classList.add('folio-message-selections');
        node.parentNode.insertBefore(view, node);
        node.nodeValue = rest.replace(/^\s+/, '');
      }
    }
  }

  // chatgpt.com can restore a draft that still holds selection markup (sometimes the one just sent from a
  // new chat). Markup at the start of a composer turns back into the chip, once per composer.
  const adopted = new WeakSet();
  const LEADING = /^\s*(?:\{==[\s\S]*?==\}(?:\{>>[\s\S]*?<<\})?\s*)+/;

  function adoptDraft() {
    const el = composer();
    if (!el || flushing || adopted.has(el) || fallback()) return;
    const text = el.tagName === 'TEXTAREA' ? el.value : el.innerText;
    if (!text.trim()) return;
    adopted.add(el);
    const lead = text.match(LEADING);
    if (!lead) return;
    for (const [, quote, source] of lead[0].matchAll(MARKUP)) {
      pending.push({ text: quote.trim(), source: (source || '').trim() });
    }
    replaceComposerText(el, text.slice(lead[0].length));
    syncTray();
  }

  function replaceComposerText(el, text) {
    if (el.tagName === 'TEXTAREA') {
      const setter = Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, 'value').set;
      setter.call(el, text);
      el.dispatchEvent(new Event('input', { bubbles: true }));
      return;
    }
    el.focus();
    const range = document.createRange();
    range.selectNodeContents(el);
    const selection = window.getSelection();
    selection.removeAllRanges();
    selection.addRange(range);
    // Let ProseMirror pick up the selection before replacing it.
    setTimeout(() => {
      if (!text) {
        document.execCommand('delete');
        return;
      }
      const dt = new DataTransfer();
      dt.setData('text/plain', text);
      el.dispatchEvent(new ClipboardEvent('paste', { clipboardData: dt, bubbles: true, cancelable: true }));
    }, 50);
  }

  // Tells Folio what's selected outside the composer, so the card's context menu can offer to ask about
  // it in another chat card.
  let reportedSelection = '';
  let selectionTimer = null;
  function reportSelection() {
    const selection = window.getSelection();
    let text = selection ? selection.toString() : '';
    const el = composer();
    if (text && el && selection.anchorNode && el.contains(selection.anchorNode)) text = '';
    if (text === reportedSelection) return;
    reportedSelection = text;
    window.webkit?.messageHandlers?.folio?.postMessage({ type: 'selection', text });
  }
  document.addEventListener('selectionchange', () => {
    clearTimeout(selectionTimer);
    selectionTimer = setTimeout(reportSelection, 100);
  });

  // MARK: Health
  //
  // chatgpt.com changes its markup without notice. Once a page settles, this checks that the parts Folio
  // relies on are there and tells Folio, which shows a notice when they aren't.

  // Whether a send button showed while the composer had text: true, false, or null (not known yet). The
  // button only appears once something is typed.
  let sendState = null;
  let sendTimer = null;
  let healthPath = null;
  let healthTimer = null;
  let reportedHealth = '';

  const sendCapable = () => !!sendButton() || SELECTORS.stopButton.some((s) => document.querySelector(s));

  async function checkHealth() {
    clearTimeout(healthTimer);
    const missing = [];
    if (/(^|\.)chatgpt\.com$/.test(location.hostname) && !signedOut()) {
      if (!(await waitFor(composer, 8000, 250))) missing.push('composer');
      if (!document.querySelector(SELECTORS.composerBody)) missing.push('composerBody');
      if (sendState === false) missing.push('sendButton');
    }
    const report = JSON.stringify(missing);
    if (report !== reportedHealth) {
      reportedHealth = report;
      window.webkit?.messageHandlers?.folio?.postMessage({ type: 'health', ok: !missing.length, missing });
    }
    // Selections that can't show as a chip any more go into the composer as text.
    if (pending.length && fallback()) pasteSelections();
    return { ok: !missing.length, missing };
  }

  // Watches for the send button once the person types. Runs on every page change.
  function watchSend() {
    if (flushing || !composerText()) {
      clearTimeout(sendTimer);
      sendTimer = null;
      return;
    }
    if (sendCapable()) {
      clearTimeout(sendTimer);
      sendTimer = null;
      if (sendState !== true) {
        sendState = true;
        checkHealth();
      }
      return;
    }
    if (sendTimer || sendState === false) return;
    sendTimer = setTimeout(() => {
      sendTimer = null;
      if (composerText() && !sendCapable()) {
        sendState = false;
        checkHealth();
      }
    }, 1500);
  }

  // Offers the open PDF to a new chat without uploading it: chatgpt.com uploads a file the moment it lands
  // in the composer, so Folio only attaches when the person clicks Attach (unless auto-attach is on).
  let suggested = null;

  function suggestFile(name) {
    suggested = name || null;
    syncSuggestion();
    return !!suggested;
  }

  function syncSuggestion() {
    const body = document.querySelector(SELECTORS.composerBody);
    let view = document.querySelector('.folio-suggestion');
    // Only new chats get the offer; a conversation keeps whatever it already has.
    const show = suggested && body && /^\/?$/.test(location.pathname);
    if (!show) {
      view?.remove();
      return;
    }
    if (view && view.parentElement === body && view.dataset.name === suggested) return;
    view?.remove();
    installStyle();
    view = document.createElement('div');
    view.className = 'folio-suggestion';
    view.dataset.name = suggested;
    const chip = document.createElement('span');
    chip.className = 'folio-chip';
    const name = document.createElement('span');
    name.className = 'folio-name';
    name.textContent = suggested;
    chip.append(iconFor([{ source: '' }]), name);
    chip.title = suggested;
    const attach = document.createElement('button');
    attach.type = 'button';
    attach.className = 'folio-attach';
    attach.textContent = t('attach', 'Attach');
    attach.addEventListener('click', (event) => {
      event.preventDefault();
      event.stopPropagation();
      window.webkit?.messageHandlers?.folio?.postMessage({ type: 'attachSuggested', name: suggested });
    });
    const dismiss = document.createElement('button');
    dismiss.type = 'button';
    dismiss.className = 'folio-remove';
    dismiss.textContent = '×';
    dismiss.title = t('dontAttach', "Don't attach");
    dismiss.setAttribute('aria-label', dismiss.title);
    dismiss.addEventListener('click', (event) => {
      event.preventDefault();
      event.stopPropagation();
      window.webkit?.messageHandlers?.folio?.postMessage({ type: 'dismissSuggested', name: suggested });
      suggestFile(null);
    });
    view.append(chip, attach, dismiss);
    body.prepend(view);
  }

  let scheduled = false;
  function scheduleRefresh() {
    if (scheduled) return;
    scheduled = true;
    // A timer rather than requestAnimationFrame, which stalls while the window is hidden.
    setTimeout(() => {
      scheduled = false;
      adoptDraft();
      syncTray();
      syncSuggestion();
      renderMessages(document);
      watchSend();
      if (location.pathname !== healthPath) {
        // A new page or route: check once it has had time to settle.
        healthPath = location.pathname;
        clearTimeout(healthTimer);
        healthTimer = setTimeout(checkHealth, 3000);
      }
    }, 50);
  }

  new MutationObserver(scheduleRefresh).observe(document.documentElement, {
    childList: true,
    subtree: true,
    characterData: true,
  });
  scheduleRefresh();

  window.__folio = {
    attachFile,
    hasFile,
    suggestFile,
    insertText,
    addSelection,
    revealQuote,
    clearSelections,
    flushSelections,
    pendingSelections: () => pending.length,
    composerText,
    removeText,
    signedOut,
    focusComposer,
    startNewChat,
    probe,
    checkHealth,
    state: (name) => {
      const s = signature();
      return `${filesInComposer(name)}|${s.nodes}|${s.text.length}`;
    },
  };
})();
