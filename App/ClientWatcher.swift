//
//  ClientWatcher.swift
//  Watches the virtual camera's running state. While nothing has a stream open there is no reason to
//  hold the iPhone, and holding it makes the phone reconnect every time it drops, so the app captures
//  only while this reports a viewer.
//

import CoreMediaIO
import Foundation

final class ClientWatcher {
	private static let runningAddress = CMIOObjectPropertyAddress(
		mSelector: UInt32(kCMIODevicePropertyDeviceIsRunningSomewhere),
		mScope: UInt32(kCMIOObjectPropertyScopeGlobal),
		mElement: UInt32(kCMIOObjectPropertyElementMain)
	)

	private static let devicesAddress = CMIOObjectPropertyAddress(
		mSelector: UInt32(kCMIOHardwarePropertyDevices),
		mScope: UInt32(kCMIOObjectPropertyScopeGlobal),
		mElement: UInt32(kCMIOObjectPropertyElementMain)
	)

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
		guard let found = Self.virtualDevice() else {
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
		var address = Self.runningAddress
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
		var address = Self.runningAddress
		CMIOObjectRemovePropertyListenerBlock(device, &address, queue, listener)
		self.device = nil
		self.listener = nil
	}

	private func readState() {
		guard let device else { return }
		isActive = Self.isRunningSomewhere(device)
	}

	private static func virtualDevice() -> CMIOObjectID? {
		var address = devicesAddress
		var size: UInt32 = 0
		guard CMIOObjectGetPropertyDataSize(UInt32(kCMIOObjectSystemObject), &address, 0, nil, &size) == noErr,
		      size > 0 else {
			return nil
		}
		var ids = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
		var used: UInt32 = 0
		guard CMIOObjectGetPropertyData(
			UInt32(kCMIOObjectSystemObject), &address, 0, nil, size, &used, &ids
		) == noErr else {
			return nil
		}
		return ids.first { modelID(of: $0) == CameraCapture.virtualCameraModel }
	}

	private static func modelID(of id: CMIOObjectID) -> String? {
		var address = CMIOObjectPropertyAddress(
			mSelector: UInt32(kCMIODevicePropertyModelUID),
			mScope: UInt32(kCMIOObjectPropertyScopeGlobal),
			mElement: UInt32(kCMIOObjectPropertyElementMain)
		)
		var value: CFString?
		var used: UInt32 = 0
		let status = withUnsafeMutablePointer(to: &value) { pointer in
			CMIOObjectGetPropertyData(
				id, &address, 0, nil, UInt32(MemoryLayout<CFString?>.size), &used, pointer
			)
		}
		guard status == noErr, let value else { return nil }
		return value as String
	}

	private static func isRunningSomewhere(_ id: CMIOObjectID) -> Bool {
		var address = runningAddress
		var value: UInt32 = 0
		var used: UInt32 = 0
		guard CMIOObjectGetPropertyData(
			id, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &used, &value
		) == noErr else {
			return false
		}
		return value != 0
	}
}
