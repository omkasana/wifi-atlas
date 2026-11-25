# Using WiFi Atlas

## What the meters show

- **Wi-Fi strength:** estimated score from 0 to 100, labeled Excellent, Good, Fair, or Weak. It is a readable conversion of measured signal, not a probability of connection success. The same conversion is used throughout the app. Raw radio readings remain available under Connection Details and in CSV exports.
- **Downloading/uploading now:** actual traffic through the selected physical interface, including LAN transfers and the app’s own speed-test traffic. A quiet connection can show zero while substantial capacity remains available. Wi-Fi is the default; select an Ethernet interface in Settings if needed. Virtual/VPN interfaces are never added to physical counters.
- **Speed test:** available throughput to Cloudflare while a manual test runs. Download/upload meters and the graph update during transfers, rather than waiting for a completed result. Inactive meters are labeled Last Tested Speed with a timestamp.
- **Response time / consistency:** web-request round-trip time and variation. Lower generally feels smoother; these are not ICMP ping or measured packet loss. Call/gaming guidance uses these values and measured throughput without promising app performance.

Tests send traffic to Cloudflare, which receives your public IP. Thorough tests use up to 250 MB of payload data and 30 seconds; Quick surveys use up to 50 MB and 20 seconds per spot. Three quarters of the payload budget are available for download and the remainder is reserved for upload. Network overhead is additional. Tests can be limited before measurements stabilize; partial results are identified. No internet throughput tests run automatically in the background.

## Layout → routers → guided survey → heatmap

1. Open **Layouts** and create a named home or office. Save multiple layouts and floors; rename, duplicate, or delete them from the Layouts menu.
2. Draw rectangular rooms on the snap grid. Use Move Room and Resize Room with a drag, or click a room with Select to edit its name, location, and size. Layout edits support a bounded undo/redo history. Door markers are annotations and can be removed from the list.
3. Optionally import a PNG/JPEG or the first page of a PDF. Draw room outlines over the image; one whole-floor outline works for a simple plan. Accepted aspect ratios range from 1:4 to 4:1. Imports reset the current draft’s room/router/door annotations; Undo restores them. Historical survey snapshots remain unchanged.
4. Place at least one router or mesh point. Click a router with Select, or use its Edit button, to change its name/location. Router locations organize suggested spots; they do not simulate signal attenuation or predict speeds.
5. Choose **Plan Survey**. The app suggests each room’s center and four inset corners, ordered starting near the first router. Review the profile and the maximum time/data allowance. A ten-spot Thorough survey may use up to 2.5 GB and five minutes of testing, plus settling/walking time.
6. The guided survey highlights the next numbered spot. Move your MacBook there and choose **I’m here—start measuring**. Stay still during settling and the response/download/upload phases. Signal monitoring continues while walking and throughout each stationary test; only confirmed stationary captures become map measurements.
7. Edit, add, skip, restore, or remove unmeasured planned spots. Pause/resume whenever needed. Completed spots and remaining plans are saved after each action. After restart or sleep the survey remains paused and requires confirmation again.
8. Explore **Heatmap & Results** layers for strength, download, upload, and response. View best-to-worst spots and room averages, compare sessions at nearby coordinates, and export CSV, PNG, or a PDF report.

Measured dots are observations. Colored shading is room-constrained inverse-distance estimation, and unsupported areas stay blank. Door markers and wall materials do not affect calculations. Comparisons match positions within 3.5% of normalized plan coordinates. Use the same geometry for meaningful router-change comparisons. Different layouts are not automatically aligned.

Every new survey stores its own immutable layout/router snapshot. Later draft edits cannot relocate older measurements. A survey can span mesh access points on the same identified network; individual readings retain access-point identifiers. A network change or disconnect interrupts the current spot and preserves earlier completed spots. Without network-name permission, identifying the same logical mesh network may be unreliable.

## Appearance, widgets, and alerts

