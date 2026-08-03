# CineBar 0.8.3-test.8 (Build 24) installation guide

This is a test build for macOS 13 Ventura or later. It is not notarized and is
not a stable release. Download only the complete CineBar test ZIP supplied by
the developer, move `CineBar.app` to Applications, then Control-click it and
choose **Open** for the first launch. Do not run it permanently from the ZIP or
Downloads folder.

## Local Library

1. Open **Local Library**, choose **Add Folder**, and grant macOS permission to
   access a folder containing your video files.
2. Choose **Refresh** to scan it. Videos added to an authorized folder appear
   after the next refresh.
3. TMDB search produces suggestions only. Review them and choose **Confirm Match**
   before CineBar changes a title's metadata.
4. Playback is local: CineBar tries IINA, then VLC, then the macOS default
   player. Already scanned files can still play without a network connection.

CineBar does not upload your local videos and does not provide downloads,
pirated sources, or torrent links. If a removable volume is disconnected, a
file moves, or access is revoked, reconnect the volume, grant folder access
again, and use **Relocate File** when needed.

## Updating and troubleshooting

Build 24 has a signed appcast and immutable archive, so CineBar can check,
download, and install it as an in-app update. A direct download remains available
at `https://cinebar.cc/downloads/CineBar-0.8.3-test-build-24-universal.zip`.
The update package is independently signature-checked, which is separate from
Apple notarization. If CineBar reports no local videos, verify the selected
folder's permission and use **Refresh**. If a player does not launch, install
IINA or VLC, or set a compatible macOS default player.
