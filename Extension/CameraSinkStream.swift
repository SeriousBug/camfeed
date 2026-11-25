//
//  CameraSinkStream.swift
//  Receives frames from the Camfeed app. The app runs as the logged-in user and this extension runs
//  as the CMIO daemon user, so a stream is the only channel between them: shared files are closed to
//  one side or the other, whichever container they sit in.
//

import CoreMedia
import CoreMediaIO
import Foundation

final class CameraSinkStream: NSObject, StreamOwner {
	weak var stream: CMIOExtensionStream?

	private let frames: LatestFrame
	private let queue = DispatchQueue(label: "dev.bgenc.camfeed.sink", qos: .userInteractive)
	private let formatDescription: CMFormatDescription?
	private let streamFormat: CMIOExtensionStreamFormat?
	private var timer: DispatchSourceTimer?
	private var client: CMIOExtensionClient?
	private var receivedFrames = 0

	init(frames: LatestFrame) {
		self.frames = frames
		let description = FrameFactory.formatDescription(
			width: CameraStreamSource.width,
			height: CameraStreamSource.height
		)
		formatDescription = description
		streamFormat = description.map {
			CMIOExtensionStreamFormat(
				formatDescription: $0,
				maxFrameDuration: CameraStreamSource.frameDuration,
				minFrameDuration: CameraStreamSource.frameDuration,
				validFrameDurations: nil
			)
		}
		super.init()
	}

	var direction: CMIOExtensionStream.Direction { .sink }

	var formats: [CMIOExtensionStreamFormat] {
		streamFormat.map { [$0] } ?? []
	}

	var availableProperties: Set<CMIOExtensionProperty> {
		[
			.streamActiveFormatIndex,
			.streamFrameDuration,
			.streamSinkBufferQueueSize,
			.streamSinkBuffersRequiredForStartup,
		]
	}

	func streamProperties(
		forProperties properties: Set<CMIOExtensionProperty>
	) throws -> CMIOExtensionStreamProperties {
		let streamProperties = CMIOExtensionStreamProperties(dictionary: [:])
		if properties.contains(.streamActiveFormatIndex) {
			streamProperties.activeFormatIndex = 0
		}
		if properties.contains(.streamFrameDuration) {
			streamProperties.frameDuration = CameraStreamSource.frameDuration
		}
		if properties.contains(.streamSinkBufferQueueSize) {
			streamProperties.sinkBufferQueueSize = 1
		}
		if properties.contains(.streamSinkBuffersRequiredForStartup) {
			streamProperties.sinkBuffersRequiredForStartup = 1
		}
		return streamProperties
	}

	func setStreamProperties(_ streamProperties: CMIOExtensionStreamProperties) throws {}

	func authorizedToStartStream(for client: CMIOExtensionClient) -> Bool {
		self.client = client
		camfeedLog("sink: the app may write frames")
		return true
	}

	func startStream() throws {
		camfeedLog("sink: start")
		receivedFrames = 0
		let timer = DispatchSource.makeTimerSource(queue: queue)
		timer.schedule(deadline: .now(), repeating: .milliseconds(11), leeway: .milliseconds(2))
		timer.setEventHandler { [weak self] in
			self?.consume()
		}
		timer.resume()
		self.timer = timer
	}

	func stopStream() throws {
		camfeedLog("sink: stop after \(receivedFrames) frames")
		timer?.cancel()
		timer = nil
	}

	private func consume() {
		guard let stream, let client else { return }
		stream.consumeSampleBuffer(from: client) { [weak self] sampleBuffer, sequenceNumber, _, hasMore, _ in
			guard let self else { return }
			if let sampleBuffer {
				frames.put(sampleBuffer)
				receivedFrames += 1
				if receivedFrames == 1 {
					camfeedLog("sink: first frame \(CMSampleBufferGetImageBuffer(sampleBuffer).map(CVPixelBufferGetWidth) ?? 0)x\(CMSampleBufferGetImageBuffer(sampleBuffer).map(CVPixelBufferGetHeight) ?? 0)")
				}
				let output = CMIOExtensionScheduledOutput(
					sequenceNumber: sequenceNumber,
					hostTimeInNanoseconds: UInt64(
						max(0, CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds * Double(NSEC_PER_SEC))
					)
				)
				stream.notifyScheduledOutputChanged(output)
			}
			if hasMore {
				consume()
			}
		}
	}
}
