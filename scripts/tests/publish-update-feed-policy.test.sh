#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)
fixture=$(mktemp)
trap 'rm -f "$fixture"' EXIT

cat > "$fixture" <<'JSON'
[[
  {
    "tag_name": "v-created-last-published-first",
    "draft": false,
    "prerelease": false,
    "published_at": "2026-09-01T00:00:00Z",
    "assets": [{"name": "appcast.xml", "url": "https://api.github.test/assets/older"}]
  },
  {
    "tag_name": "v-current",
    "draft": false,
    "prerelease": false,
    "published_at": "2026-09-12T00:00:00Z",
    "assets": [{"name": "appcast.xml", "url": "https://api.github.test/assets/current"}]
  },
  {
    "tag_name": "v-created-first-published-last",
    "draft": false,
    "prerelease": false,
    "published_at": "2026-09-10T00:00:00Z",
    "assets": [{"name": "appcast.xml", "url": "https://api.github.test/assets/served"}]
  },
  {
    "tag_name": "v-newer-beta",
    "draft": false,
    "prerelease": true,
    "published_at": "2026-09-11T00:00:00Z",
    "assets": [{"name": "appcast.xml", "url": "https://api.github.test/assets/beta"}]
  }
], [
  {
    "tag_name": "v-second-page-served",
    "draft": false,
    "prerelease": false,
    "published_at": "2026-09-11T12:00:00Z",
    "assets": [{"name": "appcast.xml", "url": "https://api.github.test/assets/second-page-served"}]
  }
]]
JSON

selected=$(jq -r \
  --arg current v-current \
  --arg name appcast.xml \
  -f "$root/scripts/previous-published-feed-asset.jq" \
  "$fixture")

test "$selected" = "https://api.github.test/assets/second-page-served"
