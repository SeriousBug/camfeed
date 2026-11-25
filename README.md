# Camfeed

Publishes an iPhone Continuity Camera to macOS as a regular camera device, so FaceTime, Chrome, Meet and anything else using AVFoundation can select it.

Two targets in one Xcode project:

- `dev.bgenc.camfeed` is a menu bar app. It runs an `AVCaptureSession` on the iPhone camera and writes frames into a shared memory ring.
- `dev.bgenc.camfeed.camera` is a CoreMediaIO camera extension. It publishes one device with one BGRA stream and forwards whatever the app wrote into the ring.

There is no scene composition, no encoder, no audio. The stream formats the extension advertises are 1920x1080, 1280x720 and 960x540 at 30 fps.

## Requirements

- macOS 14 or later
- An iPhone available to Continuity Camera
- The app must live in `/Applications` for macOS to accept the extension

## Build

```sh
Scripts/build-dmg.sh                     # signed DMG in build/Camfeed.dmg
Scripts/build-dmg.sh --notarize camfeed  # also notarize and staple, needs a stored notarytool profile
```

The script archives, exports with Developer ID signing, verifies both signatures and packs a DMG at `build/Camfeed.dmg`.

To iterate without the DMG:

```sh
xcodebuild -project Camfeed.xcodeproj -scheme Camfeed -configuration Debug build
```

## Install and enable

1. Open the DMG and drag Camfeed to `/Applications`.
2. Launch Camfeed. It asks for camera access and submits the camera extension for activation.
3. Approve it in System Settings › General › Login Items & Extensions › Camera Extensions. This asks for the administrator password.
4. Restart any app that was already running, so it picks up the new camera.

## Using it

The menu bar icon shows what is being published. The camera submenu lists the cameras Camfeed can capture, Continuity Cameras first; picking one starts feeding it to the extension. When no feed is arriving, clients see Camfeed's own idle frame instead of a black screen.

`Show Log` opens the shared container, where `camfeed.log` records extension activation, capture state and stream activity.

## How frames move

`Shared/CamfeedRing.{h,c}` maps a file of four 1920x1080 BGRA slots in `~/Library/Group Containers/63QQLP356Q.dev.bgenc.camfeed/`. The app crops to the aspect ratio of the format the extension published, scales into a free slot with vImage and bumps a sequence number. The extension reads the newest complete slot and wraps its bytes in a `CVPixelBuffer` without copying.

The extension publishes the format that the client selected through the same header, so the app always produces frames at the size the client negotiated.

## Known limits

- The ring has no flow control beyond the four slots; a client that falls more than 100 ms behind sees a newer frame than the one it asked for.
- iPhone controls (zoom, focus, exposure, torch) are not wired up yet.
- The idle frame is redrawn only when the stream format changes.

## Two things macOS insists on

The extension bundle directory must be named exactly `<CFBundleIdentifier>.systemextension`. Any other name makes `OSSystemExtensionRequest` fail before it leaves the app with `Extension not found in App bundle`.

The build must be notarized. An unnotarized Developer ID extension is listed by `systemextensionsctl` but activation fails with `code signature invalid`, while `spctl` reports `rejected, source=Unnotarized Developer ID`. Notarizing the DMG covers the app and the nested extension; stapling the app is not needed, OBS ships without it too.

