#!/bin/zsh
# Deploy the web build to Cloudflare (R2 bucket + Worker).
# Usage: tools/deploy_cloudflare.sh
#
# Cloudflare Pages cannot host this build (25 MiB per-file cap vs a ~38 MiB
# WASM blob), so the files live in R2 and web-host/src/worker.js serves them.
set -e
cd "$(dirname "$0")/.."

source /Users/ninja/Work/ninja-consulting-ai/.local/deploy.env
WRANGLER=leaderboard/node_modules/.bin/wrangler

godot --headless --export-release "Web" build/web/index.html
command cp -f web/share.png build/web/share.png

content_type() {
  case "$1" in
    *.html) echo "text/html; charset=utf-8" ;;
    *.js)   echo "text/javascript; charset=utf-8" ;;
    *.wasm) echo "application/wasm" ;;
    *.png)  echo "image/png" ;;
    *)      echo "application/octet-stream" ;;
  esac
}

# CNAME is a GitHub Pages artifact and must not be served here.
for f in build/web/index.* build/web/share.png; do
  b=$(basename "$f")
  echo "uploading $b"
  $WRANGLER r2 object put "waddle-wars-web/$b" --file "$f" \
    --content-type "$(content_type "$b")" --remote >/dev/null
done

(cd web-host && $WRANGLER deploy)

echo "live: https://waddle-wars-web.ninjaconsultingllc.workers.dev"
