import AppKit
import SwiftUI

// Render the actual journal view against an isolated, synthetic memory store.
@main struct JournalPreview {
    @MainActor static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let store = RobotMemoryStore(fileURL: directory.appendingPathComponent("fixture/memories.json"))
        let events = ["和2号撞在了一起", "嘿，你也喜欢沿着屏幕边缘散步吗？", "鼠标靠得太近，我跑开了"]
        for id in 1...3 {
            let robot = store.profile(id: id)
            for index in 0..<(id * 9) {
                robot.remember(.speech, detail: events[index % 3], now: Date(timeIntervalSince1970: 1_700_000_000 + Double(index) * 30))
            }
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 680), styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        let view = NSHostingView(rootView: RobotJournalView(store: store))
        window.contentView = view
        view.frame = NSRect(x: 0, y: 0, width: 620, height: 680)
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.5))
        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: rep)
        try rep.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("journal.png"))
    }
}
