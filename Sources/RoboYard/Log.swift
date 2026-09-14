import Foundation

/// 4.0 observability: timestamped file log with rotation. Failures must leave a trace.
enum Log {
    static let maxBytes = 256 * 1024

    static func directory() -> URL {
        URL.applicationSupportDirectory.appendingPathComponent("RoboYard", isDirectory: true)
    }

    static func fileURL(in dir: URL? = nil) -> URL {
        (dir ?? directory()).appendingPathComponent("logs.txt")
    }

    static func formatted(_ message: String, date: Date = .now) -> String {
        let stamp = ISO8601DateFormatter().string(from: date)
        return "[\(stamp)] \(message)\n"
    }

    static func needsRotation(size: Int) -> Bool { size > maxBytes }

    static func add(_ message: String, in dir: URL? = nil) {
        let url = fileURL(in: dir)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: url.path),
               let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int,
               needsRotation(size: size) {
                let prev = url.deletingLastPathComponent().appendingPathComponent("logs-prev.txt")
                try? FileManager.default.removeItem(at: prev)
                try? FileManager.default.moveItem(at: url, to: prev)
            }
            if !FileManager.default.fileExists(atPath: url.path) {
                try Data().write(to: url, options: .atomic)
            }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(formatted(message).utf8))
        } catch {
            // Logging must never crash the app; UI already surfaces save errors.
        }
    }
}
