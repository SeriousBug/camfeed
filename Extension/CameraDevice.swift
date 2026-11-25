//
//  CameraDevice.swift
//  The single virtual device the extension publishes, with one BGRA video stream.
//

import CoreMediaIO
import Foundation

/// Audio transport type fourcc from IOKit/audio/IOAudioTypes.h: virtual hardware.
private let virtualTransportType = 0x7669_7274 // 'virt'

final class CameraDevice: NSObject, CMIOExtensionDeviceSource {
	private(set) var device: CMIOExtensionDevice!
	private(set) var streamSource: CameraStreamSource!

	init(localizedName: String) {
		super.init()
		let streamSource = CameraStreamSource()
		self.streamSource = streamSource

		let stream = CMIOExtensionStream(
			localizedName: localizedName,
			streamID: UUID(),
			direction: .source,
			clockType: .hostTime,
			source: streamSource
		)
		streamSource.stream = stream

		device = CMIOExtensionDevice(
			localizedName: localizedName,
			deviceID: UUID(),
			legacyDeviceID: nil,
			source: self
		)
		do {
			try device.addStream(stream)
		} catch {
			camfeedLog("device: addStream failed: \(error.localizedDescription)")
		}
	}

	var availableProperties: Set<CMIOExtensionProperty> {
		[.deviceModel, .deviceTransportType, .deviceIsSuspended]
	}

	func deviceProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionDeviceProperties {
		let propertiesDictionary = CMIOExtensionDeviceProperties(dictionary: [:])
		if properties.contains(.deviceModel) {
			propertiesDictionary.model = "Camfeed"
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
