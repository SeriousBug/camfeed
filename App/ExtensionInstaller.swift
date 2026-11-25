//
//  ExtensionInstaller.swift
//  Submits the camera extension for activation and tracks what the system did with it.
//

import Foundation
import SystemExtensions

final class ExtensionInstaller: NSObject, OSSystemExtensionRequestDelegate {
	static let identifier = "dev.bgenc.camfeed.camera"

	enum State: Equatable {
		case unknown
		case installing
		case needsApproval
		case active
		case willActivateAfterReboot
		case failed(String)
	}

	private(set) var state: State = .unknown {
		didSet {
			guard state != oldValue else { return }
			DispatchQueue.main.async { self.onStateChange?() }
		}
	}

	var onStateChange: (() -> Void)?

	func install() {
		state = .installing
		let request = OSSystemExtensionRequest.activationRequest(
			forExtensionWithIdentifier: Self.identifier,
			queue: .main
		)
		request.delegate = self
		OSSystemExtensionManager.shared.submitRequest(request)
		camfeedLog("extension: activation requested")
	}

	func uninstall() {
		let request = OSSystemExtensionRequest.deactivationRequest(
			forExtensionWithIdentifier: Self.identifier,
			queue: .main
		)
		request.delegate = self
		OSSystemExtensionManager.shared.submitRequest(request)
		camfeedLog("extension: deactivation requested")
	}

	func request(
		_ request: OSSystemExtensionRequest,
		actionForReplacingExtension existing: OSSystemExtensionProperties,
		withExtension extension: OSSystemExtensionProperties
	) -> OSSystemExtensionRequest.ReplacementAction {
		.replace
	}

	func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
		camfeedLog("extension: waiting for approval in System Settings")
		state = .needsApproval
	}

	func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
		switch result {
		case .completed:
			camfeedLog("extension: activated")
			state = .active
		case .willCompleteAfterReboot:
			camfeedLog("extension: activates after reboot")
			state = .willActivateAfterReboot
		@unknown default:
			state = .unknown
		}
	}

	func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
		camfeedLog("extension: failed: \(error.localizedDescription)")
		state = .failed(error.localizedDescription)
	}
}
