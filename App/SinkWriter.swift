//
//  SinkWriter.swift
//  Writes camera frames into the extension's input device. The app is a CoreMediaIO client of the
//  sink stream, which is the only channel that can carry frames into the sandboxed extension.
//

import Accelerate
import CoreMedia
import CoreMediaIO
import CoreVideo
import Foundation

final class SinkWriter {
	static let width = 1920
	static let height = 1080

	private var device: CMIOObjectID?
	private var stream: CMIOObjectID?
	private var queue: CMSimpleQueue?
	private var formatDescription: CMFormatDescription?
	private var pool: CVPixelBufferPool?
	private var writtenFrames = 0
	private var lastStartAttempt = 0.0

	var isRunning: Bool { queue != nil }

	/// Called for every frame; keeps retrying at most once a second while the extension is absent.
	func startIfNeeded() -> Bool {
		if isRunning { return true }
		let now = Date.timeIntervalSinceReferenceDate
		guard now - lastStartAttempt > 1 else { return false }
		lastStartAttempt = now

		guard let device = CMIODevices.device(model: "CamfeedInput") else {
			camfeedLog("sink: the input device is not there yet")
			return false
		}
		let streams = CMIODevices.streams(of: device)
		guard let stream = streams.last else {
			camfeedLog("sink: the input device has no stream")
			return false
		}
		var copiedQueue: Unmanaged<CMSimpleQueue>?
		guard CMIOStreamCopyBufferQueue(stream, { _, _, _ in }, nil, &copiedQueue) == noErr,
		      let copiedQueue else {
			camfeedLog("sink: no buffer queue for the sink stream")
			return false
		}
		let status = CMIODeviceStartStream(device, stream)
		guard status == noErr else {
			camfeedLog("sink: starting the sink stream failed with \(status)")
			return false
		}
		guard let description = Self.makeFormatDescription() else {
			camfeedLog("sink: no format description")
			CMIODeviceStopStream(device, stream)
			return false
		}
		self.device = device
		self.stream = stream
		self.queue = copiedQueue.takeUnretainedValue()
		self.formatDescription = description
		self.pool = Self.makePool()
		camfeedLog("sink: feeding the camera extension")
		return true
	}

	func stop() {
		guard let device, let stream else { return }
		CMIODeviceStopStream(device, stream)
		camfeedLog("sink: stopped after \(writtenFrames) frames")
		self.device = nil
		self.stream = nil
		queue = nil
		formatDescription = nil
		pool = nil
	}

	func write(_ pixelBuffer: CVPixelBuffer) {
		guard let queue, let formatDescription, let pool else { return }
		guard let destination = Self.pooledBuffer(pool) else { return }
		guard scale(pixelBuffer, into: destination) else { return }

		var timing = CMSampleTimingInfo(
			duration: CMTime(value: 1, timescale: 30),
			presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
			decodeTimeStamp: .invalid
		)
		var sampleBuffer: CMSampleBuffer?
		let created = CMSampleBufferCreateReadyWithImageBuffer(
			allocator: kCFAllocatorDefault,
			imageBuffer: destination,
			formatDescription: formatDescription,
			sampleTiming: &timing,
			sampleBufferOut: &sampleBuffer
		)
		guard created == noErr, let sampleBuffer else { return }

		let retained = Unmanaged.passRetained(sampleBuffer)
		if CMSimpleQueueEnqueue(queue, element: retained.toOpaque()) != noErr {
			retained.release()
			return
		}
		if writtenFrames == 0 {
			camfeedLog("sink: first frame \(Self.width)x\(Self.height)")
		}
		writtenFrames += 1
	}

