//
//  CameraStreamSource.swift
//  Sends whatever the input device last received to the clients watching this device, and the idle
//  frame when nothing is arriving.
//

import CoreMedia
import CoreMediaIO
import Foundation

/// A stream source that owns its `CMIOExtensionStream`, so a device can build both ends the same way.
protocol StreamOwner: CMIOExtensionStreamSource {
	var stream: CMIOExtensionStream? { get set }
	var direction: CMIOExtensionStream.Direction { get }
}

final class CameraStreamSource: NSObject, StreamOwner {
	static let width = 1920
	static let height = 1080
	static let frameDuration = CMTime(value: 1, timescale: 30)

	weak var stream: CMIOExtensionStream?

	private let frames: LatestFrame
	private let queue = DispatchQueue(label: "dev.bgenc.camfeed.stream", qos: .userInteractive)
	private let formatDescription: CMFormatDescription?
	private let streamFormat: CMIOExtensionStreamFormat?
	private var timer: DispatchSourceTimer?
	private var idleBuffer: CVPixelBuffer?
	private var framesSent = 0

	init(frames: LatestFrame) {
		self.frames = frames
		let description = FrameFactory.formatDescription(width: Self.width, height: Self.height)
		formatDescription = description
		streamFormat = description.map {
			CMIOExtensionStreamFormat(
				formatDescription: $0,
				maxFrameDuration: Self.frameDuration,
				minFrameDuration: Self.frameDuration,
				validFrameDurations: nil
			)
		}
		super.init()
	}

	var direction: CMIOExtensionStream.Direction { .source }

	var formats: [CMIOExtensionStreamFormat] {
		streamFormat.map { [$0] } ?? []
	}

	var availableProperties: Set<CMIOExtensionProperty> {
		[.streamActiveFormatIndex, .streamFrameDuration]
	}

	func streamProperties(
		forProperties properties: Set<CMIOExtensionProperty>
	) throws -> CMIOExtensionStreamProperties {
		let streamProperties = CMIOExtensionStreamProperties(dictionary: [:])
		if properties.contains(.streamActiveFormatIndex) {
			streamProperties.activeFormatIndex = 0
		}
		if properties.contains(.streamFrameDuration) {
			streamProperties.frameDuration = Self.frameDuration
		}
		return streamProperties
	}

	func setStreamProperties(_ streamProperties: CMIOExtensionStreamProperties) throws {
		if let index = streamProperties.activeFormatIndex {
			camfeedLog("stream: client selected format \(index)")
		}
	}

	func authorizedToStartStream(for client: CMIOExtensionClient) -> Bool {
		true
	}

	func startStream() throws {
		camfeedLog("stream: a client started watching")
		framesSent = 0
		let timer = DispatchSource.makeTimerSource(queue: queue)
		timer.schedule(deadline: .now(), repeating: .milliseconds(33), leeway: .milliseconds(2))
		timer.setEventHandler { [weak self] in
			self?.sendNextFrame()
		}
		timer.resume()
		self.timer = timer
	}

	func stopStream() throws {
		camfeedLog("stream: client stopped after \(framesSent) frames")
		timer?.cancel()
		timer = nil
	}

	private func sendNextFrame() {
		guard let stream else { return }
		guard let sampleBuffer = frames.fresh(maxAge: 0.5) ?? idleSampleBuffer() else { return }
		let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
		let hostTime = UInt64(
			max(0, CMTimeConvertScale(presentationTime, timescale: 1_000_000_000, method: .default).value)
		)
		stream.send(sampleBuffer, discontinuity: [], hostTimeInNanoseconds: hostTime)
		framesSent += 1
		if framesSent == 300 {
			camfeedLog("stream: sent \(framesSent) frames")
		}
	}

	private func idleSampleBuffer() -> CMSampleBuffer? {
		guard let formatDescription else { return nil }
		if idleBuffer == nil {
			idleBuffer = FrameFactory.idlePixelBuffer(width: Self.width, height: Self.height)
		}
		guard let idleBuffer else { return nil }
		return FrameFactory.wrap(
			idleBuffer,
			formatDescription: formatDescription,
			presentationTime: CMClockGetTime(CMClockGetHostTimeClock())
		)
	}
}
