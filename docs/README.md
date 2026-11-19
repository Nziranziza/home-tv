# HomeTV docs

The documentation site, built with [Astro Starlight](https://starlight.astro.build) and deployed to Cloudflare.

```sh
cd docs
npm install
npm run dev      # http://localhost:4321
npm run build    # static site in dist/
```

Requires Node 22.23.4 or later (`.node-version` pins the version Cloudflare builds with).

- Pages live in `src/content/docs/`. Add new pages to the sidebar in `astro.config.mjs`.
- Screenshots go in `src/assets/screenshots/`, taken from the tvOS Simulator at 1920×1080
  (`xcrun simctl io booted screenshot`).

## Deployment

Cloudflare Workers Builds deploys from this repo:

| Setting | Value |
| --- | --- |
| Root directory | `docs` |
| Build command | `npm run build` |
| Deploy command | `npx wrangler deploy` |
| Non-production branch deploy command | `npx wrangler versions upload` |
| Build watch paths | include `docs/**` |

`main` deploys to production; other branches get a preview URL posted on their PR.
