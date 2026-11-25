#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/atlas-clang-cache"
mkdir -p .build/checks
swiftc -parse-as-library -enable-testing -emit-library -emit-module -module-name AtlasCore Sources/AtlasCore/Models.swift -emit-module-path .build/checks/AtlasCore.swiftmodule -o .build/checks/libAtlasCore.dylib -target arm64-apple-macos14.0
swiftc -parse-as-library -D ATLAS_STANDALONE_CHECKS -I .build/checks -L .build/checks -lAtlasCore -Xlinker -rpath -Xlinker @executable_path Sources/WiFiAtlas/Services.swift Sources/WiFiAtlas/ConnectionInfo.swift Tests/AtlasCoreTests/AtlasCoreTests.swift Tests/AtlasCoreTests/ServiceTests.swift Tests/AtlasCoreTests/RedesignTests.swift Tests/AtlasCoreTests/ConnectionInfoTests.swift Tests/Standalone/Runner.swift -o .build/checks/AtlasChecks -target arm64-apple-macos14.0
.build/checks/AtlasChecks
