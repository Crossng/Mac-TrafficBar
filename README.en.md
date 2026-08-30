<p align="center">
  <img src="Resources/TrafficBarIcon.png" width="132" height="132" alt="TrafficBar app icon">
</p>

<h1 align="center">TrafficBar</h1>

<p align="center">Understand your Mac's real-time network speed, traffic destinations, and app usage at a glance.</p>

<p align="center">
  <a href="https://github.com/Crossng/Mac-TrafficBar/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/Crossng/Mac-TrafficBar?display_name=tag&amp;style=flat-square&amp;color=4aa3f0"></a>
  <img alt="macOS 13 or later" src="https://img.shields.io/badge/macOS-13%2B-1d1d1f?style=flat-square&amp;logo=apple&amp;logoColor=white">
  <img alt="Apple Silicon" src="https://img.shields.io/badge/chip-Apple%20Silicon-45cfa5?style=flat-square">
  <a href="https://github.com/Crossng/Mac-TrafficBar/actions/workflows/ci.yml"><img alt="Build status" src="https://github.com/Crossng/Mac-TrafficBar/actions/workflows/ci.yml/badge.svg"></a>
  <a href="LICENSE"><img alt="MIT License" src="https://img.shields.io/github/license/Crossng/Mac-TrafficBar?style=flat-square"></a>
</p>

<p align="center">
  <strong><a href="https://github.com/Crossng/Mac-TrafficBar/releases/latest/download/TrafficBar-macos-arm64.dmg">Download the latest release</a></strong>
  ·
  <a href="https://github.com/Crossng/Mac-TrafficBar/releases">View all releases</a>
</p>

<p align="center">
  <a href="README.md">简体中文</a>
  ·
  <strong>English</strong>
</p>

---

TrafficBar is a native macOS menu bar utility. It turns system network data into clear real-time speeds, period summaries, and per-app traffic rankings without requiring a complicated network tool.

## Features

| Feature | Description |
| --- | --- |
| Real-time network speed | View current download and upload speeds from the menu bar panel |
| Time-based statistics | Review external network usage by hour, today, this week, or this month |
| Traffic path breakdown | Separate proxied, direct, and local traffic |
| Hotspot and network accounting | Track Wi-Fi and hotspot usage separately, including this Mac's external usage during the current hotspot session |
| App rankings | See each app's download, upload, and traffic breakdown |
| Duplicate accounting protection | Compare against physical interface totals to avoid double-counting proxy cores and download apps |
| Local storage | Traffic records stay on this Mac and are never uploaded to a server |
| Automatic updates | Check for and install new releases published by this project from within the app |

## Installation

1. Download the latest [`TrafficBar-macos-arm64.dmg`](https://github.com/Crossng/Mac-TrafficBar/releases/latest/download/TrafficBar-macos-arm64.dmg).
2. Open the disk image and drag TrafficBar to Applications.
3. Launch the app, then click the up-and-down arrow icon in the menu bar to view traffic data.

If macOS blocks the first launch, open **System Settings → Privacy & Security** and choose **Open Anyway** in the Security section.

macOS 13 or later is required. The release package targets Apple Silicon Macs.

## Usage

- Use the time filter to switch between hourly, today, this week, and this month.
- Use the type filter to view external, proxied, direct, or local communication.
- When connected to a phone hotspot, check **Current hotspot · This Mac** in the overview.
- Click the refresh button at the bottom to sample traffic immediately.
- Click the folder button to open the local data directory.
- Click the download button to check for updates manually.

## Data and privacy

TrafficBar reads the local network statistics provided by macOS. It does not upload traffic records or install a system extension. The app calibrates total usage against physical interface deltas; protocol overhead that cannot be attributed to a specific process is shown separately as **Unattributed external** or **Unattributed local** traffic. Because accounting methods differ, the result may still vary slightly from an ISP bill or router statistics.

Network accounting uses an anonymous network identifier generated locally and does not store Wi-Fi names. **Current hotspot** includes only this Mac's external traffic; it does not include the phone itself or other devices connected to the same hotspot.

Daily summaries are retained for approximately 62 days at most. Individual records from the most recent hour are compacted automatically every 10 minutes. Data normally remains a few megabytes in size, depending on the number of active apps.

## Accounting definitions

- **External**: The sum of proxied and direct traffic. This is traffic leaving the Mac through a physical network interface and the default usage metric.
- **Proxied**: Traffic reaching the network through a local proxy, VPN, or TUN forwarding path.
- **Direct**: Traffic reaching the network directly without passing through a recognized proxy endpoint.
- **Local**: Communication within the Mac or the same local network. It is excluded from the external total and usually does not consume broadband or mobile data.

Version 0.5.0 preserves daily summaries from version 0.3.0 onward instead of clearing them after an upgrade. Network and hotspot sessions begin recording after the first launch of 0.5.0 and cannot be reconstructed for earlier usage.

## License

This project is released under the [MIT License](LICENSE). Third-party components and license notices are listed in [NOTICE.md](NOTICE.md) and [THIRD-PARTY-NOTICES](THIRD-PARTY-NOTICES).
