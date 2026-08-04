# CineBar 0.8.3-test.12 (Build 28) installation guide

This is a test build for macOS 13 Ventura or later. The application bundle uses
ad-hoc code signing only: it is not signed with an Apple Developer ID
certificate, is not notarized, and is not a stable release. Download only the
complete CineBar test ZIP supplied by the developer, move `CineBar.app` to
Applications, then Control-click it and choose **Open** for the first launch.
Do not run it permanently from the ZIP or Downloads folder.

## Local Library

1. Open **Local Library**, choose **Add Folder**, and grant macOS permission to
   access a folder containing your video files.
2. Choose **Refresh** to scan it. Videos added to an authorized folder appear
   after the next refresh. Movie and TV filenames are classified conservatively;
   camera, screen-recording, and other personal clips remain under **Other
   Videos**. Content categories can be combined with status filters.
3. TMDB search produces suggestions only. For a movie or TV file, you can enter
   a title manually and choose **Confirm Match** before CineBar changes metadata.
   Initial suggestions and manual searches share one cancellable request path.
   Closing, confirming, or starting another search prevents late results from
   replacing the current entry.
4. Choose **View Details** to open the full existing Movie or TV details for a
   confirmed match. Unmatched and Other Videos show file-only details without
   invented external ratings, cast, stills, or trailers. A valid confirmed title
   with no TMDB release or first-air date still opens the existing full details.
5. Playback is local: CineBar tries IINA, then VLC, then the macOS default
   player. Already scanned files can still play without a network connection.

CineBar does not upload your local videos and does not provide downloads,
pirated sources, or torrent links. If a removable volume is disconnected, a
file moves, or access is revoked, reconnect the volume, grant folder access
again, and use **Relocate File** when needed.

## Updating and troubleshooting

Build 28 has a signed appcast and immutable archive, so CineBar can check,
download, and install it as an in-app update. A direct download remains available
at `https://cinebar.cc/downloads/CineBar-0.8.3-test-build-28-universal.zip`.
The Sparkle EdDSA update signature verifies the downloaded archive. It is
separate from the app's ad-hoc code signature and does not provide Apple
Developer ID signing or Apple notarization. If CineBar reports no local videos,
verify the selected folder's permission and use **Refresh**. If a player does
not launch, install IINA or VLC, or set a compatible macOS default player.
