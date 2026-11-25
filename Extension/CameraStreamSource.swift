//
//  CameraStreamSource.swift
//  Pumps the newest frame from the shared ring to whichever client started the stream.
//

import CoreMedia
import CoreMediaIO
import Foundation

final class CameraStreamSource: NSObject, CMIOExtensionStreamSource {
	private struct Format {
		let width: Int
		let height: Int
		let description: CMFormatDescription
		let streamFormat: CMIOExtensionStreamFormat
	}

	private let ring = FrameRing()
	private let queue = DispatchQueue(label: "dev.bgenc.camfeed.stream", qos: .userInteractive)
	private let frameDuration = CMTime(value: 1, timescale: 30)

	private var timer: DispatchSourceTimer?
	private var activeFormatIndex = 0
	private var idleBuffers: [String: CVPixelBuffer] = [:]
	private var framesSent = 0

	weak var stream: CMIOExtensionStream?

	private lazy var streamFormats: [Format] = {
		[(1920, 1080), (1280, 720), (960, 540)].compactMap { size in
			guard let description = FrameFactory.formatDescription(width: size.0, height: size.1) else { return nil }
			let streamFormat = CMIOExtensionStreamFormat(
				formatDescription: description,
				maxFrameDuration: frameDuration,
				minFrameDuration: frameDuration,
				validFrameDurations: nil
			)
			return Format(
				width: size.0,
				height: size.1,
				description: description,
				streamFormat: streamFormat
			)
		}
	}()

	override init() {
		super.init()
		ring.open(create: true)
	}

	var formats: [CMIOExtensionStreamFormat] {
		streamFormats.map(\.streamFormat)
	}

	var availableProperties: Set<CMIOExtensionProperty> {
		[.streamActiveFormatIndex, .streamFrameDuration]
	}

	func streamProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionStreamProperties {
		let streamProperties = CMIOExtensionStreamProperties(dictionary: [:])
		if properties.contains(.streamActiveFormatIndex) {
			streamProperties.activeFormatIndex = activeFormatIndex
		}
		if properties.contains(.streamFrameDuration) {
			streamProperties.frameDuration = frameDuration
		}
		return streamProperties
	}

	func setStreamProperties(_ streamProperties: CMIOExtensionStreamProperties) throws {
		if let index = streamProperties.activeFormatIndex as? Int, streamFormats.indices.contains(index) {
			activeFormatIndex = index
			publishRequestedFormat()
			idleBuffers.removeAll()
			camfeedLog("stream: active format is now \(streamFormats[index].width)x\(streamFormats[index].height)")
		}
	}

	func authorizedToStartStream(for client: CMIOExtensionClient) -> Bool {
		true
	}

	func startStream() throws {
		camfeedLog("stream: start")
		ring.open(create: true)
		publishRequestedFormat()
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
		camfeedLog("stream: stop after \(framesSent) frames")
		timer?.cancel()
		timer = nil
	}

	private func publishRequestedFormat() {
		guard streamFormats.indices.contains(activeFormatIndex) else { return }
		let format = streamFormats[activeFormatIndex]
		ring.publishRequestedFormat(width: format.width, height: format.height)
	}

	private func sendNextFrame() {
		guard let stream, streamFormats.indices.contains(activeFormatIndex) else { return }
		let format = streamFormats[activeFormatIndex]
		let presentationTime = CMClockGetTime(CMClockGetHostTimeClock())
		let hostTimeInNanoseconds = UInt64(
			max(0, CMTimeConvertScale(presentationTime, timescale: 1_000_000_000, method: .default).value)
		)

		let sampleBuffer: CMSampleBuffer?
		if let frame = ring.latestFrame(), frame.width == format.width, frame.height == format.height {
			sampleBuffer = FrameFactory.sampleBuffer(
				wrapping: frame.pointer,
				width: frame.width,
				height: frame.height,
				formatDescription: format.description,
				presentationTime: presentationTime
			)
		} else {
			sampleBuffer = idleSampleBuffer(for: format, presentationTime: presentationTime)
		}

		guard let sampleBuffer else { return }
		stream.send(sampleBuffer, discontinuity: .unknown, hostTimeInNanoseconds: hostTimeInNanoseconds)
		if framesSent % 300 == 0 {
			camfeedLog("stream: sent \(framesSent) frames, ring mapped: \(ring.isMapped)")
		}
		framesSent += 1
	}

	private func idleSampleBuffer(for format: Format, presentationTime: CMTime) -> CMSampleBuffer? {
		let key = "\(format.width)x\(format.height)"
		let pixelBuffer: CVPixelBuffer
		if let cached = idleBuffers[key] {
			pixelBuffer = cached
		} else if let created = FrameFactory.idlePixelBuffer(width: format.width, height: format.height) {
			idleBuffers[key] = created
			pixelBuffer = created
		} else {
			return nil
		}
		return FrameFactory.wrap(
			pixelBuffer,
			formatDescription: format.description,
			presentationTime: presentationTime
		)
	}
}
