# Live monitoring MVP

Production services: `waddle-wars-web` serves `waddlewars.io` and
`play.waddlewars.io`; `waddle-wars-leaderboard` serves the public game API.

## What is collected

- Browser game: `app_open`, `run_start`, `run_end`, `client_error` (scene load
  category). Dimensions: platform, build, fixed error category. Run-end totals:
  distance, score, fish. No account identifier, name, token, save, raw error,
  or IP in the analytics dataset. Requests are rate-limited by IP at ingress.
- Web Worker: Workers Logs at 100% sampling, including response status and
  fixed operational errors. Cloudflare's plan retention and allowance apply.
  Revisit sampling if daily logs approach the included allowance.
- Every five minutes: scheduled web Worker checks the two R2 entry documents
  and performs a read-only public leaderboard query (which exercises D1).

Native game analytics remain off until native privacy and store disclosures
are updated and a reviewed mobile build is released. Browser gameplay events
start with the next reviewed web game export. The Worker endpoint, health check,
scheduled probes and alert can ship independently of the game export.

## Alert and response

Cloudflare Observability → Alerts contains **Waddle Wars service failures**.
It emails `support@waddlewars.io` when the web Worker has at least one 5xx or
error-level log in five minutes; repeat interval is one hour. Scheduled probe
failures log `monitor: web_entries_unavailable`, `monitor: web_r2_unavailable`,
or `monitor: leaderboard_unavailable` with no response data. The alert depends
on Workers Logs remaining enabled.

When alerted: check [web health](https://play.waddlewars.io/api/health),
[public leaderboard](https://waddle-wars-leaderboard.ninjaconsultingllc.workers.dev/api/leaderboard?mode=runner&course=runner&limit=1),
then filter Cloudflare Workers Logs for script `waddle-wars-web` and the alert
time. If only the leaderboard fails, inspect its deployment/D1 metrics; never
deploy the development leaderboard Wrangler config to production.

## Gameplay counters

Dataset: `waddle_wars_game_events` in Workers Analytics Engine. The schema is:

| Column | Value |
| --- | --- |
| `blob1` | event |
| `blob2` | platform |
| `blob3` | build |
| `blob4` | fixed error category or empty |
| `double1` | distance on run end |
| `double2` | score on run end |
| `double3` | fish on run end |

Example seven-day query in Cloudflare Analytics Engine SQL (account analytics
read permission required):

```sql
SELECT blob1 AS event, blob2 AS platform, blob3 AS build,
       SUM(_sample_interval) AS events,
       SUM(_sample_interval * double1) AS distance_m,
       SUM(_sample_interval * double2) AS score,
       SUM(_sample_interval * double3) AS fish
FROM waddle_wars_game_events
WHERE timestamp >= NOW() - INTERVAL '7' DAY
GROUP BY event, platform, build
ORDER BY events DESC
```

Use `run_end / run_start` for run completion, `run_start / app_open` for menu to
run conversion, and `client_error / app_open` as a coarse load-failure signal.
These are event ratios, not unique-player rates. Do not infer retention or
unique users: the design deliberately carries no device or account ID.
