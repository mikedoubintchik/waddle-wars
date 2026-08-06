#!/bin/zsh
# Deploy the web build to GitHub Pages (gh-pages branch).
# Usage: tools/deploy_web.sh "commit message"
# Note: GitHub Pages caches assets for 10 minutes (Cache-Control max-age=600).
# Players who loaded the game within that window need a hard refresh.
set -e
cd "$(dirname "$0")/.."

MSG="${1:-Deploy web build}"

godot --headless --export-release "Web" build/web/index.html
command cp -f web/share.png build/web/share.png
command cp -f web/CNAME build/web/CNAME
grep -q "waddlewars.ninjaconsulting.ai" build/web/CNAME

cd build/web
git add -A
git -c commit.gpgsign=false commit -m "$MSG" || true
git push -f git@github.com:mikedoubintchik/waddle-wars.git HEAD:gh-pages

# Wait for the CDN to serve the new build.
local_md5=$(md5 -q index.pck)
for i in 1 2 3 4 5 6 7 8; do
  live_md5=$(curl -s "https://waddlewars.ninjaconsulting.ai/index.pck?cb=$(date +%s)" | md5 -q)
  if [ "$local_md5" = "$live_md5" ]; then
    echo "LIVE-MATCH after $i checks"
    exit 0
  fi
  sleep 15
done
echo "WARNING: live index.pck still stale after 2 minutes" >&2
exit 1
