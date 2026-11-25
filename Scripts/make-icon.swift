// Draws the Camfeed app icon: a squircle with a lens aperture.
// Run with: swift Scripts/make-icon.swift <output.iconset>

import AppKit
import Foundation

let side = 1024
let canvas = CGFloat(side)
let inset = canvas * 0.0976
let rect = CGRect(x: inset, y: inset, width: canvas - inset * 2, height: canvas - inset * 2)
let radius = rect.width * 0.2237

func makeImage() -> NSBitmapImageRep {
	let image = NSImage(size: NSSize(width: canvas, height: canvas))
	image.lockFocus()

	let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
	path.addClip()

	let gradient = NSGradient(colors: [
		NSColor(srgbRed: 0.11, green: 0.13, blue: 0.18, alpha: 1),
		NSColor(srgbRed: 0.20, green: 0.24, blue: 0.32, alpha: 1),
	])!
	gradient.draw(in: path, angle: -90)

	// Lens barrel.
	let lensCenter = CGPoint(x: canvas / 2, y: canvas / 2)
	let outerRadius = rect.width * 0.30
	let outer = NSBezierPath(
		ovalIn: CGRect(
			x: lensCenter.x - outerRadius,
			y: lensCenter.y - outerRadius,
			width: outerRadius * 2,
			height: outerRadius * 2
		)
	)
	NSColor.white.withAlphaComponent(0.96).setFill()
	outer.fill()

	// Aperture blades read as a ring.
	let ring = NSBezierPath()
	let blades = 6
	let innerRadius = outerRadius * 0.68
	let bladeRadius = outerRadius * 0.26
	for index in 0..<blades {
		let angle = (CGFloat(index) / CGFloat(blades)) * .pi * 2 + .pi / 6
		let center = CGPoint(
			x: lensCenter.x + cos(angle) * innerRadius,
			y: lensCenter.y + sin(angle) * innerRadius
		)
		ring.appendArc(
			withCenter: center,
			radius: bladeRadius,
			startAngle: 0,
			endAngle: 360
		)
	}
	NSColor(srgbRed: 0.11, green: 0.13, blue: 0.18, alpha: 1).setFill()
	ring.fill()

	let coreRadius = outerRadius * 0.30
	let core = NSBezierPath(
		ovalIn: CGRect(
			x: lensCenter.x - coreRadius,
			y: lensCenter.y - coreRadius,
			width: coreRadius * 2,
			height: coreRadius * 2
		)
	)
	NSColor(srgbRed: 0.35, green: 0.62, blue: 0.98, alpha: 1).setFill()
	core.fill()

	image.unlockFocus()

	guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else {
		fatalError("could not rasterise icon")
	}
	return rep
}

guard CommandLine.arguments.count > 1 else {
	print("usage: make-icon.swift <output.iconset>")
	exit(1)
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let rep = makeImage()
let sizes = [16, 32, 64, 128, 256, 512, 1024]
for size in sizes {
	let resized = NSImage(size: NSSize(width: size, height: side))
	_ = resized
	guard let data = rep.representation(using: .png, properties: [:]) else { continue }
	let source = NSBitmapImageRep(data: data)!
	let target = NSBitmapImageRep(
		bitmapDataPlanes: nil,
		pixelsWide: size,
		pixelsHigh: size,
		bitsPerSample: 8,
		samplesPerPixel: 4,
		hasAlpha: true,
		isPlanar: false,
		colorSpaceName: .deviceRGB,
		bytesPerRow: 0,
		bitsPerPixel: 0
	)!
	NSGraphicsContext.saveGraphicsState()
	NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: target)
	NSGraphicsContext.current?.imageInterpolation = .high
	source.draw(
		in: NSRect(x: 0, y: 0, width: size, height: size),
		from: .zero,
		operation: .copy,
		fraction: 1,
		respectFlipped: false,
		hints: nil
	)
	NSGraphicsContext.restoreGraphicsState()
	guard let png = target.representation(using: .png, properties: [:]) else { continue }
	let name: String
	if size <= 512 {
		try png.write(to: outputDirectory.appendingPathComponent("icon_\(size)x\(size).png"))
		name = "icon_\(size)x\(size)"
	} else {
		try png.write(to: outputDirectory.appendingPathComponent("icon_512x512@2x.png"))
		name = "icon_512x512@2x"
	}
	_ = name
}
print("wrote icons to \(outputDirectory.path)")
