#!/bin/zsh
set -e
cd "$(dirname "$0")/../.."
godot --headless --path "$PWD" --script res://tools/site/build_brand_assets.gd
magick web/favicon-16.png web/favicon-32.png web/favicon-48.png web/favicon.ico
