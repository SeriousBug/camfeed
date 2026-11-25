//
//  CMIODevices.swift
//  Reading the virtual devices from the app side through CoreMediaIO.
//

import CoreMediaIO
import Foundation

enum CMIODevices {
	static func device(model: String) -> CMIOObjectID? {
		var address = CMIOObjectPropertyAddress(
			mSelector: UInt32(kCMIOHardwarePropertyDevices),
			mScope: UInt32(kCMIOObjectPropertyScopeGlobal),
			mElement: UInt32(kCMIOObjectPropertyElementMain)
		)
		var size: UInt32 = 0
		guard CMIOObjectGetPropertyDataSize(UInt32(kCMIOObjectSystemObject), &address, 0, nil, &size) == noErr,
		      size > 0 else {
			return nil
		}
		var ids = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
		var used: UInt32 = 0
		guard CMIOObjectGetPropertyData(UInt32(kCMIOObjectSystemObject), &address, 0, nil, size, &used, &ids) == noErr
		else { return nil }
		return ids.first { modelID(of: $0) == model }
	}

	static func modelID(of id: CMIOObjectID) -> String? {
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

	static func streams(of device: CMIOObjectID) -> [CMIOObjectID] {
		var address = CMIOObjectPropertyAddress(
			mSelector: UInt32(kCMIODevicePropertyStreams),
			mScope: UInt32(kCMIOObjectPropertyScopeGlobal),
			mElement: UInt32(kCMIOObjectPropertyElementMain)
		)
		var size: UInt32 = 0
		guard CMIOObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
		var ids = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
		var used: UInt32 = 0
		guard CMIOObjectGetPropertyData(device, &address, 0, nil, size, &used, &ids) == noErr else { return [] }
		return ids
	}

	static let runningSomewhereAddress = CMIOObjectPropertyAddress(
		mSelector: UInt32(kCMIODevicePropertyDeviceIsRunningSomewhere),
		mScope: UInt32(kCMIOObjectPropertyScopeGlobal),
		mElement: UInt32(kCMIOObjectPropertyElementMain)
	)

	static func isRunningSomewhere(_ device: CMIOObjectID) -> Bool {
		var address = runningSomewhereAddress
		var value: UInt32 = 0
		var used: UInt32 = 0
		guard CMIOObjectGetPropertyData(
			device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &used, &value
		) == noErr else { return false }
		return value != 0
	}
}