There is one native interface with System/Light/Dark appearance, accent colors, comfortable/compact spacing, and optional/reordered dashboard sections. The former technical console is removed and its old preferences are ignored. Meters have numeric accessibility alternatives and respect Reduce Motion; there are no continuous decorative effects.

**Menu bar:** choose icon-only, strength, live traffic, or a sparkline. Customize traffic ordering, Mbps/MB/s units, and popover graph/strength visibility.

**Floating panels:** open Wi-Fi strength, live activity, connection summary, or survey progress from the toolbar, menu bar, or Settings. Multiple panel types can stay open together. Resize and move them, choose opacity and always-on-top behavior, and restore their positions on the next launch.

**macOS system widgets:** the Xcode app includes a configurable small/medium WidgetKit extension. Add multiple instances and choose Connection, Last Speed Test, or Survey Progress. Widget taps open the corresponding app screen. These show timestamped snapshots; macOS controls refresh timing. They do not show second-by-second traffic, access Wi-Fi hardware, or launch speed tests. The app writes a compact snapshot to an entitled App Group; the full history database is not shared.

**Connection tools:** scan nearby networks on demand after enabling network-name access. Friendly strength labels are shown; channel/band details remain available without another mode. Scans may briefly affect connectivity. They count visible networks rather than measuring channel utilization.

**Alerts:** optional macOS notifications for a disconnect lasting five seconds or weak signal lasting thirty seconds, with a ten-minute cooldown. Notification and Location Services permissions are requested only when relevant features are enabled.

## Wi-Fi information

Expand **Connection Details** on Overview, or open **Connection Tools**, for a selectable/copyable readout of the current Wi-Fi interface:

- Local IPv4 addresses, subnet masks, IPv4/IPv6 router addresses, IPv6 prefixes, and automatic/manual address setup.
- DHCP server and lease start/expiry when macOS exposes them.
- Wi-Fi DNS servers, search domains, domain, system DNS, primary IPv4/IPv6 interfaces, and the Mac’s local hostname.
- SSID, access-point BSSID, encryption/security, Wi-Fi generation, interface/service name, reported hardware MAC, operating mode, region code, and MTU.
- Band, channel, channel width, link rate, signal/noise, signal-to-noise difference, and reported transmit power.

Local details refresh about every fifteen seconds while monitoring, after observed connection changes, or using Refresh. Reading them does not scan nearby networks or generate internet traffic. Values are runtime-only and are not added to saved history, survey exports, or widget snapshots. Copy Details explicitly places the readout on your clipboard.

**Check Public IP** is an optional Cloudflare lookup for the internet exit address of the current route. It may reflect a VPN or Ethernet connection, rather than Wi-Fi, and displays its own check time. It uses an ephemeral session and is cleared when leaving the panel or changing connection context. No lookup runs automatically.

macOS may withhold SSID/BSSID or other information without Location Services permission. Unconfigured or inaccessible fields show Unavailable. Reported hardware MAC and private Wi-Fi addresses can differ; configured DNS servers may not include every VPN/scoped resolver used for a particular request.

## Storage and migration

The app stores a versioned Codable archive in Core Data at `~/Library/Application Support/WiFiAtlas/Atlas.sqlite`. Imported plans, readings, router annotations, layouts, and surveys stay local. Routine monitoring samples default to seven-day retention (one/seven/thirty days configurable); speed tests and surveys remain until deleted. Clear History preserves surveys. Deleting a layout/floor removes its own surveys.

Version-1 archives migrate automatically to version 2 after saving `Atlas-v1-backup.json` beside the database. Existing surveys receive their current floor geometry as a historical snapshot. Unknown/newer archive versions are rejected rather than overwritten. Old layouts need router markers and a new guided survey to use the new workflow; their earlier measurements remain accessible in Results.

Polling is one second while the app, panels, speed tests, or surveys are active, and approximately ten seconds in menu-bar-only background operation. Transfer display updates are capped at four per second and rate calculations use monotonic time with a short rolling window. Live buffers are bounded. Monitoring pauses during sleep and counter baselines reset on wake/interface changes.
