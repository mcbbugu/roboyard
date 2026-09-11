import AppKit

enum WindowOwner {
    struct Record {
        var layer: Int
        var owner: String
        var bounds: CGRect
    }

    static func quartzPoint(cocoa: CGPoint, primaryFrame: CGRect) -> CGPoint {
        CGPoint(x: cocoa.x, y: primaryFrame.maxY - cocoa.y)
    }

    static func records(from info: [[String: Any]]) -> [Record] {
        info.compactMap { w in
            let owner = w[kCGWindowOwnerName as String] as? String ?? ""
            guard let b = w[kCGWindowBounds as String] as? [String: Any],
                  let x = (b["X"] as? NSNumber)?.doubleValue,
                  let y = (b["Y"] as? NSNumber)?.doubleValue,
                  let width = (b["Width"] as? NSNumber)?.doubleValue,
                  let height = (b["Height"] as? NSNumber)?.doubleValue
            else { return nil }
            return Record(
                layer: w[kCGWindowLayer as String] as? Int ?? 0,
                owner: owner,
                bounds: CGRect(x: x, y: y, width: width, height: height)
            )
        }
    }

    static func name(
        atCocoa cocoa: CGPoint,
        primaryFrame: CGRect,
        windows: [Record],
        skip: Set<String>,
        fallback: String?
    ) -> String? {
        let q = quartzPoint(cocoa: cocoa, primaryFrame: primaryFrame)
        for w in windows {
            if w.layer != 0 { continue }
            if w.owner.isEmpty || skip.contains(w.owner) { continue }
            if w.bounds.contains(q) { return w.owner }
        }
        return fallback
    }

    @MainActor
    static func at(_ cocoa: CGPoint) -> String? {
        let fallback = NSWorkspace.shared.frontmostApplication?.localizedName
        let primary = NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.screens.first
        guard let primary else { return fallback }
        guard let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return fallback
        }
        return name(
            atCocoa: cocoa,
            primaryFrame: primary.frame,
            windows: records(from: raw),
            skip: ["RoboYard"],
            fallback: fallback
        )
    }
}
