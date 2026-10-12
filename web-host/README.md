# Cloudflare static host (outage-proof deploy path)

Serves the Godot web export from an R2 bucket through a tiny Worker.

**Why this exists:** GitHub Pages went down mid-development (Actions + Pages
major outage, 2026-08-06) and stopped publishing entirely. Cloudflare Pages
was not an option either — it rejects files over 25 MiB and the engine WASM
is ~38 MiB. R2 has no per-file cap, so the build lives in a bucket and this
Worker serves it.

Live game: https://play.waddlewars.io/
Public home: https://waddlewars.io/

Production health, gameplay counters, scheduled probes, and the email alert
are documented in [MONITORING.md](MONITORING.md).

## Deploy

```sh
tools/deploy_cloudflare.sh
```

Exports the web build, uploads the changed files to the `waddle-wars-web`
bucket, and redeploys the Worker. Needs `CLOUDFLARE_API_TOKEN` +
`CLOUDFLARE_ACCOUNT_ID`, sourced from the ninja-consulting deploy env.

## Domains and public pages

`waddlewars.io` serves `web/oauth-home.html` at `/`. `play.waddlewars.io`
serves the Godot `index.html`; the older `waddlewars.ninjaconsulting.ai`
hostname remains an alias. The Worker reads all three from the same R2 bucket.
`www.waddlewars.io` redirects to the apex.

The apex also serves `web/sitemap.xml`, browser and mobile information pages,
favicons, touch icon, and social artwork. Upload changed static source files to
matching R2 keys with their HTML, XML, PNG, ICO, or webmanifest MIME types;
deploy the Worker when its MIME map or routing changes. Verify public HTTPS
response bytes after publication. The game export deployment keeps these R2
objects in place and includes current favicon and PWA assets with new builds.

## Website feedback

Homepage and in-game feedback forms post to `POST /api/feedback` on `waddlewars.io`.
The in-game form is under Base Camp → Feedback and Pause → Send Feedback.
It preserves a paused run, accepts an optional reply email, and includes only
the build ID and platform with the player's category and message. No saves,
tokens or screenshots are attached. Success appears only after SES accepts
the message; timeout/errors preserve the draft for an explicit retry.
Worker validates input and origin, uses a five-per-minute rate limit per
Cloudflare client IP, and sends mail through SES to `support@waddlewars.io`. AWS IAM
credentials are Worker secrets `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`;
never put them in repository or Wrangler vars. SES identity
`waddlewars.io` must remain verified in `us-east-1`.
IAM user `waddle-wars-feedback-ses`, inline policy `SendWaddleFeedbackOnly`,
restricts `ses:SendEmail` to the `waddlewars.io` identity with both FromAddress
and Recipients equal to `support@waddlewars.io`. Keep that recipient condition
in sync with `FEEDBACK_TO_EMAIL`; changing only the Worker variable causes SES
to reject messages. The support address forwards through the existing mailbox
routing. No AWS key rotation or additional permissions are needed for this form.
The allowlist covers the apex, `play.waddlewars.io`, and the legacy game
hostname. Browser preflight and error responses carry the matching CORS origin;
native clients send the game origin header. An origin header is not authentication.

Run `node --test web-host/src/feedback.test.mjs` before deployment. Upload
`web/oauth-home.html` and `web/oauth-privacy.html` to matching R2 keys, then
deploy `web-host` Worker. Verify homepage, privacy copy, and one real form
submission.
