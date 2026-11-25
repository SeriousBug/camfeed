//
//  CamfeedPaths.swift
//  Where the app and the camera extension meet. The extension is launched by the CMIO daemon as
//  _cmiodalassistants, and its own group container lands under that daemon's home, which the user
//  cannot enter. Group containers are per-user and 0700, so the user's container is equally closed
//  to the extension. /Users/Shared is the one place both uids can traverse, and the extension gets
//  a sandbox exception for it in Config/CamfeedCamera.entitlements.
//

import Foundation

enum CamfeedPaths {
	static let sharedDirectory = URL(fileURLWithPath: "/Users/Shared/Camfeed", isDirectory: true)

	static var ringFile: URL {
		sharedDirectory.appendingPathComponent("camera.ring")
	}

	static var logFile: URL {
		sharedDirectory.appendingPathComponent("camfeed.log")
	}

	/// Each process may create the directory, so keep it writable by the other one.
	static func prepareDirectory() {
		try? FileManager.default.createDirectory(at: sharedDirectory, withIntermediateDirectories: true)
		try? FileManager.default.setAttributes([.posixPermissions: 0o777], ofItemAtPath: sharedDirectory.path)
	}
}
