#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/atlas-clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="${TMPDIR:-/tmp}/atlas-swift-cache"
swift test --build-system native --cache-path "${TMPDIR:-/tmp}/atlas-spm-cache" --config-path "${TMPDIR:-/tmp}/atlas-spm-config" --security-path "${TMPDIR:-/tmp}/atlas-spm-security" --disable-sandbox
