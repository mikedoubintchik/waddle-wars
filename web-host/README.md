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

## Pointing the vanity domain here

`waddlewars.ninjaconsulting.ai` still resolves to GitHub Pages. To move it,
add a custom domain to this Worker in the Cloudflare dashboard (Workers →
waddle-wars-web → Triggers → Custom Domains) and drop the GitHub Pages CNAME.
