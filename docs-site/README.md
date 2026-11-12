# Folio documentation

The Folio website: a static documentation site built from Markdown, adapted from the Findle docs site. It has local search, light and dark themes, page outlines, mobile navigation, copy actions, and a Markdown endpoint for every page.

## Run locally

Requires Node.js 22 or later.

```sh
npm ci
npm run dev
```

Open http://127.0.0.1:4320/ (change it with `PORT`). Changes in `src/`, `public/` and the build script rebuild automatically; refresh to see them.

## Validate

```sh
npm run build
npm run check
```

The site is generated into `dist/`. The check verifies internal links and anchors, assets, metadata, unique IDs, Markdown endpoints, search coverage, and that highlighted code copies exactly.

## Deploy

`npm run deploy` builds with `.env.production`, runs the check, and deploys `dist/` as the `folio-docs` Worker (static assets only, configured in `wrangler.jsonc`; sign in once with `npx wrangler login`). `pdf.amodrono.com` is its custom domain, set in `wrangler.jsonc`, which also manages the DNS record in the amodrono.com zone. `.github/workflows/pages.yml` runs it on every push to main that touches `docs-site/`, with the `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` secrets. `public/_headers` sets the response headers; unknown paths get `404.html`. The build is also at https://folio-docs.amodrono.workers.dev.

Page views go to the self-hosted Umami server at analytics.amodrono.com (website "Folio"). The tag is added only when `UMAMI_WEBSITE_ID` is set, which `.env.production` does for `npm run build:production` and `npm run deploy`; `npm run build` and `npm run dev` go without it, so local visits don't count.

## Edit

- `src/content/*.md`: the guides. `overview.md` is the homepage; its `#` heading is replaced by the hero.
- The homepage is a landing page, not a guide: no sidebar or outline. In `overview.md`, each `##` section with an image becomes a feature row (sides alternate), a section without one becomes the centered details block (its list renders as cards), and the last section becomes the closing call to action. `landing()` in `scripts/build.mjs` does this.
- Hero backdrop: `public/images/hero/valley.webp` (a painted mountain valley, 1308 × 736; `aspect-ratio` on `.hero-backdrop` in `styles.css` must match). The shader at the end of `src/app.js` blurs it (`BLUR`), pixelates it (`CELL`), adds ordered dithering and grain, and dissolves its bottom edge behind the film. It draws once per resize, with no animation loop. Without WebGL the `<img>` shows, scaled up with pixelated sampling. Dark mode dims it with a CSS filter.
- `public/images/screens/*.webp`: homepage screenshots, 2000 × 1250 frames from the launch film's takes (`../marketing/promo/public/crono/<take>/video.mp4`), converted with `cwebp -q 82`.
- `scripts/build.mjs`: navigation, hero, shared layout, Markdown rendering, search index.
- `src/styles.css`, `src/syntax.css`: layout and light/dark themes.
- `src/app.js`: search, keyboard controls, theme, copy actions, navigation, outlines.
- `public/images/folio-icon.png` (512 px) and `folio-icon-small.png` (64 px): the app icon, rendered from `Folio/Resources/AppIcon.icon`. Re-export them when the icon changes.

Every page has an HTML route and a Markdown endpoint (`/quickstart/` and `/quickstart.md`). `/llms.txt` lists the guides.

## Demo video

`public/videos/folio-demo.mp4` is the launch film (`../marketing/promo/out/folio-1.0.mp4`) re-encoded for the web: `ffmpeg -i folio-1.0.mp4 -c:v libx264 -preset slow -crf 28 -tune film -pix_fmt yuv420p -r 30 -c:a aac -b:a 128k -movflags +faststart folio-demo.mp4` (about 17 MB). The poster is the film's title card at 13.4 s. To replace it, save a recording as `public/videos/folio-demo.mp4` (or `.webm`) and rebuild. It appears on the homepage under the hero, where the `<!-- folio-demo -->` marker is. Optional: `folio-demo-poster.jpg|png|webp` and `folio-demo.en.vtt` captions.

## Content rules

Keep the guides in step with the app's labels and behavior; the source wins over the README when they differ. Say Folio isn't affiliated with OpenAI wherever it's presented, and use "ChatGPT" only to name the service (see `../docs/openai-terms.md`).
