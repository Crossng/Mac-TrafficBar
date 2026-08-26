#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

VERSION="${TRAFFICBAR_VERSION:-$(tr -d '[:space:]' < VERSION)}"
TRAFFICBAR_VERSION="$VERSION" scripts/package-release.sh

if [[ -n "${TRAFFICBAR_GITHUB_REPOSITORY:-}" ]]; then
    gh release create "v$VERSION" dist/TrafficBar-macos-*.dmg dist/TrafficBar-macos-*.tar.gz dist/appcast.xml \
        --repo "$TRAFFICBAR_GITHUB_REPOSITORY" \
        --title "流量管家 $VERSION" \
        --generate-notes
fi
