//
//  FrameWriter.swift
//  Publishes camera frames into the shared ring, scaled and cropped to the format a client asked for.
//

import Accelerate
import CoreVideo
import Foundation

final class FrameWriter {
	private var base: UnsafeMutableRawPointer?
	private var fileDescriptor: Int32 = -1
	private var cachedTarget = (width: 0, height: 0)
	private var writtenFrames = 0
	private var receivedFrames = 0

	private static let fallbackTarget = (width: 1920, height: 1080)

	var isReady: Bool { base != nil }

	func open() {
		guard base == nil else { return }
		CamfeedPaths.prepareDirectory()
		let path = CamfeedPaths.ringFile.path

		let fd = path.withCString { camfeed_ring_open($0, 1) }
		guard fd >= 0 else {
			camfeedLog("ring: open failed for \(path) errno=\(errno)")
			return
		}
		guard let mapped = camfeed_ring_map(fd) else {
			close(fd)
			camfeedLog("ring: mmap failed")
			return
		}
		guard camfeed_ring_prepare(fd, mapped) == 0 else {
			camfeed_ring_unmap(fd, mapped)
			camfeedLog("ring: prepare failed")
			return
		}
		fileDescriptor = fd
		base = mapped
		camfeedLog("ring: writer ready at \(path)")
	}

	func write(_ pixelBuffer: CVPixelBuffer) {
		guard let base else { return }
		if receivedFrames == 0 {
			camfeedLog(
				"ring: first buffer \(CVPixelBufferGetWidth(pixelBuffer))x\(CVPixelBufferGetHeight(pixelBuffer))"
			)
		}
		receivedFrames += 1
		let target = targetSize()
		guard target.width > 0, target.height > 0 else {
			if receivedFrames % 150 == 1 {
				camfeedLog("ring: no client format requested yet, dropping buffer")
			}
			return
		}

		CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
		defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
		guard let source = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }

		var sourceBuffer = vImage_Buffer(
			data: source,
			height: vImagePixelCount(CVPixelBufferGetHeight(pixelBuffer)),
			width: vImagePixelCount(CVPixelBufferGetWidth(pixelBuffer)),
			rowBytes: CVPixelBufferGetBytesPerRow(pixelBuffer)
		)

		var cropped = crop(sourceBuffer, toAspectOf: target)
		sourceBuffer = cropped

		guard let destination = camfeed_ring_begin_write(base) else { return }
		var destinationBuffer = vImage_Buffer(
			data: destination,
			height: vImagePixelCount(target.height),
			width: vImagePixelCount(target.width),
			rowBytes: target.width * 4
		)
		let error = vImageScale_ARGB8888(
			&cropped,
			&destinationBuffer,
			nil,
			vImage_Flags(kvImageHighQualityResampling) | vImage_Flags(kvImageDoNotTile)
		)
		guard error == kvImageNoError else {
			if writtenFrames == 0 {
				camfeedLog("ring: vImage scale failed with \(error)")
			}
			return
		}
		camfeed_ring_commit_write(base, UInt32(target.width), UInt32(target.height))
		if writtenFrames == 0 {
			camfeedLog("ring: first frame \(target.width)x\(target.height)")
		}
		writtenFrames += 1
	}

	/// The format the extension published for the client that started the stream.
	private func targetSize() -> (width: Int, height: Int) {
		guard let base else { return (0, 0) }
		var width: UInt32 = 0
		var height: UInt32 = 0
		camfeed_ring_get_requested_format(base, &width, &height)
		if width == 0 || height == 0 {
			cachedTarget = (0, 0)
			return (0, 0)
		}
		if cachedTarget.width != Int(width) || cachedTarget.height != Int(height) {
			cachedTarget = (Int(width), Int(height))
			camfeedLog("ring: client asked for \(width)x\(height)")
		}
		return cachedTarget
	}

	/// Center crop to the target aspect ratio so the scaled frame is not stretched.
	private func crop(_ buffer: vImage_Buffer, toAspectOf target: (width: Int, height: Int)) -> vImage_Buffer {
		let sourceWidth = Int(buffer.width)
		let sourceHeight = Int(buffer.height)
		guard sourceWidth > 0, sourceHeight > 0 else { return buffer }

		let targetAspect = Float(target.width) / Float(target.height)
		let sourceAspect = Float(sourceWidth) / Float(sourceHeight)
		if abs(targetAspect - sourceAspect) < 0.01 {
			return buffer
		}

		var cropped = buffer
		if sourceAspect > targetAspect {
			let cropWidth = Int((Float(sourceHeight) * targetAspect).rounded())
			let originX = (sourceWidth - cropWidth) / 2
			cropped.data = buffer.data.advanced(by: originX * 4)
			cropped.width = vImagePixelCount(cropWidth)
		} else {
			let cropHeight = Int((Float(sourceWidth) / targetAspect).rounded())
			let originY = (sourceHeight - cropHeight) / 2
			cropped.data = buffer.data.advanced(by: originY * buffer.rowBytes)
			cropped.height = vImagePixelCount(cropHeight)
		}
		return cropped
	}
}
