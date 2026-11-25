//
//  CameraCapture.swift
//  Runs an AVCaptureSession on the iPhone camera and hands its frames to FrameWriter.
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
	private let writer = FrameWriter()
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
		writer.open()
	}

	/// Continuity cameras first: those are what this app exists for.
	static func availableCameras() -> [AVCaptureDevice] {
		let session = AVCaptureDevice.DiscoverySession(
			deviceTypes: [.continuityCamera, .external, .builtInWideAngleCamera, .deskViewCamera],
			mediaType: .video,
			position: .unspecified
		)
		return session.devices.sorted { first, second in
			if first.isContinuityCamera != second.isContinuityCamera {
				return first.isContinuityCamera
			}
			return first.localizedName.localizedCompare(second.localizedName) == .orderedAscending
		}
	}

	var runningDeviceID: String? { currentDevice?.uniqueID }

	func start(_ device: AVCaptureDevice) {
		guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
			requestAccess { [weak self] granted in
				guard let self else { return }
				if granted {
					self.start(device)
				} else {
					self.state = .needsPermission
				}
			}
			return
		}

		queue.async { [self] in
			session.beginConfiguration()
			session.sessionPreset = .high

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
			camfeedLog("capture: running on \(device.localizedName)")
			state = .running(device.localizedName)
		}
	}

	func stop() {
		queue.async { [self] in
			if session.isRunning {
				session.stopRunning()
			}
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
		writer.write(pixelBuffer)
	}
}
