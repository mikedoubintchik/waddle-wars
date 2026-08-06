# Cloudflare static host (outage-proof deploy path)

Serves the Godot web export from an R2 bucket through a tiny Worker.

**Why this exists:** GitHub Pages went down mid-development (Actions + Pages
major outage, 2026-08-06) and stopped publishing entirely. Cloudflare Pages
was not an option either — it rejects files over 25 MiB and the engine WASM
is ~38 MiB. R2 has no per-file cap, so the build lives in a bucket and this
Worker serves it.

Live: https://waddle-wars-web.ninjaconsultingllc.workers.dev

## Deploy

```sh
tools/deploy_cloudflare.sh
```

Exports the web build, uploads the changed files to the `waddle-wars-web`
bucket, and redeploys the Worker. Needs `CLOUDFLARE_API_TOKEN` +
`CLOUDFLARE_ACCOUNT_ID`, sourced from the ninja-consulting deploy env.

## The vanity domain

`waddlewars.ninjaconsulting.ai` is bound to this Worker as a Custom Domain
(Workers → waddle-wars-web → Triggers → Custom Domains), which manages its own
proxied DNS record and certificate. The GitHub Pages CNAME it used to point at
is gone, the Pages custom domain is cleared and the `gh-pages` branch is
deleted, so this Worker is the only thing serving the game.
