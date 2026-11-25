//
//  FrameRing.swift
//  Extension side reader of the shared frame ring written by the Camfeed app.
//

import Foundation

final class FrameRing {
	private(set) var base: UnsafeMutableRawPointer?
	private var fileDescriptor: Int32 = -1

	var isMapped: Bool { base != nil }

	func open(create: Bool) {
		guard base == nil else { return }
		CamfeedPaths.prepareDirectory()
		let path = CamfeedPaths.ringFile.path

		let fd = path.withCString { camfeed_ring_open($0, create ? 1 : 0) }
		guard fd >= 0 else {
			if create {
				camfeedLog("ring: open failed for \(path) errno=\(errno)")
			}
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
		camfeedLog("ring: mapped \(path)")
	}

	/// Returns the newest complete frame, if the app published one.
	func latestFrame() -> (pointer: UnsafeMutablePointer<UInt8>, width: Int, height: Int)? {
		guard let base else { return nil }
		var data: UnsafeMutablePointer<UInt8>?
		var width: UInt32 = 0
		var height: UInt32 = 0
		guard camfeed_ring_read_latest(base, &data, &width, &height) == 1, let data else {
			return nil
		}
		return (data, Int(width), Int(height))
	}

	func publishRequestedFormat(width: Int, height: Int) {
		guard let base else { return }
		camfeed_ring_set_requested_format(base, UInt32(width), UInt32(height))
	}

	func requestedFormat() -> (width: Int, height: Int) {
		guard let base else { return (0, 0) }
		var width: UInt32 = 0
		var height: UInt32 = 0
		camfeed_ring_get_requested_format(base, &width, &height)
		return (Int(width), Int(height))
	}
}