	private func scale(_ source: CVPixelBuffer, into destination: CVPixelBuffer) -> Bool {
		CVPixelBufferLockBaseAddress(source, .readOnly)
		CVPixelBufferLockBaseAddress(destination, [])
		defer {
			CVPixelBufferUnlockBaseAddress(destination, [])
			CVPixelBufferUnlockBaseAddress(source, .readOnly)
		}
		guard let sourceBase = CVPixelBufferGetBaseAddress(source),
		      let destinationBase = CVPixelBufferGetBaseAddress(destination) else { return false }

		var sourceBuffer = vImage_Buffer(
			data: sourceBase,
			height: vImagePixelCount(CVPixelBufferGetHeight(source)),
			width: vImagePixelCount(CVPixelBufferGetWidth(source)),
			rowBytes: CVPixelBufferGetBytesPerRow(source)
		)
		var cropped = crop(sourceBuffer)
		var destinationBuffer = vImage_Buffer(
			data: destinationBase,
			height: vImagePixelCount(CVPixelBufferGetHeight(destination)),
			width: vImagePixelCount(CVPixelBufferGetWidth(destination)),
			rowBytes: CVPixelBufferGetBytesPerRow(destination)
		)
		let error = vImageScale_ARGB8888(
			&cropped,
			&destinationBuffer,
			nil,
			vImage_Flags(kvImageHighQualityResampling) | vImage_Flags(kvImageDoNotTile)
		)
		return error == kvImageNoError
	}

	/// Center crop to 16:9 so the scaled frame is not stretched.
	private func crop(_ buffer: vImage_Buffer) -> vImage_Buffer {
		let targetAspect = Float(Self.width) / Float(Self.height)
		let sourceWidth = Int(buffer.width)
		let sourceHeight = Int(buffer.height)
		guard sourceWidth > 0, sourceHeight > 0 else { return buffer }
		let sourceAspect = Float(sourceWidth) / Float(sourceHeight)
		guard abs(targetAspect - sourceAspect) >= 0.01 else { return buffer }

		var cropped = buffer
		if sourceAspect > targetAspect {
			let cropWidth = Int((Float(sourceHeight) * targetAspect).rounded())
			cropped.data = buffer.data.advanced(by: ((sourceWidth - cropWidth) / 2) * 4)
			cropped.width = vImagePixelCount(cropWidth)
		} else {
			let cropHeight = Int((Float(sourceWidth) / targetAspect).rounded())
			cropped.data = buffer.data.advanced(by: ((sourceHeight - cropHeight) / 2) * buffer.rowBytes)
			cropped.height = vImagePixelCount(cropHeight)
		}
		return cropped
	}

	private static func makeFormatDescription() -> CMFormatDescription? {
		var description: CMFormatDescription?
		let status = CMVideoFormatDescriptionCreate(
			allocator: kCFAllocatorDefault,
			codecType: kCVPixelFormatType_32BGRA,
			width: Int32(width),
			height: Int32(height),
			extensions: nil,
			formatDescriptionOut: &description
		)
		return status == noErr ? description : nil
	}

	private static func makePool() -> CVPixelBufferPool? {
		let attributes: [CFString: Any] = [
			kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any],
			kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
			kCVPixelBufferWidthKey: width,
			kCVPixelBufferHeightKey: height,
			kCVPixelBufferBytesPerRowAlignmentKey: 64,
		]
		var pool: CVPixelBufferPool?
		let status = CVPixelBufferPoolCreate(
			kCFAllocatorDefault,
			[kCVPixelBufferPoolMinimumBufferCountKey: 4] as CFDictionary,
			attributes as CFDictionary,
			&pool
		)
		return status == kCVReturnSuccess ? pool : nil
	}

	private static func pooledBuffer(_ pool: CVPixelBufferPool) -> CVPixelBuffer? {
		var pixelBuffer: CVPixelBuffer?
		let status = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(
			kCFAllocatorDefault,
			pool,
			[kCVPixelBufferPoolAllocationThresholdKey: 4] as CFDictionary,
			&pixelBuffer
		)
		return status == kCVReturnSuccess ? pixelBuffer : nil
	}
}
