//
//  ClientWatcher.swift
//  Watches the output device's running state. While nothing has a stream open there is no reason to
//  hold the iPhone, and holding it makes the phone reconnect every time it drops, so the app captures
//  only while this reports a viewer.
//

import CoreMediaIO
import Foundation

final class ClientWatcher {
	private var device: CMIOObjectID?
	private var listener: CMIOObjectPropertyListenerBlock?
	private let queue = DispatchQueue(label: "dev.bgenc.camfeed.watch")

	private(set) var isActive = false {
		didSet {
			guard isActive != oldValue else { return }
			let active = isActive
			DispatchQueue.main.async { [self] in
				camfeedLog(active ? "watch: a viewer opened the camera" : "watch: the last viewer left")
				onChange?(active)
			}
		}
	}

	var onChange: ((Bool) -> Void)?

	/// Called from the app's poll timer: the extension can be reinstalled, which replaces the object.
	func refresh() {
		queue.async { self.refreshLocked() }
	}

	private func refreshLocked() {
		guard let found = CMIODevices.device(model: CameraCapture.virtualCameraModel) else {
			removeListener()
			isActive = false
			return
		}
		if found != device {
			removeListener()
			addListener(for: found)
		}
		readState()
	}

	private func addListener(for id: CMIOObjectID) {
		var address = CMIODevices.runningSomewhereAddress
		let block: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in
			self?.readState()
		}
		guard CMIOObjectAddPropertyListenerBlock(id, &address, queue, block) == noErr else {
			camfeedLog("watch: could not observe the camera")
			return
		}
		device = id
		listener = block
	}

	private func removeListener() {
		guard let device, let listener else { return }
		var address = CMIODevices.runningSomewhereAddress
		CMIOObjectRemovePropertyListenerBlock(device, &address, queue, listener)
		self.device = nil
		self.listener = nil
	}

	private func readState() {
		guard let device else { return }
		isActive = CMIODevices.isRunningSomewhere(device)
	}
}
