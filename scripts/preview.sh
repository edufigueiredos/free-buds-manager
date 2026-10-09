#!/bin/bash
# Renders the screens to build/preview/*.png using sample data (no earbuds needed).
set -euo pipefail
cd "$(dirname "$0")/.."
swift build --product FreeBudsPreview
.build/debug/FreeBudsPreview build/preview
