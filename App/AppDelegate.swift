//
//  AppDelegate.swift
//  Menu bar shell: shows what is being published, lets the user pick a camera, manages the extension.
//

import AVFoundation
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
	private let capture = CameraCapture()
	private let watcher = ClientWatcher()
	private let installer = ExtensionInstaller()
	private var statusItem: NSStatusItem!
	private var cameras: [AVCaptureDevice] = []
	private var rescanTimer: Timer?
	private var preferredDeviceID: String?
	private var stopWorkItem: DispatchWorkItem?

	func applicationDidFinishLaunching(_ notification: Notification) {
		camfeedLog("app: launched")

		statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
		statusItem.button?.image = NSImage(systemSymbolName: "video.fill", accessibilityDescription: "Camfeed")
		statusItem.button?.image?.isTemplate = true
		let menu = NSMenu()
		menu.delegate = self
		statusItem.menu = menu

		capture.onStateChange = { [weak self] in
			self?.updateStatusIcon()
			self?.pollCameras()
		}
		installer.onStateChange = { [weak self] in
			self?.updateStatusIcon()
		}
		watcher.onChange = { [weak self] _ in
			self?.syncCaptureToViewers()
		}
		watcher.onDeviceListChange = { [weak self] in
			self?.pollCameras()
		}
		watcher.start()

		refreshCameras()
		installer.install()
		updateStatusIcon()

		rescanTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
			self?.pollCameras()
		}
	}

	func applicationWillTerminate(_ notification: Notification) {
		capture.stop()
	}

	private func pollCameras() {
		let previous = cameras.map(\.uniqueID)
		refreshCameras()
		if cameras.map(\.uniqueID) != previous {
			camfeedLog("app: cameras are \(cameras.map(\.localizedName).joined(separator: ", "))")
		}
		capture.clearPermissionFailure()

		if let runningID = capture.runningDeviceID, !cameras.contains(where: { $0.uniqueID == runningID }) {
			camfeedLog("app: \(runningID) went away")
			capture.stop()
		}
		watcher.refresh()
		syncCaptureToViewers()
	}

	/// The iPhone link is only held while something is watching, so the phone is not kept awake and
	/// does not reconnect for nothing. The grace period rides out a client restarting its stream.
	private func syncCaptureToViewers() {
		if watcher.isActive {
			stopWorkItem?.cancel()
			stopWorkItem = nil
			startPreferredCameraIfNeeded()
			return
		}
		guard capture.runningDeviceID != nil, stopWorkItem == nil else { return }
		let work = DispatchWorkItem { [weak self] in
			guard let self else { return }
			stopWorkItem = nil
			guard !watcher.isActive else { return }
			camfeedLog("capture: no viewer, releasing the camera")
			capture.stop()
		}
		stopWorkItem = work
		DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
	}

	private func refreshCameras() {
		cameras = CameraCapture.availableCameras()
	}

	private func startPreferredCameraIfNeeded() {
		guard capture.runningDeviceID == nil else { return }
		switch capture.state {
		case .running, .needsPermission:
			return
		case .idle, .failed:
			break
		}
		guard let device = cameras.first(where: { $0.uniqueID == preferredDeviceID }) ?? cameras.first else {
			return
		}
		capture.start(device)
	}

	private func updateStatusIcon() {
		let symbol: String
		switch capture.state {
		case .running:
			symbol = "video.fill"
		case .idle:
			symbol = "video"
		case .needsPermission, .failed:
			symbol = "video.slash"
		}
		statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Camfeed")
		statusItem.button?.image?.isTemplate = true
	}

	// MARK: - Menu

	func menuNeedsUpdate(_ menu: NSMenu) {
		menu.removeAllItems()

		switch capture.state {
		case let .running(name):
			menu.addItem(disabled: "Publishing \(name)")
		case .idle:
			if cameras.isEmpty {
				menu.addItem(disabled: "No camera found")
			} else {
				menu.addItem(disabled: "Waiting for an app to use the camera")
			}
		case .needsPermission:
			menu.addItem(disabled: "Camera access denied")
			menu.addItem(NSMenuItem(title: "Open Camera Privacy Settings", action: #selector(openCameraPrivacy), keyEquivalent: ""))
		case let .failed(reason):
			menu.addItem(disabled: "Capture failed: \(reason)")
		}

		menu.addItem(.separator())

		if cameras.isEmpty {
			menu.addItem(disabled: "No iPhone camera detected")
		} else {
			for device in cameras {
				let item = NSMenuItem(title: device.localizedName, action: #selector(selectCamera(_:)), keyEquivalent: "")
				item.target = self
				item.representedObject = device.uniqueID
				item.state = device.uniqueID == capture.runningDeviceID ? .on : .off
				menu.addItem(item)
			}
		}

		menu.addItem(.separator())

		switch installer.state {
		case .active:
			menu.addItem(disabled: "Camera extension enabled")
		case .installing:
			menu.addItem(disabled: "Installing camera extension…")
		case .needsApproval:
			menu.addItem(disabled: "Approve Camfeed in System Settings")
			menu.addItem(NSMenuItem(title: "Open Camera Extensions Settings", action: #selector(openExtensionSettings), keyEquivalent: ""))
		case .willActivateAfterReboot:
			menu.addItem(disabled: "Camera extension activates after reboot")
		case let .failed(reason):
			menu.addItem(disabled: "Camera extension failed: \(reason)")
			menu.addItem(NSMenuItem(title: "Retry Camera Extension Install", action: #selector(installExtension), keyEquivalent: ""))
		case .unknown:
			menu.addItem(NSMenuItem(title: "Enable Camera Extension", action: #selector(installExtension), keyEquivalent: ""))
		}

		menu.addItem(NSMenuItem(title: "Show Log", action: #selector(showLog), keyEquivalent: ""))
		menu.addItem(.separator())
		menu.addItem(NSMenuItem(title: "Quit Camfeed", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
	}

	@objc private func selectCamera(_ sender: NSMenuItem) {
		guard let id = sender.representedObject as? String,
		      let device = cameras.first(where: { $0.uniqueID == id }) else { return }
		camfeedLog("app: selected \(device.localizedName)")
		preferredDeviceID = id
		capture.start(device)
	}

	@objc private func installExtension() {
		installer.install()
	}

	@objc private func openExtensionSettings() {
		open("x-apple.systempreferences:com.apple.LoginItems-Settings.extension")
	}

	@objc private func openCameraPrivacy() {
		open("x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")
	}

	@objc private func showLog() {
		guard let container = FileManager.default
			.containerURL(forSecurityApplicationGroupIdentifier: camfeedGroupIdentifier) else { return }
		NSWorkspace.shared.open(container)
	}

	private func open(_ urlString: String) {
		guard let url = URL(string: urlString) else { return }
		NSWorkspace.shared.open(url)
	}
}

private extension NSMenu {
	func addItem(disabled title: String) {
		let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
		item.isEnabled = false
		addItem(item)
	}
}
