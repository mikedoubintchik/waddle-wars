#!/bin/zsh
# Deploy the web build to Cloudflare (R2 bucket + Worker).
# Usage: tools/deploy_cloudflare.sh
#
# Cloudflare Pages cannot host this build (25 MiB per-file cap vs a ~38 MiB
# WASM blob), so the files live in R2 and web-host/src/worker.js serves them.
set -e
cd "$(dirname "$0")/.."

source /Users/ninja/Work/ninja-consulting-ai/.local/deploy.env
# Absolute: the worker deploy below runs from web-host/, where a relative path
# to the leaderboard's node_modules would not resolve.
WRANGLER="$PWD/leaderboard/node_modules/.bin/wrangler"

# Stamp the build so a screenshot can say which code it is. Restored after the
# export so the working tree is not left dirty by a deploy.
BUILD_ID=$(git rev-parse --short HEAD)
CONFIG="scripts/utilities/game_config.gd"
cp "$CONFIG" "$CONFIG.bak"
sed -i '' "s/^const BUILD_ID: String = \".*\"/const BUILD_ID: String = \"$BUILD_ID\"/" "$CONFIG"

godot --headless --export-release "Web" build/web/index.html

command mv -f "$CONFIG.bak" "$CONFIG"
command cp -f web/share.png build/web/share.png

# Version the game data's URL so a browser CANNOT serve a stale copy.
#
# Correct cache headers were not enough. The origin and the edge were both
# serving the current build with `max-age=0, must-revalidate` and answering
# conditional requests properly, and a phone still ran code from several
# deploys earlier -- three bug reports in a row turned out to be that. Rather
# than keep trying to persuade a client to revalidate, the URL now changes
# whenever the data does: index.html is revalidated (it is small), and it
# points at index.pck?v=<hash>, which has never been fetched before and so
# cannot be in any cache.
python3 - "$BUILD_ID" <<'PYBUST'
import io, re, sys
build = sys.argv[1]
p = "build/web/index.html"
s = io.open(p, encoding="utf-8").read()
pack = "index.pck?v=%s" % build
# Point the loader at the versioned URL.
s = s.replace('"executable":"index"', '"executable":"index","mainPack":"%s"' % pack, 1)
# The loader reads the download size by URL; give it the versioned key too so
# the progress bar stays accurate instead of silently falling back to zero.
m = re.search(r'"index\.pck":(\d+)', s)
if m:
    s = s.replace(m.group(0), '%s,"%s":%s' % (m.group(0), pack, m.group(1)), 1)
io.open(p, "w", encoding="utf-8").write(s)
print("cache-busted pack URL -> %s" % pack)
PYBUST

content_type() {
  case "$1" in
    *.html) echo "text/html; charset=utf-8" ;;
    *.js)   echo "text/javascript; charset=utf-8" ;;
    *.wasm) echo "application/wasm" ;;
    *.png)  echo "image/png" ;;
    *.webp) echo "image/webp" ;;
    *.ico)  echo "image/x-icon" ;;
    *.webmanifest) echo "application/manifest+json" ;;
    *)      echo "application/octet-stream" ;;
  esac
}

# CNAME is a GitHub Pages artifact and must not be served here.
# The installable-app files ride along with the build: without the manifest
# and its icons a phone can only ever open the game in a browser tab, where
# the URL bar eats a chunk of the viewport and resizes it mid-session.
cp web/manifest.webmanifest web/icon-192.png web/icon-512.png \
  web/icon-maskable-512.png web/favicon-16.png web/favicon-32.png \
  web/favicon-48.png web/favicon.ico web/apple-touch-icon.png build/web/ 2>/dev/null || true
cp web/loader-*-v3.webp build/web/

for f in build/web/index.* build/web/share.png build/web/manifest.webmanifest \
  build/web/icon-*.png build/web/favicon-*.png build/web/favicon.ico \
  build/web/apple-touch-icon.png build/web/loader-*-v3.webp; do
  b=$(basename "$f")
  echo "uploading $b"
  $WRANGLER r2 object put "waddle-wars-web/$b" --file "$f" \
    --content-type "$(content_type "$b")" --remote >/dev/null
done

(cd web-host && $WRANGLER deploy)

echo "live: https://waddle-wars-web.ninjaconsultingllc.workers.dev"
