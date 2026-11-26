# Camfeed: how it is built

Publishes an iPhone Continuity Camera to macOS as a regular camera device, so FaceTime, Chrome, Meet and anything else using AVFoundation can select it.

Two targets in one Xcode project:

- `dev.bgenc.camfeed` is a menu bar app. It runs an `AVCaptureSession` on the iPhone camera and writes frames into the extension's sink stream.
- `dev.bgenc.camfeed.camera` is a CoreMediaIO camera extension. It publishes two devices: "Camfeed Camera", which clients watch, and "Camfeed Input", whose sink stream the app writes into.

There is no scene composition, no encoder, no audio. The stream format is 1920x1080 BGRA at 30 fps; clients that want another size scale it themselves.

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

The menu bar icon shows what is being published. The camera submenu lists the cameras Camfeed can capture, Continuity Cameras first; picking one makes it the one Camfeed uses.

The iPhone is only held while something is watching: the app observes `kCMIODevicePropertyDeviceIsRunningSomewhere` on "Camfeed Camera" and starts capturing when a client opens the stream, releasing the camera three seconds after the last one leaves. When no feed is arriving, clients see Camfeed's own idle frame instead of a black screen.

`Show Log` opens the shared container, where `camfeed.log` records extension activation, capture state and stream activity.

## How frames move

The app cannot write a file the extension reads, or the other way round. The app runs as the logged-in user and the extension runs as `_cmiodalassistants`, so their containers are closed to each other: group containers are `0700`, `/private/var/db/cmiodalassistants` is `0750`, and a system extension gets the fixed `cmioextension` sandbox where a file exception entitlement is ignored.

A stream is the only channel that crosses that boundary. The extension adds a second, input-only device with a `CMIOExtensionStream` of `direction: .sink`. The app is an ordinary CoreMediaIO client of it: `CMIOStreamCopyBufferQueue`, `CMIODeviceStartStream`, then `CMSimpleQueueEnqueue` with a `CMSampleBuffer` per frame, cropped to 16:9 and scaled to 1920x1080 with vImage. The extension polls `consumeSampleBuffer(from:)`, keeps the newest buffer and sends it to the clients watching the output device. The input device never appears in camera pickers, because it has no source stream.

Frames are sent with `discontinuity: []`. Passing `.unknown` marks *every* frame discontinuous, which makes clients such as Chrome reset their timing prediction per frame and never start presenting.

## Known limits

- The sink stream keeps a queue of one buffer, so a frame the app enqueues while the extension is not consuming is dropped.
- iPhone controls (zoom, focus, exposure, torch) are not wired up yet.
- The idle frame is drawn once and cached for the extension's lifetime.

## Replacing an installed extension

Installing a build that changes the extension replaces it, and macOS races itself doing so: the CMIO daemon asks launchd for the new job while the old process is still terminating, the submit fails with `37: Operation already in progress`, and launchd then removes the job. The daemon never retries, so the extension cannot start and no app lists Camfeed. Clear it with `sudo killall -9 com.apple.cmio.registerassistantservice` (SIGTERM is ignored) or a reboot. A first install has no previous version to tear down and is unaffected.

## Two things macOS insists on

The extension bundle directory must be named exactly `<CFBundleIdentifier>.systemextension`. Any other name makes `OSSystemExtensionRequest` fail before it leaves the app with `Extension not found in App bundle`.

The build must be notarized. An unnotarized Developer ID extension is listed by `systemextensionsctl` but activation fails with `code signature invalid`, while `spctl` reports `rejected, source=Unnotarized Developer ID`. Notarizing the DMG covers the app and the nested extension; stapling the app is not needed, OBS ships without it too.

