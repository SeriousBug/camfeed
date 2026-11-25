//
//  CameraCapture.swift
//  Runs an AVCaptureSession on the iPhone camera and hands its frames to the camera extension.
//

import AVFoundation
import Foundation

final class CameraCapture: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
	enum State: Equatable {
		case idle
		case running(String)
		case needsPermission
		case failed(String)
	}

	private let session = AVCaptureSession()
	private let queue = DispatchQueue(label: "dev.bgenc.camfeed.capture")
	private let sink = SinkWriter()
	private var currentInput: AVCaptureDeviceInput?
	private var currentDevice: AVCaptureDevice?

	private(set) var state: State = .idle {
		didSet {
			guard state != oldValue else { return }
			DispatchQueue.main.async { self.onStateChange?() }
		}
	}

	var onStateChange: (() -> Void)?

	override init() {
		super.init()
		NotificationCenter.default.addObserver(
			forName: .AVCaptureSessionRuntimeError,
			object: session,
			queue: .main
		) { [weak self] notification in
			guard let error = notification.userInfo?[AVCaptureSessionErrorKey] as? Error else { return }
			camfeedLog("capture: runtime error: \(error.localizedDescription)")
			self?.state = .failed(error.localizedDescription)
		}
	}

	/// Camera access can be granted in System Settings while the app is running.
	func clearPermissionFailure() {
		if case .needsPermission = state, hasCameraPermission {
			state = .idle
		}
	}

	/// Continuity cameras first: those are what this app exists for. The extension's own device is
	/// filtered out, or picking it would feed the virtual camera into itself.
	static func availableCameras() -> [AVCaptureDevice] {
		let session = AVCaptureDevice.DiscoverySession(
			deviceTypes: [.continuityCamera, .external, .builtInWideAngleCamera, .deskViewCamera],
			mediaType: .video,
			position: .unspecified
		)
		return session.devices
			.filter { !Self.virtualCameraModels.contains($0.modelID) }
			.sorted { first, second in
				if first.isContinuityCamera != second.isContinuityCamera {
					return first.isContinuityCamera
				}
				return first.localizedName.localizedCompare(second.localizedName) == .orderedAscending
			}
	}

	static let virtualCameraModel = "Camfeed"
	static let virtualCameraModels: Set<String> = [virtualCameraModel, "CamfeedInput"]

	var runningDeviceID: String? { currentDevice?.uniqueID }

	/// True once the user has granted camera access, which they may do after the app asked.
	var hasCameraPermission: Bool {
		AVCaptureDevice.authorizationStatus(for: .video) == .authorized
	}

	func start(_ device: AVCaptureDevice) {
		let status = AVCaptureDevice.authorizationStatus(for: .video)
		guard status == .authorized else {
			if status == .notDetermined {
				requestAccess { [weak self] granted in
					guard let self else { return }
					if granted {
						self.start(device)
					} else {
						self.state = .needsPermission
					}
				}
			} else {
				camfeedLog("capture: camera access is \(status == .restricted ? "restricted" : "denied")")
				state = .needsPermission
			}
			return
		}

		queue.async { [self] in
			if currentDevice?.uniqueID == device.uniqueID, session.isRunning {
				camfeedLog("capture: already running on \(device.localizedName)")
				state = .running(device.localizedName)
				return
			}
			camfeedLog("capture: starting \(device.localizedName)")
			session.beginConfiguration()
			if session.canSetSessionPreset(.high) {
				session.sessionPreset = .high
			}

			if let existing = currentInput {
				session.removeInput(existing)
				currentInput = nil
			}
			do {
				let input = try AVCaptureDeviceInput(device: device)
				guard session.canAddInput(input) else {
					session.commitConfiguration()
					state = .failed("\(device.localizedName) cannot be added")
					return
				}
				session.addInput(input)
				currentInput = input
				currentDevice = device
			} catch {
				session.commitConfiguration()
				state = .failed(error.localizedDescription)
				camfeedLog("capture: input failed: \(error.localizedDescription)")
				return
			}

			if session.outputs.isEmpty {
				let output = AVCaptureVideoDataOutput()
				output.alwaysDiscardsLateVideoFrames = true
				output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
				output.setSampleBufferDelegate(self, queue: queue)
				if session.canAddOutput(output) {
					session.addOutput(output)
				}
			}
			session.commitConfiguration()

			if !session.isRunning {
				session.startRunning()
			}
			guard session.isRunning else {
				state = .failed("\(device.localizedName) did not start")
				return
			}
			camfeedLog("capture: running on \(device.localizedName)")
			state = .running(device.localizedName)
		}
	}

	func stop() {
		queue.async { [self] in
			if session.isRunning {
				session.stopRunning()
			}
			sink.stop()
			state = .idle
		}
	}

	private func requestAccess(_ completion: @escaping (Bool) -> Void) {
		camfeedLog("capture: asking for camera access")
		AVCaptureDevice.requestAccess(for: .video) { granted in
			camfeedLog("capture: camera access granted: \(granted)")
			completion(granted)
		}
	}

	func captureOutput(
		_ output: AVCaptureOutput,
		didOutput sampleBuffer: CMSampleBuffer,
		from connection: AVCaptureConnection
	) {
		guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
		guard sink.startIfNeeded() else { return }
		sink.write(pixelBuffer)
	}
}
