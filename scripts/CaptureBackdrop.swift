import AppKit

// A clean background for recording the real running app. This draws no robots.
@main struct CaptureBackdrop {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let screen = NSScreen.main!
        let window = NSWindow(contentRect: screen.visibleFrame, styleMask: .borderless, backing: .buffered, defer: false)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.contentView = Backdrop(frame: NSRect(origin: .zero, size: screen.visibleFrame.size))
        window.level = NSWindow.Level(rawValue: 2) // Below the app's floating robots.
        window.orderFrontRegardless()
        let box = screen.visibleFrame
        print("\(Int(box.minX)),\(Int(screen.frame.maxY - box.maxY)),\(Int(box.width)),\(Int(box.height))")
        fflush(stdout)
        app.run()
    }
}
final class Backdrop: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor(red: 0.06, green: 0.075, blue: 0.115, alpha: 1).setFill()
        bounds.fill()
        let ink = NSColor(white: 0.28, alpha: 1)
        let grid = NSBezierPath()
        for x in stride(from: CGFloat(0), through: bounds.width, by: 36) {
            for y in stride(from: CGFloat(0), through: bounds.height, by: 36) {
                grid.appendOval(in: NSRect(x: x, y: y, width: 1.5, height: 1.5))
            }
        }
        ink.setFill(); grid.fill()
        label("RoboYard", x: 70, y: bounds.height - 145, size: 64, color: .white)
        label("Your desktop. Their playground.", x: 74, y: bounds.height - 190, size: 24, color: NSColor(white: 0.7, alpha: 1))
        label("ROAM   /   BUMP   /   CHAT   /   GROW", x: 74, y: 80, size: 16, color: NSColor(red: 0.7, green: 0.65, blue: 1, alpha: 1))
        label("LIVE APP CAPTURE · CLEAN RECORDING BACKDROP", x: 74, y: 52, size: 11, color: NSColor(white: 0.45, alpha: 1))
    }
    func label(_ text: String, x: CGFloat, y: CGFloat, size: CGFloat, color: NSColor) {
        (text as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: size, weight: .medium), .foregroundColor: color])
    }
}
