//
//  main.swift
//  Camfeed camera extension entry point.
//

import CoreMediaIO
import Foundation

final class ProviderSource: NSObject, CMIOExtensionProviderSource {
	private(set) var devices: [CameraDevice]

	init(devices: [CameraDevice]) {
		self.devices = devices
		super.init()
	}

	var availableProperties: Set<CMIOExtensionProperty> {
		[.providerName, .providerManufacturer]
	}

	func providerProperties(
		forProperties properties: Set<CMIOExtensionProperty>
	) throws -> CMIOExtensionProviderProperties {
		let providerProperties = CMIOExtensionProviderProperties(dictionary: [:])
		if properties.contains(.providerName) {
			providerProperties.name = "Camfeed"
		}
		if properties.contains(.providerManufacturer) {
			providerProperties.manufacturer = "Camfeed"
		}
		return providerProperties
	}

	func setProviderProperties(_ providerProperties: CMIOExtensionProviderProperties) throws {}

	func connect(to client: CMIOExtensionClient) throws {
		camfeedLog("provider: client connected")
	}

	func disconnect(from client: CMIOExtensionClient) {
		camfeedLog("provider: client disconnected")
	}
}

let frames = LatestFrame()
let output = CameraDevice(
	localizedName: "Camfeed Camera",
	model: "Camfeed",
	owners: [CameraStreamSource(frames: frames)]
)
let input = CameraDevice(
	localizedName: "Camfeed Input",
	model: "CamfeedInput",
	owners: [CameraSinkStream(frames: frames)]
)
let providerSource = ProviderSource(devices: [output, input])

let provider = CMIOExtensionProvider(source: providerSource, clientQueue: nil)

for device in providerSource.devices {
	do {
		try provider.addDevice(device.device)
	} catch {
		camfeedLog("provider: addDevice failed: \(error.localizedDescription)")
		exit(1)
	}
}

camfeedLog("provider: publishing \(providerSource.devices.count) devices")
CMIOExtensionProvider.startService(provider: provider)
camfeedLog("provider: service started")
CFRunLoopRun()
