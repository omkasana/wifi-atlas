# Architecture and source map

WiFi Atlas is a local macOS app with two Swift Package targets and an optional Xcode-built WidgetKit extension. The deployment target is macOS 14 and the bundled executable is arm64.

## Modules and responsibilities

| Component | Source | Responsibility |
| --- | --- | --- |
| Shared core | `Sources/AtlasCore/Models.swift` | Codable measurement/layout/survey models, strength conversion, counter deltas, statistics, survey suggestions, room-constrained interpolation, CSV, suitability guidance, and widget snapshot types |
| App entry and screens | `Sources/WiFiAtlas/WiFiAtlasApp.swift` | Scenes, navigation, dashboard, meters/charts, speed tests, history, connection tools, menu bar, and Settings |
| Application state | `Sources/WiFiAtlas/AppStore.swift` | Main-actor observable state, polling, task cancellation, route changes, surveys, persistence triggers, notifications, and shared widget snapshots |
| Hardware / persistence / throughput | `Sources/WiFiAtlas/Services.swift` | `WiFiService`, `LocalRepository`, `HTTPTransport`, and `SpeedService` |
| Activity counters | `Sources/WiFiAtlas/TrafficService.swift` | Read 64-bit statistics for a selected physical interface and derive actual traffic rates |
| Connection information | `Sources/WiFiAtlas/ConnectionInfo.swift` | Read-only CoreWLAN/SystemConfiguration details; friendly formatting and optional public-IP response parsing |
| Information panel | `Sources/WiFiAtlas/ConnectionInfoView.swift` | Selectable/copyable local details and explicit external IP lookup |
| Layouts and reports | `Sources/WiFiAtlas/SurveyView.swift` | Room editing, router/door markers, guided spots, heatmap rendering, comparisons, and CSV/PNG/PDF exports |
| Floating panels | `Sources/WiFiAtlas/Panels.swift` | Panel lifecycle/position restoration, visual preferences, and menu bar sparklines |
| Developer preview | `Sources/WiFiAtlas/Preview.swift` | Explicit fixture-only dashboard rendering, bypassing the live app archive and monitoring |
| System widget | `WidgetExtension/AtlasWidgets.swift` | Configurable connection/test/survey summaries using WidgetKit/App Intents |

## Data flow and concurrency

`AppStore` is the main-actor owner of display state. It orchestrates services and publishes small snapshots to SwiftUI. CoreWLAN radio readings provide signal and link details; they do not measure internet throughput.

`TrafficService` samples the selected physical interface using public Darwin routing statistics. `CounterTracker` converts byte deltas with monotonic time and resets baselines across sleep/interface changes. Never sum physical and VPN interfaces, which would double-count traffic.

`SpeedService` runs bounded latency/download/upload phases through `SpeedTransport`. `HTTPTransport` uses an ephemeral URLSession and a serial delegate queue, counting streamed bytes rather than retaining download bodies. Delegate state is lock-protected; display updates hop back to the main actor. A short rate window and a four-per-second display cap keep live meters useful without frame-rate polling. Cancellation, request timeouts, and an overall deadline stop transfers. Test traffic is separate from passively measured activity in the UI’s labels.

Network scans and connection-info reads run away from the main executor. Connection-info generations reject stale completions after observed network changes. No scan or public-IP request is triggered by routine local-information reads.

## Service interfaces

- `WiFiMonitoring`: current radio readings and on-demand nearby-network scans.
- `SpeedTesting`: bounded tests and cancellation; `SpeedService.onUpdate` supplies streaming display updates.
- `SpeedTransport`: transfer/cancel contract plus byte-progress callbacks. Tests substitute fake transports, including stalled and streaming responses.
- `TrafficMonitoring`: interface sample/reset boundary.
- `SurveyRepository`: load/save the archive. `LocalRepository` supplies Core Data storage and can use a temporary directory or in-memory store for checks.

Keep public/shared core types independent of app UI, network permissions, and signing. New views should consume `AppStore`/shared types rather than starting duplicate polling loops.

## Survey lifecycle

1. A `Space` holds floors, each with a mutable layout draft and survey sessions.
2. `SurveyPlanner` creates room-center and inset-corner suggestions, ordered from the first router marker.
3. A guided session receives an immutable `LayoutSnapshot`, its own planned spots, and a test profile.
4. The user confirms a spot; signal readings continue during settling and the speed test.
5. Only completed stationary captures become `SurveyPoint` records and mark their planned spot complete.
6. Pause/cancel/disconnect preserves finished points. The next unskipped, incomplete spot determines resume position; no automatic indoor positioning is attempted.
7. Heatmap layers interpolate measurements within the saved room geometry. Router/door annotations never fabricate coverage. Later draft changes cannot move historical samples.

Mesh roaming uses the logical network name where available, while readings preserve BSSID. If identifiers are withheld, network identity is less reliable. Comparisons use nearby normalized coordinates and therefore require matching geometry.

## Persistence and privacy boundaries

Core Data stores a Codable `Archive` payload, with external storage enabled for large binary payloads. Its location is `~/Library/Application Support/WiFiAtlas/Atlas.sqlite`. Archive version 2 adds guided survey geometry/progress. Version-1 data is backed up to `Atlas-v1-backup.json` before migration; unknown newer versions are rejected.

User defaults hold appearance/widget preferences. Imported plans and saved measurements live only in the local archive unless a user exports them. Connection-information snapshots and public-IP results are transient; do not add addresses or credentials to history or widget payloads inadvertently.

The widget extension reads only `widget.json` from the configured App Group. Snapshots have timestamps and last-test timestamps. The extension does not open the Core Data database, read Wi-Fi hardware, or run a speed test. WidgetKit controls when the snapshot is refreshed.

## Build entry points

| Command/file | Result |
| --- | --- |
| `scripts/build.sh` | SwiftPM release/debug app, icon, ad hoc or supplied Developer ID signature; no system extension |
| `scripts/build-xcode.sh` | Full app with embedded widget extension, using a configured signing team |
| `scripts/test-standalone.sh` | Real core/service tests with a small assertion adapter instead of XCTest |
| `scripts/test.sh` | Same test cases through SwiftPM/XCTest with full Xcode |
| `scripts/generate-xcode-project.py` | Deterministic project/scheme generation from app sources and shared core package |
| `scripts/icon.swift` | Code-generated bitmap icon representations and ICNS container |
| `scripts/release.sh` | Signed/notarized app and DMG using existing local signing/notarization credentials |
| `.github/workflows/ci.yml` | Unsigned-publication-free CI checks, app build, widget type-check, and project consistency |

The Xcode project is checked in for convenience, but the generator is its source of truth. Keep its file list/configuration in sync after adding app source files. The system widget and app must share an entitled group and compatible signing identity.

## Practical extension points

- Add a metric: introduce its core type/calculation, service sampling, AppStore state, friendly presentation, and deterministic checks.
- Change speed providers: isolate endpoint and measurement changes behind `SpeedTransport`/`SpeedService`, disclose the destination, and retain bounds/cancellation.
- Improve room planning: update core planner/geometry and interpolation tests before changing editor interactions; preserve historical layout snapshots.
- Change stored data: maintain backward decoding, migrate explicitly, retain an original backup, and test reopening the disk store.
- Add widgets: extend the small shared snapshot and WidgetKit configuration; do not make the extension a second monitoring process.

There are no third-party Swift package dependencies or bundled Apple font files. `DESIGN.md` is visual inspiration; native macOS behavior takes precedence over its web-oriented component examples.
