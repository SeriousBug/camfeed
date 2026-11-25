//
//  LatestFrame.swift
//  The app writes frames into the input device, the output device sends them to clients. Frames age
//  out so a stale picture is never left on screen after the app stops or the phone disconnects.
//

import CoreMedia
import Foundation
import QuartzCore

final class LatestFrame {
	private let lock = NSLock()
	private var buffer: CMSampleBuffer?
	private var arrival = 0.0

	func put(_ buffer: CMSampleBuffer) {
		lock.lock()
		defer { lock.unlock() }
		self.buffer = buffer
		arrival = CACurrentMediaTime()
	}

	func fresh(maxAge: Double) -> CMSampleBuffer? {
		lock.lock()
		defer { lock.unlock() }
		guard let buffer, CACurrentMediaTime() - arrival < maxAge else { return nil }
		return buffer
	}
}
