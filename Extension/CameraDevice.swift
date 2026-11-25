//
//  CameraDevice.swift
//  One virtual device. The extension publishes two: the output device clients watch and the input
//  device the app feeds, so the app's own writing does not look like somebody watching.
//

import CoreMediaIO
import Foundation

/// Audio transport type fourcc from IOKit/audio/IOAudioTypes.h: virtual hardware.
private let virtualTransportType = 0x7669_7274 // 'virt'

final class CameraDevice: NSObject, CMIOExtensionDeviceSource {
	private(set) var device: CMIOExtensionDevice!
	private let model: String

	init(localizedName: String, model: String, owners: [StreamOwner]) {
		self.model = model
		super.init()
		device = CMIOExtensionDevice(
			localizedName: localizedName,
			deviceID: UUID(),
			legacyDeviceID: nil,
			source: self
		)
		for owner in owners {
			let stream = CMIOExtensionStream(
				localizedName: localizedName,
				streamID: UUID(),
				direction: owner.direction,
				clockType: .hostTime,
				source: owner
			)
			owner.stream = stream
			do {
				try device.addStream(stream)
			} catch {
				camfeedLog("device: addStream failed: \(error.localizedDescription)")
			}
		}
	}

	var availableProperties: Set<CMIOExtensionProperty> {
		[.deviceModel, .deviceTransportType, .deviceIsSuspended]
	}

	func deviceProperties(
		forProperties properties: Set<CMIOExtensionProperty>
	) throws -> CMIOExtensionDeviceProperties {
		let propertiesDictionary = CMIOExtensionDeviceProperties(dictionary: [:])
		if properties.contains(.deviceModel) {
			propertiesDictionary.model = model
		}
		if properties.contains(.deviceTransportType) {
			propertiesDictionary.transportType = virtualTransportType
		}
		if properties.contains(.deviceIsSuspended) {
			propertiesDictionary.suspended = false
		}
		return propertiesDictionary
	}

	func setDeviceProperties(_ deviceProperties: CMIOExtensionDeviceProperties) throws {}
}
