# Waddle Wars production search and analytics

Checked October 11, 2026.

## Search

- Search Console domain property: `sc-domain:waddlewars.io` in the owner Google account. Homepage and `play.waddlewars.io/` both report indexed and HTTPS. The sitemap report says Success.
- Public sitemap: `https://waddlewars.io/sitemap.xml`. It lists six canonical public URLs, including the browser game. Resubmit after a major URL change; routine content changes do not need a new submission.
- Homepage has a self canonical, description, Open Graph/Twitter image, and JSON-LD for the publisher, site, browser game, and released Android game.
- Game root declares `https://play.waddlewars.io/` through the HTTP `Link` canonical header, including 304 responses. Staged release HTML gets `X-Robots-Tag: noindex`.
- Cloudflare-managed `robots.txt` permits search crawling. Search Console has the sitemap directly; a `Sitemap:` line in robots is optional.
- Google's Rich Results Test crawled the homepage successfully but found no eligible items. Google's Software App rich result requires a genuine rating or review in addition to the app name and offer; none is asserted on this new release. Keep the schema accurate and add review data only when real, eligible reviews exist.
- Search Console Core Web Vitals has insufficient field data at this traffic level. Review when data arrives.
- PageSpeed mobile lab audit before image optimization: Performance 79, Accessibility 100, Best Practices 100, SEO 100; LCP 5.7 s. First WebP pass reached mobile LCP 2.0 s. The final page preloads a responsive hero: 32 KiB AVIF for phones, 57 KiB AVIF for larger screens, WebP and PNG fallbacks. Published [October 11 retest](https://pagespeed.web.dev/analysis/https-waddlewars-io/7pss3ours2?form_factor=mobile): mobile 99/100/100/100, FCP 1.546 s, LCP 1.547 s; desktop 100/100/100/100, FCP/LCP 0.428 s. LCP is now the hero image and effectively coincides with first paint in the emulated slow 4G mobile test. These are lab results; no field data exists yet.

## Measurement

- Cloudflare Web Analytics property `waddlewars.io` auto-injects its beacon. Its dashboard showed active traffic during the audit. No GA4 cookie or Google Analytics tag is installed.
- Homepage sends one first-party event for each user click on the browser-play or Google Play links. Links keep their direct destinations even when the beacon fails. Event fields are limited to `play_browser`/`google_play` and `nav`/`hero`/`mobile` placement.
- Worker validates origin and event fields, limits requests to 30 per minute per source IP, then writes only event and placement to Workers Analytics Engine dataset `waddle_wars_cta_clicks`. IP is used for temporary rate limiting and is not stored in the dataset. The browser privacy page discloses this.
- For CTA totals, query the dataset with Cloudflare Analytics SQL using `SELECT blob1 AS destination, blob2 AS placement, SUM(_sample_interval) AS clicks FROM waddle_wars_cta_clicks WHERE timestamp >= NOW() - INTERVAL '30' DAY GROUP BY destination, placement ORDER BY clicks DESC`. `clicks` measures outbound intent, not Google Play installs.
- Verified production write and query with one real Google Play hero click. Studio returned `google_play / hero / 1`.
- Existing game telemetry lives in the separate `waddle_wars_game_events` dataset. Keep event schemas separate.

## Operational checks

1. After Worker deployment, verify homepage, game root, feedback endpoint, game health endpoint, canonical/noindex headers, and sitemap over public HTTPS.
2. Open homepage in a real browser; confirm Cloudflare Web Analytics beacon and a successful CTA event request. Check dataset readback after propagation.
3. After significant site edits, inspect both Search Console URLs and the sitemap report. Indexing and rich results may lag publication.
