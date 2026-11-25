//
//  CamfeedLog.swift
//  A line log both targets append to, in the shared group container. System extensions are hard to
//  observe from outside, so failures leave a trace here.
//

import Foundation
import os

let camfeedGroupIdentifier = "63QQLP356Q.dev.bgenc.camfeed"

private let camfeedLogger = Logger(subsystem: "dev.bgenc.camfeed", category: "camfeed")

func camfeedLog(_ message: String) {
	camfeedLogger.log("\(message, privacy: .public)")
	guard let url = FileManager.default
		.containerURL(forSecurityApplicationGroupIdentifier: camfeedGroupIdentifier)?
		.appendingPathComponent("camfeed.log") else { return }
	let formatter = ISO8601DateFormatter()
	let line = "\(formatter.string(from: Date())) [\(ProcessInfo.processInfo.processName)] \(message)\n"
	guard let data = line.data(using: .utf8) else { return }
	if let handle = try? FileHandle(forWritingTo: url) {
		handle.seekToEndOfFile()
		handle.write(data)
		try? handle.close()
	} else {
		try? data.write(to: url, options: .atomic)
	}
}
