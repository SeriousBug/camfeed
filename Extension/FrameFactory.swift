//
//  FrameFactory.swift
//  Turns ring buffer bytes into CMSampleBuffers, and draws the idle frame shown when the app has no camera.
//

import CoreGraphics
import CoreMedia
import CoreText
import CoreVideo
import Foundation

enum FrameFactory {
	static let frameDuration = CMTime(value: 1, timescale: 30)

	static func formatDescription(width: Int, height: Int) -> CMFormatDescription? {
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

	static func makePixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
		let attributes: [CFString: Any] = [
			kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any],
			kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
			kCVPixelBufferWidthKey: width,
			kCVPixelBufferHeightKey: height,
			kCVPixelBufferBytesPerRowAlignmentKey: 64,
		]
		var pixelBuffer: CVPixelBuffer?
		let status = CVPixelBufferCreate(
			kCFAllocatorDefault,
			width,
			height,
			kCVPixelFormatType_32BGRA,
			attributes as CFDictionary,
			&pixelBuffer
		)
		return status == kCVReturnSuccess ? pixelBuffer : nil
	}

	/// Wraps ring bytes without copying. The mapping lives for the extension's lifetime.
	static func sampleBuffer(
		wrapping bytes: UnsafeMutableRawPointer,
		width: Int,
		height: Int,
		formatDescription: CMFormatDescription,
		presentationTime: CMTime
	) -> CMSampleBuffer? {
		var pixelBuffer: CVPixelBuffer?
		let attributes: [CFString: Any] = [
			kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any],
			kCVPixelBufferBytesPerRowAlignmentKey: 64,
		]
		let status = CVPixelBufferCreateWithBytes(
			kCFAllocatorDefault,
			width,
			height,
			kCVPixelFormatType_32BGRA,
			bytes,
			width * 4,
			nil,
			nil,
			attributes as CFDictionary,
			&pixelBuffer
		)
		guard status == kCVReturnSuccess, let pixelBuffer else { return nil }
		return wrap(pixelBuffer, formatDescription: formatDescription, presentationTime: presentationTime)
	}

	static func wrap(
		_ pixelBuffer: CVPixelBuffer,
		formatDescription: CMFormatDescription,
		presentationTime: CMTime
	) -> CMSampleBuffer? {
		var timing = CMSampleTimingInfo(
			duration: frameDuration,
			presentationTimeStamp: presentationTime,
			decodeTimeStamp: .invalid
		)
		var sampleBuffer: CMSampleBuffer?
		let status = CMSampleBufferCreateReadyWithImageBuffer(
			allocator: kCFAllocatorDefault,
			imageBuffer: pixelBuffer,
			formatDescription: formatDescription,
			sampleTiming: &timing,
			sampleBufferOut: &sampleBuffer
		)
		return status == noErr ? sampleBuffer : nil
	}

	/// Draws the frame clients see while no iPhone feed is arriving.
	static func idlePixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
		guard let pixelBuffer = makePixelBuffer(width: width, height: height) else { return nil }
		CVPixelBufferLockBaseAddress(pixelBuffer, [])
		defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
		guard let context = CGContext(
			data: CVPixelBufferGetBaseAddress(pixelBuffer),
			width: width,
			height: height,
			bitsPerComponent: 8,
			bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
			space: CGColorSpaceCreateDeviceRGB(),
			bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
		) else { return nil }

		let colors = [
			CGColor(red: 0.09, green: 0.10, blue: 0.12, alpha: 1),
			CGColor(red: 0.17, green: 0.19, blue: 0.23, alpha: 1),
		] as CFArray
		if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
			context.drawLinearGradient(
				gradient,
				start: CGPoint(x: 0, y: 0),
				end: CGPoint(x: 0, y: height),
				options: []
			)
		}

		let titleSize = CGFloat(height) * 0.055
		let title = CTFontCreateWithName("HelveticaNeue-Medium" as CFString, titleSize, nil)
		let subtitle = CTFontCreateWithName("HelveticaNeue" as CFString, titleSize * 0.6, nil)
		drawCentered("Camfeed", font: title, context: context, width: width, height: height, offset: titleSize * 0.45, alpha: 0.92)
		drawCentered(
			"iPhone camera not connected",
			font: subtitle,
			context: context,
			width: width,
			height: height,
			offset: -titleSize * 0.6,
			alpha: 0.5
		)
		return pixelBuffer
	}

	private static func drawCentered(
		_ text: String,
		font: CTFont,
		context: CGContext,
		width: Int,
		height: Int,
		offset: CGFloat,
		alpha: CGFloat
	) {
		let attributes: [NSAttributedString.Key: Any] = [
			NSAttributedString.Key(kCTFontAttributeName as String): font,
			NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(
				red: 1,
				green: 1,
				blue: 1,
				alpha: alpha
			),
		]
		let attributed = NSAttributedString(string: text, attributes: attributes)
		let line = CTLineCreateWithAttributedString(attributed)
		let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
		context.textPosition = CGPoint(
			x: (CGFloat(width) - bounds.width) / 2 - bounds.minX,
			y: (CGFloat(height) - bounds.height) / 2 - bounds.minY + offset
		)
		CTLineDraw(line, context)
	}
}
