# Camfeed

Your iPhone camera, as a normal camera in any Mac app.

A menu bar app captures the iPhone Continuity Camera and a CoreMediaIO camera extension publishes it as **Camfeed Camera**. No scenes, no encoder, no audio.

## Install

1. Download `Camfeed.dmg` from [Releases](../../releases/latest) and drag Camfeed to `/Applications`.
2. Open Camfeed and grant camera access.
3. Approve the camera extension in System Settings › General › Login Items & Extensions › Camera Extensions.
4. In any app, pick **Camfeed Camera**.

Requires macOS 14 or later.

The iPhone is only connected while an app is using the camera. When nothing is watching, Camfeed shows its own idle frame.

## Development

See [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md). MIT licensed, see [LICENSE](LICENSE).
