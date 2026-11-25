//
//  main.swift
//  Camfeed camera extension entry point.
//

import CoreMediaIO
import Foundation

final class ProviderSource: NSObject, CMIOExtensionProviderSource {
	private(set) var device: CameraDevice

	init(device: CameraDevice) {
		self.device = device
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

let device = CameraDevice(localizedName: "Camfeed Camera")
let providerSource = ProviderSource(device: device)

let provider = CMIOExtensionProvider(source: providerSource, clientQueue: nil)

do {
	try provider.addDevice(device.device)
} catch {
	camfeedLog("provider: addDevice failed: \(error.localizedDescription)")
	exit(1)
}

CMIOExtensionProvider.startService(provider: provider)
camfeedLog("provider: service started")
CFRunLoopRun()
